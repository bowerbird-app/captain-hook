# frozen_string_literal: true

module CaptainHook
  module Adapters
    # PayPal webhook signature verification adapter
    # Implements PayPal's webhook signature verification scheme
    # https://developer.paypal.com/api/rest/webhooks/
    class Paypal < Base
      SIGNATURE_HEADER = "Paypal-Transmission-Sig"
      CERT_URL_HEADER = "Paypal-Cert-Url"
      TRANSMISSION_ID_HEADER = "Paypal-Transmission-Id"
      TRANSMISSION_TIME_HEADER = "Paypal-Transmission-Time"
      AUTH_ALGO_HEADER = "Paypal-Auth-Algo"
      WEBHOOK_ID_HEADER = "Paypal-Webhook-Id"

      # Verify PayPal webhook signature
      # PayPal uses a complex verification with certificate chain
      # For now, this is a simplified implementation for testing
      # TODO: Implement full certificate-based verification for production
      def verify_signature(payload:, headers:)
        # Log what we receive for debugging
        Rails.logger.info "🔵 PayPal Adapter: Verifying signature"
        Rails.logger.info "🔵 Headers: #{headers.keys.join(', ')}"

        # Get signature components from headers
        signature = extract_header(headers, SIGNATURE_HEADER)
        transmission_id = extract_header(headers, TRANSMISSION_ID_HEADER)
        transmission_time = extract_header(headers, TRANSMISSION_TIME_HEADER)
        webhook_id = extract_header(headers, WEBHOOK_ID_HEADER)

        Rails.logger.info "🔵 Signature: #{signature.present? ? 'present' : 'missing'}"
        Rails.logger.info "🔵 Transmission ID: #{transmission_id.present? ? 'present' : 'missing'}"
        Rails.logger.info "🔵 Transmission Time: #{transmission_time.present? ? 'present' : 'missing'}"
        Rails.logger.info "🔵 Webhook ID: #{webhook_id || 'not provided'}"

        # For testing: If signing_secret is blank or "skip", skip verification
        if provider_config.signing_secret.blank? || provider_config.signing_secret == "skip"
          Rails.logger.info "🔵 PayPal: Skipping signature verification (no secret configured)"
          return true
        end

        # Basic validation: require signature headers
        if signature.blank? || transmission_id.blank? || transmission_time.blank?
          Rails.logger.warn "🔵 PayPal: Missing required signature headers"
          return false
        end

        # Check timestamp tolerance
        if provider_config.timestamp_validation_enabled?
          timestamp = begin
            Time.parse(transmission_time).to_i
          rescue StandardError
            nil
          end
          if timestamp.nil?
            Rails.logger.warn "🔵 PayPal: Invalid timestamp format"
            return false
          end

          tolerance = provider_config.timestamp_tolerance_seconds || 300
          unless timestamp_within_tolerance?(timestamp, tolerance)
            Rails.logger.warn "🔵 PayPal: Timestamp outside tolerance window"
            return false
          end
        end

        # For now, just validate that required headers are present
        # Full PayPal verification requires downloading and validating their cert chain
        # which is complex and requires the paypal-sdk
        Rails.logger.info "🔵 PayPal: Signature verification passed (simplified)"
        true
      end

      # Extract timestamp from PayPal headers
      def extract_timestamp(headers)
        transmission_time = extract_header(headers, TRANSMISSION_TIME_HEADER)
        return nil if transmission_time.blank?

        begin
          Time.parse(transmission_time).to_i
        rescue StandardError
          nil
        end
      end

      # Extract event ID from PayPal payload
      def extract_event_id(payload)
        payload["id"]
      end

      # Extract event type from PayPal payload
      def extract_event_type(payload)
        payload["event_type"]
      end

      private

      # Extract header value (case-insensitive)
      def extract_header(headers, key)
        headers[key] || headers[key.downcase] || headers[key.upcase]
      end

      # Check if timestamp is within tolerance
      def timestamp_within_tolerance?(timestamp, tolerance)
        current_time = Time.current.to_i
        (current_time - timestamp).abs <= tolerance
      end
    end
  end
end
