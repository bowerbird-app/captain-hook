# frozen_string_literal: true

require "test_helper"
require "ostruct"

module CaptainHook
  module Adapters
    class WebhookSiteTest < ActiveSupport::TestCase
      setup do
        @provider_config = Struct.new(:signing_secret).new("not_used")
        @adapter = WebhookSite.new(@provider_config)
      end

      test "verify_signature always returns true" do
        payload = '{"test":"data"}'
        headers = {}

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "verify_signature accepts any payload" do
        assert @adapter.verify_signature(payload: "anything", headers: {})
        assert @adapter.verify_signature(payload: "", headers: {})
        assert @adapter.verify_signature(payload: '{"complex":"json"}', headers: {})
      end

      test "verify_signature accepts any headers" do
        assert @adapter.verify_signature(payload: "test", headers: { "Any" => "Headers" })
        assert @adapter.verify_signature(payload: "test", headers: {})
      end

      test "extract_timestamp returns timestamp from X-Webhook-Timestamp header" do
        timestamp = Time.current.to_i
        headers = { "X-Webhook-Timestamp" => timestamp.to_s }

        assert_equal timestamp, @adapter.extract_timestamp(headers)
      end

      test "extract_timestamp handles lowercase header name" do
        timestamp = Time.current.to_i
        headers = { "x-webhook-timestamp" => timestamp.to_s }

        assert_equal timestamp, @adapter.extract_timestamp(headers)
      end

      test "extract_timestamp returns nil when header missing" do
        headers = {}
        assert_nil @adapter.extract_timestamp(headers)
      end

      test "extract_timestamp returns nil when header empty" do
        headers = { "X-Webhook-Timestamp" => "" }
        assert_nil @adapter.extract_timestamp(headers)
      end

      test "extract_event_id returns request_id from payload" do
        payload = { "request_id" => "req_123", "id" => "different" }
        assert_equal "req_123", @adapter.extract_event_id(payload)
      end

      test "extract_event_id returns external_id from payload" do
        payload = { "external_id" => "ext_456", "id" => "different" }
        assert_equal "ext_456", @adapter.extract_event_id(payload)
      end

      test "extract_event_id returns id from payload" do
        payload = { "id" => "id_789" }
        assert_equal "id_789", @adapter.extract_event_id(payload)
      end

      test "extract_event_id generates UUID when no id fields present" do
        payload = { "data" => "something" }
        event_id = @adapter.extract_event_id(payload)

        assert_not_nil event_id
        # UUID format: 8-4-4-4-12 hex digits
        assert_match(/\A[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\z/, event_id)
      end

      test "extract_event_id prioritizes request_id over external_id" do
        payload = { "request_id" => "req", "external_id" => "ext", "id" => "id" }
        assert_equal "req", @adapter.extract_event_id(payload)
      end

      test "extract_event_id prioritizes external_id over id" do
        payload = { "external_id" => "ext", "id" => "id" }
        assert_equal "ext", @adapter.extract_event_id(payload)
      end

      test "extract_event_type returns event_type from payload" do
        payload = { "event_type" => "custom.event", "type" => "different" }
        assert_equal "custom.event", @adapter.extract_event_type(payload)
      end

      test "extract_event_type returns type from payload" do
        payload = { "type" => "test.event" }
        assert_equal "test.event", @adapter.extract_event_type(payload)
      end

      test "extract_event_type defaults to test.incoming" do
        payload = { "data" => "something" }
        assert_equal "test.incoming", @adapter.extract_event_type(payload)
      end

      test "extract_event_type prioritizes event_type over type" do
        payload = { "event_type" => "priority", "type" => "fallback" }
        assert_equal "priority", @adapter.extract_event_type(payload)
      end

      test "adapter inherits from Base" do
        assert WebhookSite < Base
      end
    end
  end
end
