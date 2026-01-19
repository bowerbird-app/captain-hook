# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Verifiers
    class BaseTest < Minitest::Test
      def setup
        @verifier = Base.new
      end

      def test_verifier_can_be_instantiated
        assert_instance_of Base, @verifier
      end

      def test_verifier_includes_verifier_helpers
        assert @verifier.class.included_modules.include?(CaptainHook::VerifierHelpers),
               "Base verifier should include VerifierHelpers"
      end

      def test_verify_signature_returns_true_by_default
        result = @verifier.verify_signature(
          payload: "test payload",
          headers: {},
          provider_config: OpenStruct.new(signing_secret: "secret")
        )
        assert result, "Base verifier should accept all signatures"
      end

      def test_extract_timestamp_returns_nil_by_default
        result = @verifier.extract_timestamp({})
        assert_nil result, "Base verifier should return nil for timestamp"
      end

      def test_extract_event_id_returns_id_from_payload
        payload = { "id" => "evt_123" }
        result = @verifier.extract_event_id(payload)
        assert_equal "evt_123", result
      end

      def test_extract_event_id_returns_event_id_field
        payload = { "event_id" => "evt_456" }
        result = @verifier.extract_event_id(payload)
        assert_equal "evt_456", result
      end

      def test_extract_event_id_generates_uuid_if_missing
        payload = {}
        result = @verifier.extract_event_id(payload)
        assert result.is_a?(String), "Should generate a UUID"
        assert result.length.positive?, "UUID should not be empty"
      end

      def test_extract_event_type_returns_type_from_payload
        payload = { "type" => "test.event" }
        result = @verifier.extract_event_type(payload)
        assert_equal "test.event", result
      end

      def test_extract_event_type_returns_event_type_field
        payload = { "event_type" => "custom.event" }
        result = @verifier.extract_event_type(payload)
        assert_equal "custom.event", result
      end

      def test_extract_event_type_returns_default_if_missing
        payload = {}
        result = @verifier.extract_event_type(payload)
        assert_equal "webhook.received", result
      end
    end
  end
end
