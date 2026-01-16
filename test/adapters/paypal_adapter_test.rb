# frozen_string_literal: true

require "test_helper"
require "ostruct"

module CaptainHook
  module Adapters
    class PaypalTest < ActiveSupport::TestCase
      setup do
        @provider_config = Struct.new(:signing_secret,
                                      :timestamp_validation_enabled?,
                                      :timestamp_tolerance_seconds).new(
                                        "test_secret",
                                        true,
                                        300
                                      )
        @adapter = Paypal.new(@provider_config)
      end

      test "verify_signature accepts request with all required headers" do
        payload = '{"id":"WH-123","event_type":"PAYMENT.CAPTURE.COMPLETED"}'
        headers = {
          "Paypal-Transmission-Sig" => "valid_signature",
          "Paypal-Transmission-Id" => "transmission_123",
          "Paypal-Transmission-Time" => Time.current.iso8601,
          "Paypal-Webhook-Id" => "webhook_123"
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature accepts when signing_secret is blank (skip mode)" do
        @provider_config.signing_secret = ""
        payload = '{"id":"WH-123"}'
        headers = {}

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature accepts when signing_secret is 'skip'" do
        @provider_config.signing_secret = "skip"
        payload = '{"id":"WH-123"}'
        headers = {}

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects when signature header is missing" do
        payload = '{"id":"WH-123"}'
        headers = {
          "Paypal-Transmission-Id" => "transmission_123",
          "Paypal-Transmission-Time" => Time.current.iso8601
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects when transmission_id header is missing" do
        payload = '{"id":"WH-123"}'
        headers = {
          "Paypal-Transmission-Sig" => "signature",
          "Paypal-Transmission-Time" => Time.current.iso8601
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects when transmission_time header is missing" do
        payload = '{"id":"WH-123"}'
        headers = {
          "Paypal-Transmission-Sig" => "signature",
          "Paypal-Transmission-Id" => "transmission_123"
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects expired timestamp" do
        payload = '{"id":"WH-123"}'
        old_time = (Time.current - 10.minutes).iso8601

        headers = {
          "Paypal-Transmission-Sig" => "signature",
          "Paypal-Transmission-Id" => "transmission_123",
          "Paypal-Transmission-Time" => old_time
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature accepts timestamp within tolerance" do
        payload = '{"id":"WH-123"}'
        recent_time = (Time.current - 4.minutes).iso8601

        headers = {
          "Paypal-Transmission-Sig" => "signature",
          "Paypal-Transmission-Id" => "transmission_123",
          "Paypal-Transmission-Time" => recent_time
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature uses custom timestamp tolerance" do
        @provider_config.timestamp_tolerance_seconds = 60 # 1 minute
        payload = '{"id":"WH-123"}'
        time = (Time.current - 90.seconds).iso8601

        headers = {
          "Paypal-Transmission-Sig" => "signature",
          "Paypal-Transmission-Id" => "transmission_123",
          "Paypal-Transmission-Time" => time
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature skips timestamp validation when disabled" do
        # Create new provider config with timestamp validation disabled
        config = Struct.new(:signing_secret, :timestamp_validation_enabled?, :timestamp_tolerance_seconds).new(
          "test_secret",
          false,
          300
        )
        adapter = Paypal.new(config)

        payload = '{"id":"WH-123"}'
        old_time = (Time.current - 1.hour).iso8601

        headers = {
          "Paypal-Transmission-Sig" => "signature",
          "Paypal-Transmission-Id" => "transmission_123",
          "Paypal-Transmission-Time" => old_time
        }

        assert adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects invalid timestamp format" do
        payload = '{"id":"WH-123"}'
        headers = {
          "Paypal-Transmission-Sig" => "signature",
          "Paypal-Transmission-Id" => "transmission_123",
          "Paypal-Transmission-Time" => "not-a-valid-timestamp"
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "extract_timestamp returns timestamp from header" do
        timestamp = Time.current
        headers = {
          "Paypal-Transmission-Time" => timestamp.iso8601
        }

        extracted = @adapter.extract_timestamp(headers)
        assert_equal timestamp.to_i, extracted
      end

      test "extract_timestamp returns nil for missing header" do
        headers = {}
        assert_nil @adapter.extract_timestamp(headers)
      end

      test "extract_timestamp returns nil for invalid timestamp" do
        headers = {
          "Paypal-Transmission-Time" => "invalid"
        }
        assert_nil @adapter.extract_timestamp(headers)
      end

      test "extract_event_id returns id from payload" do
        payload = { "id" => "WH-12345", "event_type" => "PAYMENT.CAPTURE.COMPLETED" }
        assert_equal "WH-12345", @adapter.extract_event_id(payload)
      end

      test "extract_event_type returns event_type from payload" do
        payload = { "id" => "WH-12345", "event_type" => "PAYMENT.AUTHORIZATION.VOIDED" }
        assert_equal "PAYMENT.AUTHORIZATION.VOIDED", @adapter.extract_event_type(payload)
      end

      test "extract_header is case-insensitive" do
        headers = {
          "paypal-transmission-sig" => "lowercase",
          "PAYPAL-TRANSMISSION-ID" => "uppercase"
        }

        assert_equal "lowercase", @adapter.send(:extract_header, headers, "Paypal-Transmission-Sig")
        assert_equal "uppercase", @adapter.send(:extract_header, headers, "Paypal-Transmission-Id")
      end

      test "extract_header prefers exact case match" do
        headers = {
          "Paypal-Transmission-Sig" => "exact",
          "paypal-transmission-sig" => "lowercase"
        }

        assert_equal "exact", @adapter.send(:extract_header, headers, "Paypal-Transmission-Sig")
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
        assert_equal "Paypal-Transmission-Sig", Paypal::SIGNATURE_HEADER
        assert_equal "Paypal-Cert-Url", Paypal::CERT_URL_HEADER
        assert_equal "Paypal-Transmission-Id", Paypal::TRANSMISSION_ID_HEADER
        assert_equal "Paypal-Transmission-Time", Paypal::TRANSMISSION_TIME_HEADER
        assert_equal "Paypal-Auth-Algo", Paypal::AUTH_ALGO_HEADER
        assert_equal "Paypal-Webhook-Id", Paypal::WEBHOOK_ID_HEADER
      end

      test "verify_signature handles all headers with webhook_id optional" do
        payload = '{"id":"WH-123"}'
        headers = {
          "Paypal-Transmission-Sig" => "signature",
          "Paypal-Transmission-Id" => "transmission_123",
          "Paypal-Transmission-Time" => Time.current.iso8601
          # webhook_id is optional
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end
    end
  end
end
