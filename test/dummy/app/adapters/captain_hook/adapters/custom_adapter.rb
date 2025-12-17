# frozen_string_literal: true

module CaptainHook
  module Adapters
    # Example custom adapter for application-specific webhook providers
    # Place your custom adapters in app/adapters/captain_hook/adapters/
    class CustomAdapter < Base
      # Verify webhook signature
      # @param payload [String] Raw request body
      # @param headers [Hash] Request headers
      # @return [Boolean] true if signature is valid
      def verify_signature(payload:, headers:)
        # Example: Simple HMAC-SHA256 verification
        signature_header = headers["X-Custom-Signature"]
        return false if signature_header.blank?

        expected_signature = generate_signature(payload)
        ActiveSupport::SecurityUtils.secure_compare(signature_header, expected_signature)
      end

      # Extract event type from webhook payload
      # @param payload [Hash] Parsed webhook payload
      # @return [String] Event type identifier
      def extract_event_type(payload)
        payload.dig("event", "type") || "unknown"
      end

      # Extract event ID from webhook payload (optional)
      # @param payload [Hash] Parsed webhook payload
      # @return [String, nil] Event ID if available
      def extract_event_id(payload)
        payload.dig("event", "id")
      end

      # Extract timestamp from webhook payload (optional)
      # Used for timestamp validation if timestamp_tolerance_seconds is set
      # @param payload [Hash] Parsed webhook payload
      # @return [Time, nil] Event timestamp if available
      def extract_timestamp(payload)
        timestamp = payload.dig("event", "timestamp")
        Time.at(timestamp) if timestamp
      end

      private

      # Generate HMAC signature for verification
      def generate_signature(payload)
        OpenSSL::HMAC.hexdigest("SHA256", signing_secret, payload)
      end
    end
  end
end
