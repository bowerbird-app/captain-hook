# frozen_string_literal: true

module CaptainHook
  module Verifiers
    # Square webhook verifier
    # Implements Square's webhook signature verification
    # https://developer.squareup.com/docs/webhooks/step3validate
    class Square < Base
      SIGNATURE_HEADER = "X-Square-Signature"
      SIGNATURE_HMACSHA256_HEADER = "X-Square-Hmacsha256-Signature"

      # Verify Square webhook signature
      # Square signs webhooks with HMAC-SHA256 (Base64 encoded)
      def verify_signature(payload:, headers:, provider_config:)
        log_verification("square", "Verifying signature" => "started")

        # Square sends signature in X-Square-Hmacsha256-Signature (newer) or X-Square-Signature
        signature = extract_header(headers, SIGNATURE_HMACSHA256_HEADER) ||
                    extract_header(headers, SIGNATURE_HEADER)

        log_verification("square", "Signature" => signature.present? ? "present" : "missing")

        # Skip verification if signing secret not configured
        if skip_verification?(provider_config.signing_secret)
          log_verification("square", "Status" => "Skipping verification (no secret configured)")
          return true
        end

        if signature.blank?
          log_verification("square", "Status" => "No signature header found")
          return false
        end

        # Square uses HMAC-SHA256: notification_url + request_body
        notification_url = build_square_notification_url(provider_config)
        signed_payload = "#{notification_url}#{payload}"

        log_verification("square",
          "Notification URL" => notification_url,
          "Payload size" => "#{payload.bytesize} bytes")

        # Square expects Base64-encoded HMAC-SHA256
        expected_signature = generate_hmac_base64(provider_config.signing_secret, signed_payload)

        log_verification("square",
          "Expected" => "#{expected_signature[0..20]}...",
          "Received" => "#{signature[0..20]}...")

        result = secure_compare(signature, expected_signature)
        log_verification("square", "Result" => result ? "✓ Passed" : "✗ Failed")
        result
      end

      # Extract event ID from Square payload
      def extract_event_id(payload)
        payload.dig("event_id")
      end

      # Extract event type from Square payload
      def extract_event_type(payload)
        payload.dig("type")
      end

      private

      # Build the notification URL that Square uses for signature
      # This must match exactly what you configured in Square
      def build_square_notification_url(provider_config)
        # Try to get from environment or reconstruct
        return ENV["SQUARE_WEBHOOK_URL"] if ENV["SQUARE_WEBHOOK_URL"].present?

        # Reconstruct from provider config
        build_webhook_url("/captain_hook/square", provider_token: provider_config.token)
      end
    end
  end
end
