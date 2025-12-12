# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Adapters
    class WebhookSiteTest < Minitest::Test
      def setup
        @provider_config = ProviderConfig.new(
          name: "webhook_site",
          token: "test-token",
          adapter_class: "CaptainHook::Adapters::WebhookSite"
        )
        @adapter = @provider_config.adapter
      end

      def test_verify_signature_always_returns_true
        payload = '{"test": "data"}'
        headers = {}

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      def test_verify_signature_with_any_headers
        payload = '{"test": "data"}'
        headers = { "X-Some-Header" => "value" }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      def test_extract_event_id_from_request_id
        payload = { "request_id" => "req-123", "other" => "data" }

        assert_equal "req-123", @adapter.extract_event_id(payload)
      end

      def test_extract_event_id_from_external_id
        payload = { "external_id" => "ext-456", "other" => "data" }

        assert_equal "ext-456", @adapter.extract_event_id(payload)
      end

      def test_extract_event_id_fallback_to_base
        payload = { "id" => "id-789", "other" => "data" }

        assert_equal "id-789", @adapter.extract_event_id(payload)
      end

      def test_extract_event_type_from_event_type_field
        payload = { "event_type" => "test.incoming", "data" => {} }

        assert_equal "test.incoming", @adapter.extract_event_type(payload)
      end

      def test_extract_event_type_from_type_field
        payload = { "type" => "user.created", "data" => {} }

        assert_equal "user.created", @adapter.extract_event_type(payload)
      end

      def test_extract_event_type_default
        payload = { "data" => {} }

        assert_equal "test.incoming", @adapter.extract_event_type(payload)
      end

      def test_extract_timestamp_from_header
        headers = { "X-Webhook-Timestamp" => "1234567890" }

        assert_equal 1_234_567_890, @adapter.extract_timestamp(headers)
      end

      def test_extract_timestamp_from_lowercase_header
        headers = { "x-webhook-timestamp" => "9876543210" }

        assert_equal 9_876_543_210, @adapter.extract_timestamp(headers)
      end

      def test_extract_timestamp_returns_nil_when_not_present
        headers = {}

        assert_nil @adapter.extract_timestamp(headers)
      end
    end
  end
end
