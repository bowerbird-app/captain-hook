# frozen_string_literal: true

require "test_helper"
require "ostruct"

module CaptainHook
  module Adapters
    class StripeTest < ActiveSupport::TestCase
      setup do
        @signing_secret = "whsec_test_secret"
        @provider_config = Struct.new(:signing_secret,
                                      :timestamp_validation_enabled?,
                                      :timestamp_tolerance_seconds).new(
                                        @signing_secret,
                                        true,
                                        300
                                      )
        @adapter = Stripe.new(@provider_config)
      end

      test "verify_signature accepts valid Stripe signature" do
        payload = '{"id":"evt_test","type":"payment_intent.succeeded"}'
        timestamp = Time.current.to_i

        signed_payload = "#{timestamp}.#{payload}"
        signature = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, signed_payload)

        headers = {
          "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects invalid signature" do
        payload = '{"id":"evt_test","type":"payment_intent.succeeded"}'
        timestamp = Time.current.to_i

        headers = {
          "Stripe-Signature" => "t=#{timestamp},v1=invalid_signature"
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects when signature header is missing" do
        payload = '{"id":"evt_test"}'
        headers = {}

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects when signature header is blank" do
        payload = '{"id":"evt_test"}'
        headers = { "Stripe-Signature" => "" }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature accepts signatures with multiple versions (v1 and v0)" do
        payload = '{"id":"evt_test"}'
        timestamp = Time.current.to_i

        signed_payload = "#{timestamp}.#{payload}"
        signature_v1 = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, signed_payload)
        signature_v0 = "old_signature"

        headers = {
          "Stripe-Signature" => "t=#{timestamp},v1=#{signature_v1},v0=#{signature_v0}"
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects expired timestamp" do
        payload = '{"id":"evt_test"}'
        old_timestamp = (Time.current - 10.minutes).to_i

        signed_payload = "#{old_timestamp}.#{payload}"
        signature = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, signed_payload)

        headers = {
          "Stripe-Signature" => "t=#{old_timestamp},v1=#{signature}"
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature accepts timestamp within tolerance" do
        payload = '{"id":"evt_test"}'
        timestamp = (Time.current - 4.minutes).to_i # Within 5 minute tolerance

        signed_payload = "#{timestamp}.#{payload}"
        signature = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, signed_payload)

        headers = {
          "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature uses custom timestamp tolerance from provider config" do
        @provider_config.timestamp_tolerance_seconds = 60 # 1 minute
        payload = '{"id":"evt_test"}'
        timestamp = (Time.current - 90.seconds).to_i # Beyond 1 minute tolerance

        signed_payload = "#{timestamp}.#{payload}"
        signature = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, signed_payload)

        headers = {
          "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature skips timestamp validation when disabled" do
        # Create new provider config with timestamp validation disabled
        config = Struct.new(:signing_secret, :timestamp_validation_enabled?, :timestamp_tolerance_seconds).new(
          @signing_secret,
          false,
          300
        )
        adapter = Stripe.new(config)

        payload = '{"id":"evt_test"}'
        old_timestamp = (Time.current - 1.hour).to_i

        signed_payload = "#{old_timestamp}.#{payload}"
        signature = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, signed_payload)

        headers = {
          "Stripe-Signature" => "t=#{old_timestamp},v1=#{signature}"
        }

        assert adapter.verify_signature(payload: payload, headers: headers)
      end

      test "extract_timestamp returns timestamp from header" do
        timestamp = Time.current.to_i
        headers = {
          "Stripe-Signature" => "t=#{timestamp},v1=somesignature"
        }

        extracted = @adapter.extract_timestamp(headers)
        assert_equal timestamp, extracted
      end

      test "extract_timestamp returns nil for missing header" do
        headers = {}
        assert_nil @adapter.extract_timestamp(headers)
      end

      test "extract_timestamp returns nil for blank header" do
        headers = { "Stripe-Signature" => "" }
        assert_nil @adapter.extract_timestamp(headers)
      end

      test "extract_event_id returns id from payload" do
        payload = { "id" => "evt_1234", "type" => "payment_intent.succeeded" }
        assert_equal "evt_1234", @adapter.extract_event_id(payload)
      end

      test "extract_event_type returns type from payload" do
        payload = { "id" => "evt_1234", "type" => "charge.succeeded" }
        assert_equal "charge.succeeded", @adapter.extract_event_type(payload)
      end

      test "verify_signature handles malformed signature header gracefully" do
        payload = '{"id":"evt_test"}'
        headers = { "Stripe-Signature" => "malformed_header_without_proper_format" }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature matches any valid signature when multiple provided" do
        payload = '{"id":"evt_test"}'
        timestamp = Time.current.to_i

        signed_payload = "#{timestamp}.#{payload}"
        correct_signature = OpenSSL::HMAC.hexdigest("SHA256", @signing_secret, signed_payload)
        wrong_signature = "wrong_sig"

        # Correct signature in v0, wrong in v1
        headers = {
          "Stripe-Signature" => "t=#{timestamp},v1=#{wrong_signature},v0=#{correct_signature}"
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "parse_signature_header correctly parses Stripe format" do
        header = "t=1234567890,v1=signature1,v0=signature0"
        timestamp, signatures = @adapter.send(:parse_signature_header, header)

        assert_equal "1234567890", timestamp
        assert_includes signatures, "signature1"
        assert_includes signatures, "signature0"
      end

      test "timestamp_within_tolerance? validates timestamp correctly" do
        current = Time.current.to_i

        # Within tolerance
        assert @adapter.send(:timestamp_within_tolerance?, current - 100, 300)
        assert @adapter.send(:timestamp_within_tolerance?, current + 100, 300)

        # Outside tolerance
        refute @adapter.send(:timestamp_within_tolerance?, current - 400, 300)
        refute @adapter.send(:timestamp_within_tolerance?, current + 400, 300)
      end

      test "constants are defined correctly" do
        assert_equal "Stripe-Signature", Stripe::SIGNATURE_HEADER
        assert_equal 300, Stripe::TIMESTAMP_TOLERANCE
      end
    end
  end
end
