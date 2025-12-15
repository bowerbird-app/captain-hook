# frozen_string_literal: true

require "socket"

module CaptainHook
  # Helpers and utilities for integrating Captain Hook into other gems
  # Provides reusable methods for sending webhooks and managing configurations
  #
  # @example Include in your gem's service class
  #   class MyGem::WebhookService
  #     include CaptainHook::GemIntegration
  #
  #     def notify_event(resource)
  #       send_webhook(
  #         provider: "my_gem_webhooks",
  #         event_type: "resource.created",
  #         payload: { id: resource.id, name: resource.name }
  #       )
  #     end
  #   end
  #
  module GemIntegration
    # Send a webhook via Captain Hook with standard error handling
    #
    # @param provider [String] The provider/endpoint name registered in Captain Hook
    # @param event_type [String] The event type (e.g., "resource.created")
    # @param payload [Hash] The webhook payload data
    # @param target_url [String, nil] Optional explicit target URL (overrides endpoint config)
    # @param metadata [Hash] Additional metadata for tracking
    # @param headers [Hash] Additional HTTP headers
    # @param async [Boolean] Whether to enqueue the job asynchronously (default: true)
    # @return [CaptainHook::OutgoingEvent, nil] The created event record, or nil if failed
    #
    # @example Send a webhook
    #   send_webhook(
    #     provider: "my_gem_webhooks",
    #     event_type: "resource.created",
    #     payload: { id: 123, name: "Example" }
    #   )
    #
    def send_webhook(provider:, event_type:, payload:, target_url: nil, metadata: {}, headers: {}, async: true)
      # Determine target URL
      url = target_url || resolve_webhook_url(provider)

      unless url
        log_webhook_error("No target URL configured for provider: #{provider}")
        return nil
      end

      # Create the outgoing event
      event = CaptainHook::OutgoingEvent.create!(
        provider: provider.to_s,
        event_type: event_type.to_s,
        target_url: url,
        payload: payload,
        metadata: metadata.merge(default_metadata),
        headers: headers
      )

      # Enqueue for delivery
      if async
        CaptainHook::OutgoingJob.perform_later(event.id)
      else
        CaptainHook::OutgoingJob.perform_now(event.id)
      end

      log_webhook_sent(event)
      event
    rescue StandardError => e
      log_webhook_error("Failed to send webhook: #{e.message}")
      log_webhook_error(e.backtrace.first(3).join("\n"))
      nil
    end

    # Register a webhook handler for your gem
    # This is a convenience method that wraps CaptainHook.register_handler
    #
    # @param provider [String] The provider name
    # @param event_type [String] The event type to handle
    # @param handler_class [String, Class] The handler class (as string or constant)
    # @param options [Hash] Additional options (async, priority, retry_delays, max_attempts)
    # @return [void]
    #
    # @example Register a handler
    #   register_webhook_handler(
    #     provider: "external_provider",
    #     event_type: "resource.updated",
    #     handler_class: "MyGem::Handlers::ResourceUpdatedHandler",
    #     priority: 100
    #   )
    #
    def register_webhook_handler(provider:, event_type:, handler_class:, **options)
      CaptainHook.register_handler(
        provider: provider.to_s,
        event_type: event_type.to_s,
        handler_class: handler_class.to_s,
        **options
      )

      log_handler_registered(provider, event_type, handler_class)
    end

    # Check if a webhook endpoint is configured
    #
    # @param provider [String] The provider name
    # @return [Boolean] True if endpoint is configured
    #
    # @example Check if endpoint exists
    #   if webhook_configured?("my_gem_webhooks")
    #     send_webhook(...)
    #   end
    #
    def webhook_configured?(provider)
      endpoint = CaptainHook.configuration.outgoing_endpoint(provider.to_s)
      endpoint && endpoint.base_url.present?
    end

    # Get the configured webhook URL for a provider
    #
    # @param provider [String] The provider name
    # @return [String, nil] The webhook URL or nil if not configured
    #
    def webhook_url(provider)
      endpoint = CaptainHook.configuration.outgoing_endpoint(provider.to_s)
      endpoint&.base_url
    end

    # Build a standardized webhook payload
    #
    # @param resource [ActiveRecord::Base] The resource to serialize
    # @param additional_fields [Hash] Additional fields to include
    # @return [Hash] The webhook payload
    #
    # @example Build payload from ActiveRecord model
    #   payload = build_webhook_payload(
    #     user,
    #     additional_fields: { account_type: "premium" }
    #   )
    #
    def build_webhook_payload(resource, additional_fields: {})
      base_payload = {
        id: resource.id,
        created_at: resource.created_at&.iso8601,
        updated_at: resource.updated_at&.iso8601
      }

      # Add all attributes if resource responds to attributes
      if resource.respond_to?(:attributes)
        base_payload.merge!(resource.attributes.symbolize_keys)
      end

      base_payload.merge(additional_fields)
    end

    # Build metadata for webhook tracking
    #
    # @param additional_metadata [Hash] Additional metadata fields
    # @return [Hash] The metadata hash
    #
    def build_webhook_metadata(additional_metadata: {})
      default_metadata.merge(additional_metadata)
    end

    private

    # Resolve the webhook URL from configuration or environment
    #
    # @param provider [String] The provider name
    # @return [String, nil] The resolved URL
    def resolve_webhook_url(provider)
      # Try to get from Captain Hook configuration first
      endpoint = CaptainHook.configuration.outgoing_endpoint(provider.to_s)
      return endpoint.base_url if endpoint&.base_url

      # Fall back to environment variable
      env_var = "#{provider.upcase.tr('-', '_')}_WEBHOOK_URL"
      ENV[env_var]
    end

    # Default metadata included in all webhooks
    #
    # @return [Hash] Default metadata
    def default_metadata
      {
        environment: Rails.env,
        triggered_at: Time.current.iso8601,
        hostname: Socket.gethostname
      }
    rescue StandardError
      { environment: Rails.env, triggered_at: Time.current.iso8601 }
    end

    # Log webhook sent event
    #
    # @param event [CaptainHook::OutgoingEvent] The event record
    # @return [void]
    def log_webhook_sent(event)
      return unless defined?(Rails) && Rails.logger

      Rails.logger.info(
        "[CaptainHook] Webhook queued: #{event.event_type} " \
        "(Provider: #{event.provider}, Event ID: #{event.id})"
      )
    end

    # Log webhook error
    #
    # @param message [String] The error message
    # @return [void]
    def log_webhook_error(message)
      return unless defined?(Rails) && Rails.logger

      Rails.logger.error("[CaptainHook] #{message}")
    end

    # Log handler registration
    #
    # @param provider [String] The provider name
    # @param event_type [String] The event type
    # @param handler_class [String, Class] The handler class
    # @return [void]
    def log_handler_registered(provider, event_type, handler_class)
      return unless defined?(Rails) && Rails.logger

      Rails.logger.info(
        "[CaptainHook] Handler registered: #{provider}.#{event_type} -> #{handler_class}"
      )
    end

    # Make methods available as both instance and class methods
    # Note: Private methods will only be available to instance method calls
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Send a webhook via Captain Hook with standard error handling
      # This is a class method wrapper that creates an instance and calls the instance method
      def send_webhook(...)
        include CaptainHook::GemIntegration
        new.send_webhook(...)
      end

      def register_webhook_handler(...)
        CaptainHook.register_handler(...)
      end

      def webhook_configured?(provider)
        endpoint = CaptainHook.configuration.outgoing_endpoint(provider.to_s)
        endpoint && endpoint.base_url.present?
      end

      def webhook_url(provider)
        endpoint = CaptainHook.configuration.outgoing_endpoint(provider.to_s)
        endpoint&.base_url
      end

      def build_webhook_payload(resource, additional_fields: {})
        base_payload = {
          id: resource.id,
          created_at: resource.created_at&.iso8601,
          updated_at: resource.updated_at&.iso8601
        }

        if resource.respond_to?(:attributes)
          base_payload.merge!(resource.attributes.symbolize_keys)
        end

        base_payload.merge(additional_fields)
      end

      def build_webhook_metadata(additional_metadata: {})
        {
          environment: defined?(Rails) ? Rails.env : "development",
          triggered_at: Time.current.iso8601,
          hostname: Socket.gethostname
        }.merge(additional_metadata)
      rescue StandardError
        { environment: "unknown", triggered_at: Time.current.iso8601 }.merge(additional_metadata)
      end
    end
  end
end
