# frozen_string_literal: true

module CaptainHook
  # Controller for receiving incoming webhooks
  # Route: POST /captain_hook/:provider/:token
  class IncomingController < ApplicationController
    skip_before_action :verify_authenticity_token

    # Receive a webhook from a provider
    def create
      provider_name = params[:provider]
      token = params[:token]

      # DEBUG: Log all incoming webhook details
      Rails.logger.info "🔍 ============================================"
      Rails.logger.info "🔍 WEBHOOK RECEIVED"
      Rails.logger.info "🔍 Provider: #{provider_name}"
      Rails.logger.info "🔍 Token: #{token}"
      Rails.logger.info "🔍 Headers: #{request.headers.to_h.select do |k, _v|
        k.start_with?('HTTP_', 'CONTENT_')
      end.inspect}"
      Rails.logger.info "🔍 Body (first 500 chars): #{request.body.read[0..500]}"
      request.body.rewind # Important: rewind after reading
      Rails.logger.info "🔍 ============================================"

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

      # Verify token
      unless provider_config.token == token
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
          render json: { error: "Payload too large" }, status: :payload_too_large
          return
        end
      end

      # Get raw payload and headers
      raw_payload = request.raw_post
      headers = extract_headers(request)

      # Verify signature using adapter
      adapter = provider_config.adapter

      unless adapter.verify_signature(payload: raw_payload, headers: headers)
        CaptainHook::Instrumentation.signature_failed(provider: provider_name, reason: "Invalid signature")
        render json: { error: "Invalid signature" }, status: :unauthorized
        return
      end

      CaptainHook::Instrumentation.signature_verified(provider: provider_name)

      # Parse payload
      Rails.logger.info "🔍 Parsing JSON payload..."
      begin
        parsed_payload = JSON.parse(raw_payload)
        Rails.logger.info "🔍 JSON parsed successfully"
      rescue JSON::ParserError => e
        Rails.logger.error "🔍 JSON parse failed: #{e.message}"
        render json: { error: "Invalid JSON" }, status: :bad_request
        return
      end

      # Extract event details using adapter
      Rails.logger.info "🔍 Extracting event metadata..."
      external_id = adapter.extract_event_id(parsed_payload)
      event_type = adapter.extract_event_type(parsed_payload)
      Rails.logger.info "🔍 Event ID: #{external_id}, Event Type: #{event_type}"

      # Check timestamp if provided
      if provider_config.timestamp_validation_enabled?
        Rails.logger.info "🔍 Validating timestamp..."
        timestamp = adapter.extract_timestamp(headers)
        Rails.logger.info "🔍 Extracted timestamp: #{timestamp}"

        if timestamp
          validator = CaptainHook::TimeWindowValidator.new(
            tolerance_seconds: provider_config.timestamp_tolerance_seconds
          )

          unless validator.valid?(timestamp)
            Rails.logger.warn "🔍 Timestamp validation FAILED"
            render json: { error: "Timestamp outside tolerance window" }, status: :bad_request
            return
          end
          Rails.logger.info "🔍 Timestamp validation passed"
        end
      end

      Rails.logger.info "🔍 Creating IncomingEvent record..."

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
        # New event - create handlers
        create_handlers_for_event(event)

        CaptainHook::Instrumentation.incoming_received(
          event,
          provider: provider_name,
          event_type: event_type
        )

        Rails.logger.info "🔍 Sending 201 Created response..."
        render json: { id: event.id, status: "received" }, status: :created
      else
        # Duplicate event
        event.mark_duplicate!
        Rails.logger.info "🔍 Sending 200 OK response (duplicate)..."
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

    # Create handler records for all registered handlers
    def create_handlers_for_event(event)
      handler_configs = CaptainHook.handler_registry.handlers_for(
        provider: event.provider,
        event_type: event.event_type
      )

      handler_configs.each do |config|
        handler = event.incoming_event_handlers.create!(
          handler_class: config.handler_class.to_s,
          status: :pending,
          priority: config.priority,
          attempt_count: 0
        )

        # Enqueue job if async
        if config.async
          CaptainHook::IncomingHandlerJob.perform_later(handler.id)
        else
          # Execute synchronously
          CaptainHook::IncomingHandlerJob.new.perform(handler.id)
        end
      end
    end
  end
end
