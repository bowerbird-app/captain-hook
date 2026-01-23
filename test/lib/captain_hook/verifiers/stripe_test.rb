# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Verifiers
    class StripeTest < ActiveSupport::TestCase
      setup do
        @verifier = Stripe.new
        @secret = "whsec_test123"
        @payload = '{"id":"evt_test123","type":"charge.succeeded","data":{"object":{"id":"ch_123"}}}'
        @timestamp = Time.current.to_i
        @provider_config = build_provider_config(
          signing_secret: @secret,
          timestamp_tolerance_seconds: 300
        )
      end

      # === VALID Signature Tests ===

      test "accepts valid signature with v1" do
        signature = generate_stripe_signature(@payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}" }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should accept valid signature"
      end

      test "accepts valid signature with both v1 and v0" do
        signature = generate_stripe_signature(@payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature},v0=old_signature" }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "accepts valid v0 signature when v1 is invalid" do
        invalid_v1 = "invalid_signature"
        valid_v0 = generate_stripe_signature(@payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{invalid_v1},v0=#{valid_v0}" }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "accepts signature with case-insensitive header name" do
        signature = generate_stripe_signature(@payload, @timestamp, @secret)
        headers = { "stripe-signature" => "t=#{@timestamp},v1=#{signature}" }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === INVALID Signature Tests ===

      test "rejects invalid signature" do
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=invalid_signature" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should reject invalid signature"
      end

      test "rejects signature with wrong secret" do
        signature = generate_stripe_signature(@payload, @timestamp, "wrong_secret")
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects signature with modified payload" do
        signature = generate_stripe_signature(@payload, @timestamp, @secret)
        modified_payload = '{"id":"evt_different","type":"modified"}'
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}" }

        refute @verifier.verify_signature(
          payload: modified_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects tampered signature" do
        signature = generate_stripe_signature(@payload, @timestamp, @secret)
        tampered_signature = signature[0..-2] + "x" # Change last character
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{tampered_signature}" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === MISSING Signature Tests ===

      test "rejects missing signature header" do
        refute @verifier.verify_signature(
          payload: @payload,
          headers: {},
          provider_config: @provider_config
        ), "Should reject when signature header is missing"
      end

      test "rejects empty signature header" do
        headers = { "Stripe-Signature" => "" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects signature header with only whitespace" do
        headers = { "Stripe-Signature" => "   " }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === MALFORMED Signature Header Tests ===

      test "rejects malformed signature header without timestamp" do
        signature = generate_stripe_signature(@payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "v1=#{signature}" } # Missing timestamp

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects malformed signature header without v1" do
        headers = { "Stripe-Signature" => "t=#{@timestamp}" } # Missing signature

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects invalid format signature header" do
        headers = { "Stripe-Signature" => "not_valid_format" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects signature header with wrong delimiter" do
        signature = generate_stripe_signature(@payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp};v1=#{signature}" } # ; instead of ,

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === STALE Timestamp Tests (Replay Attack Prevention) ===

      test "rejects stale timestamp outside tolerance" do
        stale_timestamp = (Time.current - 6.minutes).to_i # Outside 5 minute tolerance
        signature = generate_stripe_signature(@payload, stale_timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{stale_timestamp},v1=#{signature}" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should reject stale timestamp"
      end

      test "accepts timestamp at exact tolerance boundary" do
        boundary_timestamp = (Time.current - 5.minutes).to_i
        signature = generate_stripe_signature(@payload, boundary_timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{boundary_timestamp},v1=#{signature}" }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects timestamp 1 second past tolerance" do
        past_tolerance = (Time.current - 301.seconds).to_i
        signature = generate_stripe_signature(@payload, past_tolerance, @secret)
        headers = { "Stripe-Signature" => "t=#{past_tolerance},v1=#{signature}" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === FUTURE Timestamp Tests ===

      test "rejects future timestamp outside tolerance" do
        future_timestamp = (Time.current + 6.minutes).to_i
        signature = generate_stripe_signature(@payload, future_timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{future_timestamp},v1=#{signature}" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should reject future timestamp"
      end

      test "accepts future timestamp within tolerance" do
        future_timestamp = (Time.current + 2.minutes).to_i
        signature = generate_stripe_signature(@payload, future_timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{future_timestamp},v1=#{signature}" }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === Timestamp Validation Disabled ===

      test "accepts stale timestamp when validation disabled" do
        stale_timestamp = (Time.current - 1.hour).to_i
        signature = generate_stripe_signature(@payload, stale_timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{stale_timestamp},v1=#{signature}" }
        
        config_no_validation = build_provider_config(
          signing_secret: @secret,
          timestamp_validation_enabled: false
        )

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config_no_validation
        )
      end

      # === Edge Cases ===

      test "handles empty payload" do
        empty_payload = ""
        signature = generate_stripe_signature(empty_payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}" }

        assert @verifier.verify_signature(
          payload: empty_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "handles unicode in payload" do
        unicode_payload = '{"id":"evt_test","message":"Hello 世界 🌍 émojis"}'
        signature = generate_stripe_signature(unicode_payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}" }

        assert @verifier.verify_signature(
          payload: unicode_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "handles large payload" do
        large_data = "x" * 100_000
        large_payload = %{{"id":"evt_test","data":"#{large_data}"}}
        signature = generate_stripe_signature(large_payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}" }

        assert @verifier.verify_signature(
          payload: large_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "handles special characters in payload" do
        special_payload = '{"id":"evt_test","data":"special!@#$%^&*()_+-=[]{}|;:\',.<>?/~`"}'
        signature = generate_stripe_signature(special_payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}" }

        assert @verifier.verify_signature(
          payload: special_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === Extract Methods Tests ===

      test "extracts timestamp from valid header" do
        signature = generate_stripe_signature(@payload, @timestamp, @secret)
        headers = { "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}" }

        extracted = @verifier.extract_timestamp(headers)
        assert_equal @timestamp, extracted
      end

      test "returns nil for missing signature header" do
        assert_nil @verifier.extract_timestamp({})
      end

      test "extracts event ID from payload" do
        parsed_payload = JSON.parse(@payload)
        event_id = @verifier.extract_event_id(parsed_payload)
        assert_equal "evt_test123", event_id
      end

      test "extracts event type from payload" do
        parsed_payload = JSON.parse(@payload)
        event_type = @verifier.extract_event_type(parsed_payload)
        assert_equal "charge.succeeded", event_type
      end

      private

      def generate_stripe_signature(payload, timestamp, secret)
        signed_payload = "#{timestamp}.#{payload}"
        OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
      end

      def build_provider_config(signing_secret:, timestamp_tolerance_seconds: 300, timestamp_validation_enabled: true)
        config = OpenStruct.new(
          signing_secret: signing_secret,
          timestamp_tolerance_seconds: timestamp_tolerance_seconds
        )
        
        config.define_singleton_method(:timestamp_validation_enabled?) do
          timestamp_validation_enabled
        end
        
        config
      end
    end
  end
end
