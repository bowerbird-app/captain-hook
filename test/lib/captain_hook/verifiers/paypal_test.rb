# frozen_string_literal: true

require "test_helper"
require "ostruct"

module CaptainHook
  module Verifiers
    class PaypalTest < Minitest::Test
      def setup
        @verifier = Paypal.new
        @valid_transmission_time = Time.current.iso8601
        @valid_payload = { "id" => "WH-123", "event_type" => "PAYMENT.CAPTURE.COMPLETED" }.to_json

        # Stub debug_mode to avoid NoMethodError in log_verification
        CaptainHook.configuration.define_singleton_method(:debug_mode) { false }
      end

      # Basic instantiation tests
      def test_verifier_can_be_instantiated
        assert_instance_of Paypal, @verifier
      end

      def test_verifier_inherits_from_base
        assert @verifier.is_a?(Base), "PayPal verifier should inherit from Base"
      end

      def test_verifier_includes_verifier_helpers
        assert @verifier.class.included_modules.include?(CaptainHook::VerifierHelpers),
               "PayPal verifier should include VerifierHelpers"
      end

      # Extract event ID tests
      def test_extract_event_id_returns_event_id_from_payload
        payload = { "id" => "WH-PAYPAL-123" }
        result = @verifier.extract_event_id(payload)
        assert_equal "WH-PAYPAL-123", result
      end

      def test_extract_event_id_returns_nil_when_id_is_missing
        payload = { "event_type" => "PAYMENT.CAPTURE.COMPLETED" }
        result = @verifier.extract_event_id(payload)
        assert_nil result
      end

      # Extract event type tests
      def test_extract_event_type_returns_event_type_from_payload
        payload = { "event_type" => "PAYMENT.CAPTURE.COMPLETED" }
        result = @verifier.extract_event_type(payload)
        assert_equal "PAYMENT.CAPTURE.COMPLETED", result
      end

      def test_extract_event_type_returns_nil_when_event_type_is_missing
        payload = { "id" => "WH-123" }
        result = @verifier.extract_event_type(payload)
        assert_nil result
      end

      # Extract timestamp tests
      def test_extract_timestamp_returns_unix_timestamp_from_headers
        headers = { "Paypal-Transmission-Time" => @valid_transmission_time }
        result = @verifier.extract_timestamp(headers)
        assert_kind_of Integer, result
      end

      def test_extract_timestamp_handles_case_insensitive_header_names
        headers = { "paypal-transmission-time" => @valid_transmission_time }
        result = @verifier.extract_timestamp(headers)
        assert_kind_of Integer, result
      end

      def test_extract_timestamp_returns_nil_when_header_is_missing
        result = @verifier.extract_timestamp({})
        assert_nil result
      end

      def test_extract_timestamp_returns_nil_for_invalid_timestamp_format
        headers = { "Paypal-Transmission-Time" => "invalid-timestamp" }
        result = @verifier.extract_timestamp(headers)
        assert_nil result
      end

      def test_extract_timestamp_handles_unix_timestamp_string
        timestamp = Time.current.to_i.to_s
        headers = { "Paypal-Transmission-Time" => timestamp }
        result = @verifier.extract_timestamp(headers)
        assert_equal timestamp.to_i, result
      end

      # Signature verification - skip verification scenarios
      def test_verify_signature_returns_true_when_signing_secret_is_blank
        config = build_provider_config(signing_secret: "")
        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: build_valid_headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_returns_true_when_signing_secret_is_env_placeholder
        config = build_provider_config(signing_secret: "ENV[PAYPAL_WEBHOOK_ID]")
        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: build_valid_headers,
          provider_config: config
        )
        assert result
      end

      # Signature verification - missing headers
      def test_verify_signature_returns_false_when_signature_header_is_missing
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = build_valid_headers
        headers.delete("Paypal-Transmission-Sig")

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_returns_false_when_transmission_id_header_is_missing
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = build_valid_headers
        headers.delete("Paypal-Transmission-Id")

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_returns_false_when_transmission_time_header_is_missing
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = build_valid_headers
        headers.delete("Paypal-Transmission-Time")

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_returns_false_when_all_signature_headers_are_missing
        config = build_provider_config(signing_secret: "webhook_id_123")
        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: {},
          provider_config: config
        )
        refute result
      end

      # Signature verification - blank headers
      def test_verify_signature_returns_false_when_signature_header_is_blank
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = build_valid_headers
        headers["Paypal-Transmission-Sig"] = ""

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_returns_false_when_transmission_id_is_blank
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = build_valid_headers
        headers["Paypal-Transmission-Id"] = ""

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_returns_false_when_transmission_time_is_blank
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = build_valid_headers
        headers["Paypal-Transmission-Time"] = ""

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      # Timestamp validation tests
      def test_verify_signature_validates_timestamp_when_enabled
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        headers = build_valid_headers

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_returns_false_when_timestamp_is_too_old
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        old_time = (Time.current - 400.seconds).iso8601
        headers = build_valid_headers(transmission_time: old_time)

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_returns_false_when_timestamp_is_too_far_in_future
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        future_time = (Time.current + 400.seconds).iso8601
        headers = build_valid_headers(transmission_time: future_time)

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_accepts_timestamp_at_exact_tolerance_boundary
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        boundary_time = (Time.current - 300.seconds).iso8601
        headers = build_valid_headers(transmission_time: boundary_time)

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_returns_false_when_timestamp_format_is_invalid
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        headers = build_valid_headers(transmission_time: "not-a-valid-timestamp")

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_uses_default_tolerance_when_not_specified
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: nil
        )
        # Set time to 250 seconds ago (within default 300 second tolerance)
        recent_time = (Time.current - 250.seconds).iso8601
        headers = build_valid_headers(transmission_time: recent_time)

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_skips_timestamp_validation_when_disabled
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: false
        )
        # Use very old timestamp
        old_time = (Time.current - 10_000.seconds).iso8601
        headers = build_valid_headers(transmission_time: old_time)

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      # Header extraction with case variations
      def test_verify_signature_handles_uppercase_header_names
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = {
          "PAYPAL-TRANSMISSION-SIG" => "sig123",
          "PAYPAL-TRANSMISSION-ID" => "id123",
          "PAYPAL-TRANSMISSION-TIME" => @valid_transmission_time,
          "PAYPAL-WEBHOOK-ID" => "webhook123"
        }

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_handles_lowercase_header_names
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = {
          "paypal-transmission-sig" => "sig123",
          "paypal-transmission-id" => "id123",
          "paypal-transmission-time" => @valid_transmission_time,
          "paypal-webhook-id" => "webhook123"
        }

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_handles_mixed_case_header_names
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = {
          "PayPal-Transmission-Sig" => "sig123",
          "paypal-transmission-id" => "id123",
          "Paypal-Transmission-Time" => @valid_transmission_time,
          "PAYPAL-WEBHOOK-ID" => "webhook123"
        }

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        # NOTE: extract_header doesn't handle arbitrary mixed-case well
        # It only checks exact match, downcase, and upcase
        # This is a known limitation - headers should be consistently cased
        refute result
      end

      # Optional webhook ID header test
      def test_verify_signature_works_without_webhook_id_header
        config = build_provider_config(signing_secret: "webhook_id_123")
        headers = build_valid_headers
        headers.delete("Paypal-Webhook-Id")

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        # Webhook ID is optional, should still pass
        assert result
      end

      # Edge cases
      def test_verify_signature_handles_empty_payload
        config = build_provider_config(signing_secret: "webhook_id_123")
        result = @verifier.verify_signature(
          payload: "",
          headers: build_valid_headers,
          provider_config: config
        )
        # Should pass basic validation even with empty payload
        assert result
      end

      def test_verify_signature_handles_nil_timestamp_in_headers_hash
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: true
        )
        headers = build_valid_headers
        headers["Paypal-Transmission-Time"] = nil

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_handles_malformed_json_payload
        config = build_provider_config(signing_secret: "webhook_id_123")
        result = @verifier.verify_signature(
          payload: "{invalid json",
          headers: build_valid_headers,
          provider_config: config
        )
        # Verifier doesn't parse JSON, so malformed JSON should pass basic checks
        assert result
      end

      # Integration with configuration
      def test_verify_signature_respects_provider_specific_timestamp_tolerance
        config = build_provider_config(
          signing_secret: "webhook_id_123",
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 600 # 10 minutes
        )
        # 500 seconds old - within 600s tolerance
        old_time = (Time.current - 500.seconds).iso8601
        headers = build_valid_headers(transmission_time: old_time)

        result = @verifier.verify_signature(
          payload: @valid_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      private

      def build_provider_config(
        signing_secret:,
        timestamp_validation_enabled: false,
        timestamp_tolerance_seconds: 300
      )
        OpenStruct.new(
          signing_secret: signing_secret,
          timestamp_validation_enabled?: timestamp_validation_enabled,
          timestamp_tolerance_seconds: timestamp_tolerance_seconds
        )
      end

      def build_valid_headers(transmission_time: @valid_transmission_time)
        {
          "Paypal-Transmission-Sig" => "test_signature_123",
          "Paypal-Transmission-Id" => "test_transmission_id_123",
          "Paypal-Transmission-Time" => transmission_time,
          "Paypal-Webhook-Id" => "test_webhook_id_123",
          "Paypal-Auth-Algo" => "SHA256withRSA",
          "Paypal-Cert-Url" => "https://api.paypal.com/v1/notifications/certs/test"
        }
      end
    end
  end
end
