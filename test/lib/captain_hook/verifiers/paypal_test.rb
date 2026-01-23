# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Verifiers
    class PaypalTest < ActiveSupport::TestCase
      setup do
        @verifier = Paypal.new
        @secret = "paypal_webhook_secret"
        @payload = '{"id":"WH-123","event_type":"PAYMENT.SALE.COMPLETED","resource":{"id":"PAY123"}}'
        @transmission_id = "transmission_#{SecureRandom.hex(8)}"
        @transmission_time = Time.current.utc.iso8601
        @webhook_id = "webhook_#{SecureRandom.hex(4)}"
        @provider_config = build_provider_config(
          signing_secret: @secret,
          timestamp_tolerance_seconds: 300
        )
      end

      # === VALID Signature Tests ===

      test "accepts valid signature with all required headers" do
        headers = build_paypal_headers(
          signature: "valid_signature_base64",
          transmission_id: @transmission_id,
          transmission_time: @transmission_time,
          webhook_id: @webhook_id
        )

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should accept valid PayPal signature"
      end

      test "accepts signature with current timestamp" do
        headers = build_paypal_headers(
          signature: "signature",
          transmission_id: @transmission_id,
          transmission_time: Time.current.utc.iso8601
        )

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === MISSING Required Headers Tests ===

      test "rejects missing signature header" do
        headers = build_paypal_headers(
          transmission_id: @transmission_id,
          transmission_time: @transmission_time
        )
        headers.delete("Paypal-Transmission-Sig")

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should reject when signature is missing"
      end

      test "rejects missing transmission ID" do
        headers = build_paypal_headers(
          signature: "signature",
          transmission_time: @transmission_time
        )
        headers.delete("Paypal-Transmission-Id")

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects missing transmission time" do
        headers = build_paypal_headers(
          signature: "signature",
          transmission_id: @transmission_id
        )
        headers.delete("Paypal-Transmission-Time")

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects empty signature header" do
        headers = build_paypal_headers(
          signature: "",
          transmission_id: @transmission_id,
          transmission_time: @transmission_time
        )

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === Timestamp Validation Tests ===

      test "rejects stale timestamp outside tolerance" do
        stale_time = (Time.current - 6.minutes).utc.iso8601
        headers = build_paypal_headers(
          signature: "signature",
          transmission_id: @transmission_id,
          transmission_time: stale_time
        )

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should reject stale timestamp"
      end

      test "accepts timestamp within tolerance" do
        recent_time = (Time.current - 2.minutes).utc.iso8601
        headers = build_paypal_headers(
          signature: "signature",
          transmission_id: @transmission_id,
          transmission_time: recent_time
        )

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects future timestamp outside tolerance" do
        future_time = (Time.current + 6.minutes).utc.iso8601
        headers = build_paypal_headers(
          signature: "signature",
          transmission_id: @transmission_id,
          transmission_time: future_time
        )

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should reject future timestamp"
      end

      test "accepts stale timestamp when validation disabled" do
        stale_time = (Time.current - 1.hour).utc.iso8601
        headers = build_paypal_headers(
          signature: "signature",
          transmission_id: @transmission_id,
          transmission_time: stale_time
        )
        
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

      test "rejects invalid timestamp format" do
        headers = build_paypal_headers(
          signature: "signature",
          transmission_id: @transmission_id,
          transmission_time: "not_a_valid_timestamp"
        )

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should reject invalid timestamp format"
      end

      # === Skip Verification Tests ===

      test "accepts request when secret not configured" do
        config_no_secret = build_provider_config(signing_secret: nil)
        headers = build_paypal_headers(
          signature: "any_signature",
          transmission_id: @transmission_id,
          transmission_time: @transmission_time
        )

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config_no_secret
        ), "Should skip verification when no secret configured"
      end

      # === Extract Methods Tests ===

      test "extracts timestamp from headers" do
        headers = build_paypal_headers(
          signature: "sig",
          transmission_id: @transmission_id,
          transmission_time: @transmission_time
        )

        extracted = @verifier.extract_timestamp(headers)
        assert_kind_of Integer, extracted
        assert extracted > 0
      end

      test "returns nil for missing transmission time header" do
        assert_nil @verifier.extract_timestamp({})
      end

      test "extracts event ID from payload" do
        parsed_payload = JSON.parse(@payload)
        event_id = @verifier.extract_event_id(parsed_payload)
        assert_equal "WH-123", event_id
      end

      test "extracts event type from payload" do
        parsed_payload = JSON.parse(@payload)
        event_type = @verifier.extract_event_type(parsed_payload)
        assert_equal "PAYMENT.SALE.COMPLETED", event_type
      end

      private

      def build_paypal_headers(signature: nil, transmission_id: nil, transmission_time: nil, webhook_id: nil)
        headers = {}
        headers["Paypal-Transmission-Sig"] = signature if signature
        headers["Paypal-Transmission-Id"] = transmission_id if transmission_id
        headers["Paypal-Transmission-Time"] = transmission_time if transmission_time
        headers["Paypal-Webhook-Id"] = webhook_id if webhook_id
        headers
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
