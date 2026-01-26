# frozen_string_literal: true

module CaptainHook
  # Controller for receiving incoming webhooks
  # Route: POST /captain_hook/:provider/:token
  class IncomingController < ApplicationController
    include CaptainHook::VerifierHelpers

    skip_before_action :verify_authenticity_token

    # Receive a webhook from a provider
    def create
      provider_name = params[:provider]
      token = params[:token]

      request.body.rewind # Important: rewind after reading

      # Get provider from database first, then fall back to configuration
      provider = CaptainHook::Provider.find_by(name: provider_name)
      # Check if provider is active
      if provider && !provider.active?
        render json: { error: "Provider is inactive" }, status: :forbidden
        return
      end

      # Convert Provider model to ProviderConfig
      provider_config = CaptainHook.configuration.provider(provider_name)

      unless provider_config
        render json: { error: "Unknown provider" }, status: :not_found
        return
      end

      # Verify token (constant-time comparison to prevent timing attacks)
      unless secure_compare(provider_config.token.to_s, token.to_s)
        render json: { error: "Invalid token" }, status: :unauthorized
        return
      end

      # Check rate limiting
      if provider_config.rate_limiting_enabled?
        rate_limiter = CaptainHook::Services::RateLimiter.new

        begin
          rate_limiter.record!(
            provider: provider_name,
            limit: provider_config.rate_limit_requests,
            period: provider_config.rate_limit_period
          )
        rescue CaptainHook::Services::RateLimiter::RateLimitExceeded
          CaptainHook::Instrumentation.rate_limit_exceeded(
            provider: provider_name,
            current_count: provider_config.rate_limit_requests,
            limit: provider_config.rate_limit_requests
          )
          render json: { error: "Rate limit exceeded" }, status: :too_many_requests
          return
        end
      end

      # Check payload size
      if provider_config.payload_size_limit_enabled?
        payload_size = request.raw_post.bytesize

        if payload_size > provider_config.max_payload_size_bytes
          render json: { error: "Payload too large" }, status: :content_too_large
          return
        end
      end

      # Get raw payload and headers
      raw_payload = request.raw_post
      headers = extract_headers(request)

      # Verify signature using verifier
      verifier = provider_config.verifier

      unless verifier.verify_signature(payload: raw_payload, headers: headers, provider_config: provider_config)
        CaptainHook::Instrumentation.signature_failed(provider: provider_name, reason: "Invalid signature")
        render json: { error: "Invalid signature" }, status: :unauthorized
        return
      end

      CaptainHook::Instrumentation.signature_verified(provider: provider_name)

      begin
        parsed_payload = JSON.parse(raw_payload)
      rescue JSON::ParserError => e
        # Sanitize error message to prevent sensitive data leakage
        Rails.logger.error "🔍 JSON parse failed for provider=#{provider_name}"
        render json: { error: "Invalid JSON" }, status: :bad_request
        return
      end

      # Extract event details using verifier
      external_id = verifier.extract_event_id(parsed_payload)
      event_type = verifier.extract_event_type(parsed_payload)

      # Check timestamp if provided
      if provider_config.timestamp_validation_enabled?
        timestamp = verifier.extract_timestamp(headers)

        if timestamp
          validator = CaptainHook::TimeWindowValidator.new(
            tolerance_seconds: provider_config.timestamp_tolerance_seconds
          )

          unless validator.valid?(timestamp)
            Rails.logger.warn "🔍 Timestamp validation FAILED"
            render json: { error: "Timestamp outside tolerance window" }, status: :bad_request
            return
          end
        end
      end

      # Create or find incoming event (idempotency)
      event = CaptainHook::IncomingEvent.find_or_create_by_external!(
        provider: provider_name,
        external_id: external_id,
        event_type: event_type,
        payload: parsed_payload,
        headers: headers,
        metadata: { received_at: Time.current.iso8601 },
        status: :received,
        dedup_state: :unique,
        request_id: request.request_id
      )

      # Check if this is a duplicate
      if event.previously_new_record?
        # New event - create actions
        create_actions_for_event(event)

        CaptainHook::Instrumentation.incoming_received(
          event,
          provider: provider_name,
          event_type: event_type
        )

        render json: { id: event.id, status: "received" }, status: :created
      else
        # Duplicate event
        event.mark_duplicate!
        render json: { id: event.id, status: "duplicate" }, status: :ok
      end
    end

    private

    # Extract relevant headers from request
    def extract_headers(request)
      headers = {}

      request.headers.each do |key, value|
        # Extract HTTP headers (they start with HTTP_ or are CONTENT_TYPE/CONTENT_LENGTH)
        next unless key.start_with?("HTTP_") || key == "CONTENT_TYPE" || key == "CONTENT_LENGTH"

        # Convert HTTP_X_SOME_HEADER to X-Some-Header
        header_name = if key.start_with?("HTTP_")
                        key[5..].split("_").map(&:capitalize).join("-")
                      else
                        key.split("_").map(&:capitalize).join("-")
                      end

        headers[header_name] = value
      end

      headers
    end

    # Create action records for all registered actions
    def create_actions_for_event(event)
      action_configs = CaptainHook::Services::ActionLookup.actions_for(
        provider: event.provider,
        event_type: event.event_type
      )

      action_configs.each do |config|
        action = event.incoming_event_actions.create!(
          action_class: config.action_class.to_s,
          status: :pending,
          priority: config.priority,
          attempt_count: 0
        )

        # Enqueue job if async
        if config.async
          CaptainHook::IncomingActionJob.perform_later(action.id)
        else
          # Execute synchronously
          CaptainHook::IncomingActionJob.new.perform(action.id)
        end
      end
    end
  end
end
