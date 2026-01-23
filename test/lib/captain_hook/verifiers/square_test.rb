# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Verifiers
    class SquareTest < ActiveSupport::TestCase
      setup do
        @verifier = Square.new
        @secret = "square_webhook_secret_test"
        @payload = '{"merchant_id":"MERCHANT123","type":"payment.created","event_id":"evt_square_123","data":{"id":"payment_123"}}'
        @provider_config = build_provider_config(
          signing_secret: @secret,
          token: "test_token"
        )
        @notification_url = "https://example.com/captain_hook/square/test_token"
        ENV["SQUARE_WEBHOOK_URL"] = @notification_url
      end

      teardown do
        ENV.delete("SQUARE_WEBHOOK_URL")
      end

      # === VALID Signature Tests ===

      test "accepts valid HMAC-SHA256 signature" do
        signature = generate_square_signature(@payload, @notification_url, @secret)
        headers = { "X-Square-Hmacsha256-Signature" => signature }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should accept valid signature"
      end

      test "accepts signature from older X-Square-Signature header" do
        signature = generate_square_signature(@payload, @notification_url, @secret)
        headers = { "X-Square-Signature" => signature }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "prefers X-Square-Hmacsha256-Signature over X-Square-Signature" do
        valid_signature = generate_square_signature(@payload, @notification_url, @secret)
        invalid_signature = "invalid_signature"
        headers = {
          "X-Square-Hmacsha256-Signature" => valid_signature,
          "X-Square-Signature" => invalid_signature
        }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should use HMACSHA256 header when both present"
      end

      # === INVALID Signature Tests ===

      test "rejects invalid signature" do
        headers = { "X-Square-Hmacsha256-Signature" => "invalid_signature" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        ), "Should reject invalid signature"
      end

      test "rejects signature with wrong secret" do
        signature = generate_square_signature(@payload, @notification_url, "wrong_secret")
        headers = { "X-Square-Hmacsha256-Signature" => signature }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects signature with modified payload" do
        signature = generate_square_signature(@payload, @notification_url, @secret)
        modified_payload = '{"merchant_id":"DIFFERENT","type":"modified"}'
        headers = { "X-Square-Hmacsha256-Signature" => signature }

        refute @verifier.verify_signature(
          payload: modified_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "rejects signature with wrong notification URL" do
        wrong_url = "https://wrong.com/captain_hook/square/test_token"
        signature = generate_square_signature(@payload, wrong_url, @secret)
        headers = { "X-Square-Hmacsha256-Signature" => signature }

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
        headers = { "X-Square-Hmacsha256-Signature" => "" }

        refute @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "accepts request when secret not configured" do
        config_no_secret = build_provider_config(signing_secret: nil, token: "test_token")
        headers = { "X-Square-Hmacsha256-Signature" => "any_signature" }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: config_no_secret
        ), "Should skip verification when no secret configured"
      end

      # === Edge Cases ===

      test "handles empty payload" do
        empty_payload = ""
        signature = generate_square_signature(empty_payload, @notification_url, @secret)
        headers = { "X-Square-Hmacsha256-Signature" => signature }

        assert @verifier.verify_signature(
          payload: empty_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "handles unicode in payload" do
        unicode_payload = '{"merchant_id":"MERCHANT123","message":"Hello 世界 🌍"}'
        signature = generate_square_signature(unicode_payload, @notification_url, @secret)
        headers = { "X-Square-Hmacsha256-Signature" => signature }

        assert @verifier.verify_signature(
          payload: unicode_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "handles large payload" do
        large_data = "x" * 50_000
        large_payload = %{{"merchant_id":"MERCHANT123","data":"#{large_data}"}}
        signature = generate_square_signature(large_payload, @notification_url, @secret)
        headers = { "X-Square-Hmacsha256-Signature" => signature }

        assert @verifier.verify_signature(
          payload: large_payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      # === Extract Methods Tests ===

      test "extracts event ID from payload" do
        parsed_payload = JSON.parse(@payload)
        event_id = @verifier.extract_event_id(parsed_payload)
        assert_equal "evt_square_123", event_id
      end

      test "extracts event type from payload" do
        parsed_payload = JSON.parse(@payload)
        event_type = @verifier.extract_event_type(parsed_payload)
        assert_equal "payment.created", event_type
      end

      private

      def generate_square_signature(payload, notification_url, secret)
        signed_payload = "#{notification_url}#{payload}"
        Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, signed_payload))
      end

      def build_provider_config(signing_secret:, token:)
        config = OpenStruct.new(
          signing_secret: signing_secret,
          token: token
        )
        
        config.define_singleton_method(:timestamp_validation_enabled?) { false }
        
        config
      end
    end
  end
end
