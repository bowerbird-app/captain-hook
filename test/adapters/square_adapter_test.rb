# frozen_string_literal: true

require "test_helper"
require "ostruct"

module CaptainHook
  module Adapters
    class SquareTest < ActiveSupport::TestCase
      setup do
        @signing_secret = "test_secret"
        @provider_config = Struct.new(:signing_secret, :token).new(
          @signing_secret,
          "test_token"
        )
        @adapter = Square.new(@provider_config)
        ENV["SQUARE_WEBHOOK_URL"] = "https://example.com/captain_hook/square/test_token"
      end

      teardown do
        ENV.delete("SQUARE_WEBHOOK_URL")
      end

      test "verify_signature accepts valid Square signature" do
        payload = '{"event_id":"evt_123","type":"payment.created"}'
        notification_url = ENV.fetch("SQUARE_WEBHOOK_URL", nil)
        signed_payload = "#{notification_url}#{payload}"

        signature = Base64.strict_encode64(
          OpenSSL::HMAC.digest("sha256", @signing_secret, signed_payload)
        )

        headers = {
          "X-Square-Hmacsha256-Signature" => signature
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature uses legacy signature header if HMACSHA256 not present" do
        payload = '{"event_id":"evt_123"}'
        notification_url = ENV.fetch("SQUARE_WEBHOOK_URL", nil)
        signed_payload = "#{notification_url}#{payload}"

        signature = Base64.strict_encode64(
          OpenSSL::HMAC.digest("sha256", @signing_secret, signed_payload)
        )

        headers = {
          "X-Square-Signature" => signature
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects invalid signature" do
        payload = '{"event_id":"evt_123"}'
        headers = {
          "X-Square-Hmacsha256-Signature" => "invalid_signature"
        }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature rejects when signature header is missing" do
        payload = '{"event_id":"evt_123"}'
        headers = {}

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature accepts when signing_secret is blank (skip mode)" do
        @provider_config.signing_secret = ""
        payload = '{"event_id":"evt_123"}'
        headers = {}

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature accepts when signing_secret is 'skip'" do
        @provider_config.signing_secret = "skip"
        payload = '{"event_id":"evt_123"}'
        headers = {}

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "extract_event_id returns event_id from payload" do
        payload = { "event_id" => "sq_evt_12345", "type" => "payment.created" }
        assert_equal "sq_evt_12345", @adapter.extract_event_id(payload)
      end

      test "extract_event_type returns type from payload" do
        payload = { "event_id" => "sq_evt_12345", "type" => "order.updated" }
        assert_equal "order.updated", @adapter.extract_event_type(payload)
      end

      test "generate_square_signature produces Base64-encoded HMAC" do
        data = "test_data"
        signature = @adapter.send(:generate_square_signature, @signing_secret, data)

        # Should be Base64 format
        assert_match(%r{^[A-Za-z0-9+/]+=*$}, signature)

        # Should be decodable
        assert_nothing_raised { Base64.strict_decode64(signature) }
      end

      test "generate_square_signature is consistent" do
        data = "test_data"
        sig1 = @adapter.send(:generate_square_signature, @signing_secret, data)
        sig2 = @adapter.send(:generate_square_signature, @signing_secret, data)

        assert_equal sig1, sig2
      end

      test "build_notification_url uses SQUARE_WEBHOOK_URL from environment" do
        ENV["SQUARE_WEBHOOK_URL"] = "https://custom.com/webhooks/square"

        url = @adapter.send(:build_notification_url)
        assert_equal "https://custom.com/webhooks/square", url
      end

      test "build_notification_url constructs URL when env var not set" do
        ENV.delete("SQUARE_WEBHOOK_URL")
        ENV["APP_URL"] = "https://myapp.com"

        url = @adapter.send(:build_notification_url)
        assert_equal "https://myapp.com/captain_hook/square/test_token", url
      end

      test "detect_base_url returns APP_URL when present" do
        ENV["APP_URL"] = "https://production.com"

        url = @adapter.send(:detect_base_url)
        assert_equal "https://production.com", url
      end

      test "detect_base_url handles Codespaces environment" do
        ENV.delete("APP_URL")
        ENV["CODESPACES"] = "true"
        ENV["CODESPACE_NAME"] = "my-codespace"
        ENV["PORT"] = "3004"

        url = @adapter.send(:detect_base_url)
        assert_equal "https://my-codespace-3004.app.github.dev", url
      ensure
        ENV.delete("CODESPACES")
        ENV.delete("CODESPACE_NAME")
        ENV.delete("PORT")
      end

      test "detect_base_url defaults to localhost" do
        ENV.delete("APP_URL")
        ENV.delete("CODESPACES")

        url = @adapter.send(:detect_base_url)
        assert_equal "http://localhost:3000", url
      end

      test "detect_base_url uses custom port when set" do
        ENV.delete("APP_URL")
        ENV.delete("CODESPACES")
        ENV["PORT"] = "4000"

        url = @adapter.send(:detect_base_url)
        assert_equal "http://localhost:4000", url
      ensure
        ENV.delete("PORT")
      end

      test "extract_header finds header case-insensitively" do
        # ActionDispatch::Http::Headers provides case-insensitive access
        # In real Rails, headers would be accessible via get method
        headers = {
          "X-Square-Signature" => "test_value"
        }

        value = @adapter.send(:extract_header, headers, "X-Square-Signature")
        assert_equal "test_value", value
      end

      test "extract_header handles HTTP_ prefix variants" do
        headers = {
          "HTTP_X_SQUARE_SIGNATURE" => "test_value"
        }

        value = @adapter.send(:extract_header, headers, "X-Square-Signature")
        assert_equal "test_value", value
      end

      test "extract_header returns nil when header not found" do
        headers = {}

        value = @adapter.send(:extract_header, headers, "X-Square-Signature")
        assert_nil value
      end

      test "extract_header tries multiple case variants" do
        headers = {
          "x-square-signature" => "lowercase_value"
        }

        value = @adapter.send(:extract_header, headers, "X-Square-Signature")
        assert_equal "lowercase_value", value
      end

      test "constants are defined correctly" do
        assert_equal "X-Square-Signature", Square::SIGNATURE_HEADER
        assert_equal "X-Square-Hmacsha256-Signature", Square::SIGNATURE_HMACSHA256_HEADER
      end

      test "verify_signature uses notification_url in signature calculation" do
        payload = '{"event_id":"evt_123"}'
        custom_url = "https://custom.example.com/hook"
        ENV["SQUARE_WEBHOOK_URL"] = custom_url

        signed_payload = "#{custom_url}#{payload}"
        signature = Base64.strict_encode64(
          OpenSSL::HMAC.digest("sha256", @signing_secret, signed_payload)
        )

        headers = {
          "X-Square-Hmacsha256-Signature" => signature
        }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature fails if notification_url doesn't match" do
        payload = '{"event_id":"evt_123"}'
        wrong_url = "https://wrong.example.com/hook"

        # Generate signature with wrong URL
        signed_payload = "#{wrong_url}#{payload}"
        signature = Base64.strict_encode64(
          OpenSSL::HMAC.digest("sha256", @signing_secret, signed_payload)
        )

        headers = {
          "X-Square-Hmacsha256-Signature" => signature
        }

        # Should fail because ENV["SQUARE_WEBHOOK_URL"] is different
        refute @adapter.verify_signature(payload: payload, headers: headers)
      end
    end
  end
end
