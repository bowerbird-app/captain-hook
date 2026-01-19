# frozen_string_literal: true

module CaptainHook
  module Adapters
    # PayPal webhook adapter
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
      def verify_signature(payload:, headers:, provider_config:)
        log_verification("paypal", "Status" => "Verifying signature")

        # Get signature components from headers
        signature = extract_header(headers, SIGNATURE_HEADER)
        transmission_id = extract_header(headers, TRANSMISSION_ID_HEADER)
        transmission_time = extract_header(headers, TRANSMISSION_TIME_HEADER)
        webhook_id = extract_header(headers, WEBHOOK_ID_HEADER)

        log_verification("paypal",
          "Signature" => signature.present? ? "present" : "missing",
          "Transmission ID" => transmission_id.present? ? "present" : "missing",
          "Transmission Time" => transmission_time.present? ? "present" : "missing",
          "Webhook ID" => webhook_id || "not provided")

        # Skip verification if signing secret not configured
        if skip_verification?(provider_config.signing_secret)
          log_verification("paypal", "Status" => "Skipping verification (no secret configured)")
          return true
        end

        # Basic validation: require signature headers
        if signature.blank? || transmission_id.blank? || transmission_time.blank?
          log_verification("paypal", "Error" => "Missing required signature headers")
          return false
        end

        # Check timestamp tolerance
        if provider_config.timestamp_validation_enabled?
          timestamp = parse_timestamp(transmission_time)
          if timestamp.nil?
            log_verification("paypal", "Error" => "Invalid timestamp format")
            return false
          end

          tolerance = provider_config.timestamp_tolerance_seconds || 300
          unless timestamp_within_tolerance?(timestamp, tolerance)
            log_verification("paypal", "Error" => "Timestamp outside tolerance window")
            return false
          end
        end

        # For now, just validate that required headers are present
        # Full PayPal verification requires downloading and validating their cert chain
        # which is complex and requires the paypal-sdk
        log_verification("paypal", "Result" => "✓ Passed (simplified)")
        true
      end

      # Extract timestamp from PayPal headers
      def extract_timestamp(headers)
        transmission_time = extract_header(headers, TRANSMISSION_TIME_HEADER)
        parse_timestamp(transmission_time)
      end

      # Extract event ID from PayPal payload
      def extract_event_id(payload)
        payload["id"]
      end

      # Extract event type from PayPal payload
      def extract_event_type(payload)
        payload["event_type"]
      end
    end
  end
end
