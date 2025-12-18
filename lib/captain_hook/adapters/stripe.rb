# frozen_string_literal: true

module CaptainHook
  module Adapters
    # Stripe webhook signature verification adapter
    # Implements Stripe's webhook signature verification scheme
    # https://stripe.com/docs/webhooks/signatures
    class Stripe < Base
      SIGNATURE_HEADER = "Stripe-Signature"
      TIMESTAMP_TOLERANCE = 300 # 5 minutes

      # Verify Stripe webhook signature
      # Stripe sends signature as: t=timestamp,v1=signature
      def verify_signature(payload:, headers:)
        signature_header = headers[SIGNATURE_HEADER] || headers[SIGNATURE_HEADER.downcase]
        return false if signature_header.blank?

        timestamp, signatures = parse_signature_header(signature_header)
        return false if timestamp.blank? || signatures.empty?

        # Check timestamp tolerance
        if provider_config.timestamp_validation_enabled?
          tolerance = provider_config.timestamp_tolerance_seconds || TIMESTAMP_TOLERANCE
          return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
        end

        # Generate expected signature
        signed_payload = "#{timestamp}.#{payload}"
        expected_signature = generate_hmac(provider_config.signing_secret, signed_payload)

        # Check if any of the signatures match (Stripe sends both v1 and v0 sometimes)
        signatures.any? { |sig| secure_compare(sig, expected_signature) }
      end

      # Extract timestamp from Stripe signature header
      def extract_timestamp(headers)
        signature_header = headers[SIGNATURE_HEADER] || headers[SIGNATURE_HEADER.downcase]
        return nil if signature_header.blank?

        timestamp, = parse_signature_header(signature_header)
        timestamp&.to_i
      end

      # Extract event ID from Stripe payload
      def extract_event_id(payload)
        payload["id"]
      end

      # Extract event type from Stripe payload
      def extract_event_type(payload)
        payload["type"]
      end

      private

      # Parse Stripe signature header
      # Format: t=timestamp,v1=signature,v0=old_signature
      def parse_signature_header(header)
        elements = header.split(",")
        timestamp = nil
        signatures = []

        elements.each do |element|
          key, value = element.split("=", 2)
          case key
          when "t"
            timestamp = value
          when "v1", "v0"
            signatures << value
          end
        end

        [timestamp, signatures]
      end

      # Check if timestamp is within tolerance
      def timestamp_within_tolerance?(timestamp, tolerance)
        current_time = Time.current.to_i
        (current_time - timestamp).abs <= tolerance
      end
    end
  end
end
