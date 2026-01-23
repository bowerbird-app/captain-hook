# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Verifiers
    class WebhookSiteTest < ActiveSupport::TestCase
      setup do
        @verifier = WebhookSite.new
        @payload = '{"request_id":"req_123","data":"test"}'
        @provider_config = build_provider_config
      end

      # === No Signature Verification Tests ===

      test "always accepts webhooks without signature" do
        assert @verifier.verify_signature(
          payload: @payload,
          headers: {},
          provider_config: @provider_config
        ), "WebhookSite verifier should always accept requests"
      end

      test "accepts webhooks with any signature" do
        headers = { "X-Any-Signature" => "any_value" }

        assert @verifier.verify_signature(
          payload: @payload,
          headers: headers,
          provider_config: @provider_config
        )
      end

      test "accepts webhooks with empty payload" do
        assert @verifier.verify_signature(
          payload: "",
          headers: {},
          provider_config: @provider_config
        )
      end

      test "accepts webhooks with invalid JSON" do
        assert @verifier.verify_signature(
          payload: "{ invalid json",
          headers: {},
          provider_config: @provider_config
        ), "Should accept any payload for testing purposes"
      end

      # === Extract Timestamp Tests ===

      test "extracts timestamp from X-Webhook-Timestamp header" do
        timestamp = Time.current.to_i
        headers = { "X-Webhook-Timestamp" => timestamp.to_s }

        extracted = @verifier.extract_timestamp(headers)
        assert_equal timestamp, extracted
      end

      test "extracts timestamp from lowercase header" do
        timestamp = Time.current.to_i
        headers = { "x-webhook-timestamp" => timestamp.to_s }

        extracted = @verifier.extract_timestamp(headers)
        assert_equal timestamp, extracted
      end

      test "returns nil when timestamp header missing" do
        assert_nil @verifier.extract_timestamp({})
      end

      test "returns nil for empty timestamp header" do
        headers = { "X-Webhook-Timestamp" => "" }
        assert_nil @verifier.extract_timestamp(headers)
      end

      # === Extract Event ID Tests ===

      test "extracts event ID from request_id field" do
        parsed_payload = { "request_id" => "req_123" }
        event_id = @verifier.extract_event_id(parsed_payload)
        assert_equal "req_123", event_id
      end

      test "extracts event ID from external_id field" do
        parsed_payload = { "external_id" => "ext_456" }
        event_id = @verifier.extract_event_id(parsed_payload)
        assert_equal "ext_456", event_id
      end

      test "extracts event ID from id field" do
        parsed_payload = { "id" => "id_789" }
        event_id = @verifier.extract_event_id(parsed_payload)
        assert_equal "id_789", event_id
      end

      test "generates UUID when no ID field present" do
        parsed_payload = { "data" => "test" }
        event_id = @verifier.extract_event_id(parsed_payload)
        
        assert event_id.present?
        assert_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, event_id)
      end

      test "prefers request_id over external_id" do
        parsed_payload = { 
          "request_id" => "req_priority",
          "external_id" => "ext_other",
          "id" => "id_other"
        }
        event_id = @verifier.extract_event_id(parsed_payload)
        assert_equal "req_priority", event_id
      end

      # === Extract Event Type Tests ===

      test "extracts event type from event_type field" do
        parsed_payload = { "event_type" => "webhook.received" }
        event_type = @verifier.extract_event_type(parsed_payload)
        assert_equal "webhook.received", event_type
      end

      test "extracts event type from type field" do
        parsed_payload = { "type" => "test.event" }
        event_type = @verifier.extract_event_type(parsed_payload)
        assert_equal "test.event", event_type
      end

      test "returns default event type when no type field present" do
        parsed_payload = { "data" => "test" }
        event_type = @verifier.extract_event_type(parsed_payload)
        assert_equal "test.incoming", event_type
      end

      test "prefers event_type over type field" do
        parsed_payload = { 
          "event_type" => "priority.event",
          "type" => "other.event"
        }
        event_type = @verifier.extract_event_type(parsed_payload)
        assert_equal "priority.event", event_type
      end

      # === Edge Cases ===

      test "handles nil payload gracefully" do
        # Should not crash, even with nil (though this shouldn't happen in practice)
        assert @verifier.verify_signature(
          payload: nil,
          headers: {},
          provider_config: @provider_config
        )
      end

      test "handles nil headers gracefully" do
        assert @verifier.verify_signature(
          payload: @payload,
          headers: nil,
          provider_config: @provider_config
        )
      end

      test "handles nil provider_config gracefully" do
        assert @verifier.verify_signature(
          payload: @payload,
          headers: {},
          provider_config: nil
        )
      end

      private

      def build_provider_config
        OpenStruct.new(signing_secret: nil)
      end
    end
  end
end
