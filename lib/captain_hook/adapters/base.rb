# frozen_string_literal: true

module CaptainHook
  module Adapters
    # Base adapter class for webhook signature verification
    # All adapters should inherit from this class or implement the same interface
    class Base
      include CaptainHook::AdapterHelpers

      # Verify webhook signature
      # This is a no-op base implementation that always returns true
      # Override in subclasses to implement actual verification
      #
      # @param payload [String] Raw request body
      # @param headers [Hash] Request headers
      # @param provider_config [CaptainHook::Provider, CaptainHook::ProviderConfig] Provider configuration
      # @return [Boolean] True if signature is valid, false otherwise
      def verify_signature(payload:, headers:, provider_config:)
        # Base adapter accepts all webhooks without verification
        # Override this method in subclasses to implement actual verification
        _ = payload
        _ = headers
        _ = provider_config
        true
      end

      # Extract timestamp from webhook headers or payload
      # Override in subclasses if provider includes timestamp
      #
      # @param headers [Hash] Request headers
      # @return [Integer, nil] Unix timestamp or nil
      def extract_timestamp(headers)
        _ = headers
        nil
      end

      # Extract event ID from webhook payload
      # Override in subclasses to extract provider-specific event ID
      #
      # @param payload [Hash] Parsed JSON payload
      # @return [String, nil] Event ID or nil
      def extract_event_id(payload)
        payload["id"] || payload["event_id"] || SecureRandom.uuid
      end

      # Extract event type from webhook payload
      # Override in subclasses to extract provider-specific event type
      #
      # @param payload [Hash] Parsed JSON payload
      # @return [String] Event type
      def extract_event_type(payload)
        payload["type"] || payload["event_type"] || "webhook.received"
      end
    end
  end
end
