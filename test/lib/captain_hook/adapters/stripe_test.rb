# frozen_string_literal: true

require "test_helper"
require "ostruct"

module CaptainHook
  module Verifiers
    class StripeTest < Minitest::Test
      def setup
        @verifier = Stripe.new
        @secret = "whsec_test_secret"
        @timestamp = Time.current.to_i
        @payload = '{"id":"evt_test","type":"payment_intent.succeeded"}'

        # Stub debug_mode to avoid NoMethodError
        CaptainHook.configuration.define_singleton_method(:debug_mode) { false }
      end

      # Basic instantiation tests
      def test_verifier_can_be_instantiated
        assert_instance_of Stripe, @verifier
      end

      def test_verifier_inherits_from_base
        assert @verifier.is_a?(Base), "Stripe verifier should inherit from Base"
      end

      def test_verifier_includes_verifier_helpers
        assert @verifier.class.included_modules.include?(CaptainHook::VerifierHelpers),
               "Stripe verifier should include VerifierHelpers"
      end

      # Extract event ID tests
      def test_extract_event_id_from_stripe_payload
        payload = { "id" => "evt_stripe_123" }
        result = @verifier.extract_event_id(payload)
        assert_equal "evt_stripe_123", result
      end

      def test_extract_event_id_returns_nil_when_missing
        payload = { "type" => "payment_intent.succeeded" }
        result = @verifier.extract_event_id(payload)
        assert_nil result
      end

      # Extract event type tests
      def test_extract_event_type_from_stripe_payload
        payload = { "type" => "payment_intent.succeeded" }
        result = @verifier.extract_event_type(payload)
        assert_equal "payment_intent.succeeded", result
      end

      def test_extract_event_type_returns_nil_when_missing
        payload = { "id" => "evt_123" }
        result = @verifier.extract_event_type(payload)
        assert_nil result
      end

      # Extract timestamp tests
      def test_extract_timestamp_returns_unix_timestamp
        signature_header = "t=#{@timestamp},v1=signature"
        headers = { "Stripe-Signature" => signature_header }
        result = @verifier.extract_timestamp(headers)
        assert_equal @timestamp, result
      end

      def test_extract_timestamp_returns_nil_when_header_missing
        result = @verifier.extract_timestamp({})
        assert_nil result
      end

      def test_extract_timestamp_returns_nil_when_timestamp_missing_from_header
        headers = { "Stripe-Signature" => "v1=signature" }
        result = @verifier.extract_timestamp(headers)
        assert_nil result
      end

      # Signature verification - missing signature header
      def test_verify_signature_returns_false_without_signature_header
        config = build_config(signing_secret: @secret)
        result = @verifier.verify_signature(
          payload: @payload,
          headers: {},
          provider_config: config
        )
        refute result, "Should return false without signature header"
      end

      def test_verify_signature_returns_false_with_blank_signature_header
        config = build_config(signing_secret: @secret)
        result = @verifier.verify_signature(
          payload: @payload,
          headers: { "Stripe-Signature" => "" },
          provider_config: config
        )
        refute result
      end

      # Signature verification - malformed signature header
      def test_verify_signature_returns_false_when_timestamp_missing
        config = build_config(signing_secret: @secret)
        headers = { "Stripe-Signature" => "v1=abc123" }
        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_returns_false_when_signature_missing
        config = build_config(signing_secret: @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp}" }
        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_returns_false_when_both_timestamp_and_signature_missing
        config = build_config(signing_secret: @secret)
        headers = { "Stripe-Signature" => "v0=old" }
        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      # Signature verification - valid signatures
      def test_verify_signature_accepts_valid_v1_signature
        config = build_config(signing_secret: @secret)
        signed_payload = "#{@timestamp}.#{@payload}"
        expected_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{expected_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_accepts_valid_v0_signature
        config = build_config(signing_secret: @secret)
        signed_payload = "#{@timestamp}.#{@payload}"
        expected_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v0=#{expected_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_accepts_either_v1_or_v0_signature
        config = build_config(signing_secret: @secret)
        signed_payload = "#{@timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{valid_sig},v0=invalid" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_rejects_invalid_signature
        config = build_config(signing_secret: @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=invalid_signature" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_rejects_signature_with_wrong_secret
        config = build_config(signing_secret: @secret)
        signed_payload = "#{@timestamp}.#{@payload}"
        wrong_sig = OpenSSL::HMAC.hexdigest("SHA256", "wrong_secret", signed_payload)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{wrong_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_rejects_tampered_payload
        config = build_config(signing_secret: @secret)
        signed_payload = "#{@timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{valid_sig}" }
        tampered_payload = '{"id":"evt_tampered","type":"payment_intent.succeeded"}'

        result = @verifier.verify_signature(
          payload: tampered_payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      # Timestamp validation tests
      def test_verify_signature_validates_timestamp_when_enabled
        config = build_config(
          signing_secret: @secret,
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        signed_payload = "#{@timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_rejects_old_timestamp
        config = build_config(
          signing_secret: @secret,
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        old_timestamp = (Time.current - 400.seconds).to_i
        signed_payload = "#{old_timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{old_timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_rejects_future_timestamp
        config = build_config(
          signing_secret: @secret,
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        future_timestamp = (Time.current + 400.seconds).to_i
        signed_payload = "#{future_timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{future_timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        refute result
      end

      def test_verify_signature_accepts_timestamp_at_tolerance_boundary
        config = build_config(
          signing_secret: @secret,
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 300
        )
        boundary_timestamp = (Time.current - 300.seconds).to_i
        signed_payload = "#{boundary_timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{boundary_timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_uses_default_tolerance_when_not_specified
        config = build_config(
          signing_secret: @secret,
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: nil
        )
        recent_timestamp = (Time.current - 250.seconds).to_i
        signed_payload = "#{recent_timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{recent_timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_skips_timestamp_validation_when_disabled
        config = build_config(
          signing_secret: @secret,
          timestamp_validation_enabled: false
        )
        old_timestamp = (Time.current - 10_000.seconds).to_i
        signed_payload = "#{old_timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{old_timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      # Header case sensitivity tests
      def test_verify_signature_handles_lowercase_header_name
        config = build_config(signing_secret: @secret)
        signed_payload = "#{@timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "stripe-signature" => "t=#{@timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_handles_uppercase_header_name
        config = build_config(signing_secret: @secret)
        signed_payload = "#{@timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "STRIPE-SIGNATURE" => "t=#{@timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      # Edge cases
      def test_verify_signature_handles_empty_payload
        config = build_config(signing_secret: @secret)
        empty_payload = ""
        signed_payload = "#{@timestamp}.#{empty_payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: empty_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_handles_complex_json_payload
        config = build_config(signing_secret: @secret)
        complex_payload = '{"id":"evt_123","type":"payment_intent.succeeded","data":{"object":{"amount":1000}}}'
        signed_payload = "#{@timestamp}.#{complex_payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: complex_payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_handles_multiple_v1_signatures
        config = build_config(signing_secret: @secret)
        signed_payload = "#{@timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        # Stripe sometimes sends multiple signatures
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{valid_sig},v1=another_sig" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      def test_verify_signature_with_custom_tolerance
        config = build_config(
          signing_secret: @secret,
          timestamp_validation_enabled: true,
          timestamp_tolerance_seconds: 600
        )
        old_timestamp = (Time.current - 500.seconds).to_i
        signed_payload = "#{old_timestamp}.#{@payload}"
        valid_sig = OpenSSL::HMAC.hexdigest("SHA256", @secret, signed_payload)
        headers = { "Stripe-Signature" => "t=#{old_timestamp},v1=#{valid_sig}" }

        result = @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config
        )
        assert result
      end

      private

      def build_config(
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
    end
  end
end
