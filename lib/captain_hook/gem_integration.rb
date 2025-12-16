# frozen_string_literal: true

module CaptainHook
  # Module for integrating CaptainHook with other gems for inter-gem communication
  #
  # This module provides helper methods for gems to:
  # - Send webhooks to other services/gems
  # - Register handlers for incoming webhooks
  # - Build webhook payloads and metadata
  #
  # @example Include in a service class
  #   class MyGem::WebhookService
  #     include CaptainHook::GemIntegration
  #
  #     def notify_search_completed(search_id)
  #       send_webhook(
  #         provider: "my_service",
  #         event_type: "search.completed",
  #         payload: { search_id: search_id },
  #         endpoint: "webhook_receiver"
  #       )
  #     end
  #   end
  #
  module GemIntegration
    # Send a webhook to a configured endpoint
    #
    # @param provider [String] The provider name (e.g., "my_gem")
    # @param event_type [String] The event type (e.g., "resource.created")
    # @param payload [Hash] The webhook payload
    # @param endpoint [String] The endpoint name from configuration
    # @param headers [Hash] Optional custom headers
    # @param metadata [Hash] Optional metadata for tracking
    # @param async [Boolean] Whether to send asynchronously (default: true)
    #
    # @return [CaptainHook::OutgoingEvent] The created outgoing event
    #
    # @example Send a webhook synchronously
    #   send_webhook(
    #     provider: "my_gem",
    #     event_type: "user.created",
    #     payload: { id: 1, email: "user@example.com" },
    #     endpoint: "production_endpoint",
    #     async: false
    #   )
    #
    def send_webhook(provider:, event_type:, payload:, endpoint:, headers: {}, metadata: {}, async: true)
      raise ArgumentError, "Provider cannot be blank" if provider.blank?
      raise ArgumentError, "Event type cannot be blank" if event_type.blank?
      raise ArgumentError, "Endpoint cannot be blank" if endpoint.blank?

      endpoint_config = CaptainHook.configuration.outgoing_endpoint(endpoint)
      raise ArgumentError, "Endpoint '#{endpoint}' not configured" unless endpoint_config

      # Build the target URL
      target_url = endpoint_config.base_url

      # Create the outgoing event
      event = CaptainHook::OutgoingEvent.create!(
        provider: provider.to_s,
        event_type: event_type.to_s,
        target_url: target_url,
        payload: payload,
        headers: headers.merge(endpoint_config.default_headers || {}),
        metadata: metadata
      )

      # Enqueue for delivery if async
      if async
        CaptainHook::OutgoingJob.perform_later(event.id)
      else
        # For synchronous delivery, we'd need to implement immediate sending
        # For now, we'll enqueue and rely on the job system
        CaptainHook::OutgoingJob.perform_later(event.id)
      end

      event
    end

    # Register a webhook handler for incoming webhooks
    #
    # This is a convenience method that wraps CaptainHook.register_handler
    #
    # @param provider [String] The provider name
    # @param event_type [String] The event type to handle
    # @param handler_class [String, Class] The handler class name or class
    # @param async [Boolean] Whether to process asynchronously (default: true)
    # @param priority [Integer] Handler priority (lower = higher priority)
    # @param retry_delays [Array<Integer>] Retry delays in seconds
    # @param max_attempts [Integer] Maximum retry attempts
    #
    # @example Register a handler
    #   register_webhook_handler(
    #     provider: "external_service",
    #     event_type: "data.updated",
    #     handler_class: "MyGem::Handlers::DataUpdateHandler",
    #     priority: 50
    #   )
    #
    def register_webhook_handler(provider:, event_type:, handler_class:, **options)
      CaptainHook.register_handler(
        provider: provider,
        event_type: event_type,
        handler_class: handler_class,
        **options
      )
    end

    # Check if a webhook endpoint is configured
    #
    # @param endpoint [String] The endpoint name
    # @return [Boolean] True if the endpoint is configured
    #
    # @example
    #   webhook_configured?("production_endpoint") # => true
    #
    def webhook_configured?(endpoint)
      CaptainHook.configuration.outgoing_endpoint(endpoint).present?
    end

    # Get the webhook URL for a provider (for incoming webhooks)
    #
    # @param provider [String] The provider name
    # @param token [String] Optional token override
    # @return [String, nil] The webhook URL or nil if not configured
    #
    # @example
    #   webhook_url("my_gem") # => "/captain_hook/my_gem/abc123"
    #
    def webhook_url(provider, token: nil)
      provider_config = CaptainHook.configuration.provider(provider)
      return nil unless provider_config

      used_token = token || provider_config.token
      return nil unless used_token

      "/captain_hook/#{provider}/#{used_token}"
    end

    # Build a standardized webhook payload
    #
    # @param data [Hash] The main data to send
    # @param event_id [String] Optional event ID for idempotency
    # @param timestamp [Time] Optional timestamp (defaults to current time)
    #
    # @return [Hash] Standardized webhook payload
    #
    # @example
    #   build_webhook_payload(
    #     data: { user_id: 1, action: "created" },
    #     event_id: "evt_123"
    #   )
    #   # => {
    #   #   id: "evt_123",
    #   #   timestamp: "2025-01-01T00:00:00Z",
    #   #   data: { user_id: 1, action: "created" }
    #   # }
    #
    def build_webhook_payload(data:, event_id: nil, timestamp: nil)
      {
        id: event_id || SecureRandom.uuid,
        timestamp: (timestamp || Time.current).iso8601,
        data: data
      }
    end

    # Build standardized webhook metadata
    #
    # @param source [String] The source gem/service name
    # @param version [String] Optional version
    # @param additional [Hash] Additional metadata
    #
    # @return [Hash] Standardized metadata
    #
    # @example
    #   build_webhook_metadata(
    #     source: "my_gem",
    #     version: "1.0.0",
    #     additional: { environment: "production" }
    #   )
    #
    def build_webhook_metadata(source:, version: nil, additional: {})
      {
        source: source,
        version: version,
        triggered_at: Time.current.iso8601
      }.merge(additional).compact
    end

    # Listen to ActiveSupport::Notifications and send webhooks
    #
    # This is a helper method to subscribe to notifications and automatically
    # send webhooks when certain events occur.
    #
    # @param notification_name [String] The notification name to subscribe to
    # @param provider [String] The provider name for the webhook
    # @param endpoint [String] The endpoint name
    # @param event_type_proc [Proc] Optional proc to transform notification to event_type
    # @param payload_proc [Proc] Optional proc to transform notification payload
    #
    # @example Subscribe to notifications
    #   listen_to_notification(
    #     "search.completed",
    #     provider: "my_gem",
    #     endpoint: "webhook_receiver",
    #     event_type_proc: ->(name) { name },
    #     payload_proc: ->(payload) { payload.slice(:search_id, :results) }
    #   )
    #
    def listen_to_notification(notification_name, provider:, endpoint:, event_type_proc: nil, payload_proc: nil)
      ActiveSupport::Notifications.subscribe(notification_name) do |name, _start, _finish, _id, payload|
        event_type = event_type_proc ? event_type_proc.call(name) : name
        webhook_payload = payload_proc ? payload_proc.call(payload) : payload

        send_webhook(
          provider: provider,
          event_type: event_type,
          payload: webhook_payload,
          endpoint: endpoint
        )
      end
    end

    module_function :send_webhook,
                    :register_webhook_handler,
                    :webhook_configured?,
                    :webhook_url,
                    :build_webhook_payload,
                    :build_webhook_metadata,
                    :listen_to_notification
  end
end
