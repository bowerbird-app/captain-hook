# frozen_string_literal: true

module CaptainHook
  module Adapters
    # Base adapter for webhook signature verification
    # Each provider should implement their own adapter with specific verification logic
    class Base
      attr_reader :provider_config

      def initialize(provider_config)
        @provider_config = provider_config
      end

      # Verify the webhook signature
      # @param payload [String] The raw request body
      # @param headers [Hash] The request headers
      # @return [Boolean] true if signature is valid
      # @raise [NotImplementedError] Must be implemented by subclasses
      def verify_signature(payload:, headers:)
        raise NotImplementedError, "#{self.class} must implement #verify_signature"
      end

      # Extract timestamp from headers if available
      # @param headers [Hash] The request headers
      # @return [Integer, nil] Unix timestamp or nil
      def extract_timestamp(_headers)
        # Override in subclasses if provider includes timestamp
        nil
      end

      # Extract event ID from payload if available
      # @param payload [Hash] The parsed payload
      # @return [String, nil] Event ID or nil
      def extract_event_id(payload)
        # Common patterns: id, event_id, webhook_id
        payload["id"] || payload["event_id"] || payload["webhook_id"]
      end

      # Extract event type from payload
      # @param payload [Hash] The parsed payload
      # @return [String] Event type
      def extract_event_type(payload)
        # Common patterns: type, event_type, event
        payload["type"] || payload["event_type"] || payload["event"] || "unknown"
      end

      protected

      # Constant-time string comparison to prevent timing attacks
      def secure_compare(a, b)
        return false if a.blank? || b.blank? || a.bytesize != b.bytesize

        l = a.unpack "C#{a.bytesize}"
        res = 0
        b.each_byte { |byte| res |= byte ^ l.shift }
        res.zero?
      end

      # Generate HMAC signature
      def generate_hmac(secret, data)
        OpenSSL::HMAC.hexdigest("SHA256", secret, data)
      end
    end
  end
end
