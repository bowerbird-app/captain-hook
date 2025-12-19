# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Adapters
    class BaseAdapterTest < Minitest::Test
      def setup
        @config = OpenStruct.new(
          name: "test_provider",
          signing_secret: "test_secret"
        )
        @adapter = Base.new(@config)
      end

      # === Initialization Tests ===

      def test_initializes_with_provider_config
        assert_equal @config, @adapter.provider_config
      end

      # === Abstract Method Tests ===

      def test_verify_signature_raises_not_implemented_error
        assert_raises(NotImplementedError) do
          @adapter.verify_signature(payload: "{}", headers: {})
        end
      end

      # === extract_event_id Tests ===

      def test_extract_event_id_from_id_field
        payload = { "id" => "evt_123" }
        assert_equal "evt_123", @adapter.extract_event_id(payload)
      end

      def test_extract_event_id_returns_nil_when_no_id_fields
        payload = { "data" => "value" }
        assert_nil @adapter.extract_event_id(payload)
      end

      # === extract_event_type Tests ===

      def test_extract_event_type_from_type_field
        payload = { "type" => "payment.succeeded" }
        assert_equal "payment.succeeded", @adapter.extract_event_type(payload)
      end

      def test_extract_event_type_returns_unknown_when_no_type_fields
        payload = { "data" => "value" }
        assert_equal "unknown", @adapter.extract_event_type(payload)
      end
    end
  end
end
