# frozen_string_literal: true

module CaptainHook
  module Adapters
    # Square webhook signature verification adapter
    # Implements Square's webhook signature verification
    # https://developer.squareup.com/docs/webhooks/step3validate
    class Square < Base
      SIGNATURE_HEADER = "X-Square-Signature"
      SIGNATURE_HMACSHA256_HEADER = "X-Square-Hmacsha256-Signature"

      # Verify Square webhook signature
      # Square signs webhooks with HMAC-SHA256 (Base64 encoded)
      def verify_signature(payload:, headers:)
        Rails.logger.info "🟦 Square Adapter: Verifying signature"
        Rails.logger.info "🟦 All square headers: #{headers.to_h.select do |k, _|
          k.to_s.downcase.include?('square')
        end.inspect}"

        # Square sends signature in X-Square-Hmacsha256-Signature (newer) or X-Square-Signature
        signature = extract_header(headers, SIGNATURE_HMACSHA256_HEADER) ||
                    extract_header(headers, SIGNATURE_HEADER)

        Rails.logger.info "🟦 Signature: #{signature.present? ? 'present' : 'missing'}"

        # For testing: If signing_secret is blank or "skip", skip verification
        if provider_config.signing_secret.blank? || provider_config.signing_secret == "skip"
          Rails.logger.info "🟦 Square: Skipping signature verification (no secret configured)"
          return true
        end

        if signature.blank?
          Rails.logger.warn "🟦 Square: No signature header found"
          return false
        end

        # Square uses HMAC-SHA256: notification_url + request_body
        notification_url = build_notification_url
        signed_payload = "#{notification_url}#{payload}"

        Rails.logger.info "🟦 Notification URL: #{notification_url}"
        Rails.logger.info "🟦 Payload length: #{payload.bytesize} bytes"
        Rails.logger.info "🟦 Using signing_secret: #{provider_config.signing_secret.present?}"

        # Square expects Base64-encoded HMAC-SHA256
        expected_signature = generate_square_signature(provider_config.signing_secret, signed_payload)

        Rails.logger.info "🟦 Expected: #{expected_signature[0..20]}..."
        Rails.logger.info "🟦 Received: #{signature[0..20]}..."

        if secure_compare(signature, expected_signature)
          Rails.logger.info "🟦 Square: Signature verification passed ✓"
          true
        else
          Rails.logger.warn "🟦 Square: Signature verification failed ✗"
          false
        end
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

      # Extract header value (Rack-proof, handles HTTP_ prefix)
      def extract_header(headers, key)
        # ActionDispatch::Http::Headers supports case-insensitive lookup
        return headers.get(key) if headers.respond_to?(:get)

        # Try multiple variants for plain Hash
        candidates = [
          key,
          key.downcase,
          "HTTP_#{key.upcase.tr('-', '_')}",
          "http_#{key.downcase.tr('-', '_')}"
        ]

        candidates.each do |k|
          v = headers[k]
          return v if v.present?
        end

        nil
      end

      # Generate Square signature (Base64-encoded HMAC-SHA256)
      # Square expects Base64, not hex!
      def generate_square_signature(secret, data)
        digest = OpenSSL::HMAC.digest("sha256", secret, data)
        Base64.strict_encode64(digest)
      end

      # Build the notification URL that Square uses for signature
      # This must match exactly what you configured in Square
      def build_notification_url
        # Try to get from environment or reconstruct
        if ENV["SQUARE_WEBHOOK_URL"].present?
          ENV["SQUARE_WEBHOOK_URL"]
        else
          # Reconstruct from provider config
          # You may need to adjust this based on your setup
          base_url = detect_base_url
          "#{base_url}/captain_hook/incoming/square/#{provider_config.token}"
        end
      end

      def detect_base_url
        return ENV["APP_URL"] if ENV["APP_URL"].present?

        if ENV["CODESPACES"] == "true" && ENV["CODESPACE_NAME"].present?
          port = ENV.fetch("PORT", "3004")
          "https://#{ENV.fetch('CODESPACE_NAME', nil)}-#{port}.app.github.dev"
        else
          port = ENV.fetch("PORT", "3000")
          "http://localhost:#{port}"
        end
      end
    end
  end
end
