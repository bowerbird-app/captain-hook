# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Adapters
    class BaseAdapterTest < Minitest::Test
      def setup
        @config = Struct.new(:name, :signing_secret).new(
          "test_provider",
          "test_secret"
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

      def test_extract_event_type_from_event_type_field
        payload = { "event_type" => "order.created" }
        assert_equal "order.created", @adapter.extract_event_type(payload)
      end

      def test_extract_event_type_from_event_field
        payload = { "event" => "subscription.updated" }
        assert_equal "subscription.updated", @adapter.extract_event_type(payload)
      end

      def test_extract_event_type_returns_unknown_when_no_type_fields
        payload = { "data" => "value" }
        assert_equal "unknown", @adapter.extract_event_type(payload)
      end

      def test_extract_event_id_from_event_id_field
        payload = { "event_id" => "evt_12345" }
        assert_equal "evt_12345", @adapter.extract_event_id(payload)
      end

      def test_extract_event_id_from_webhook_id_field
        payload = { "webhook_id" => "wh_67890" }
        assert_equal "wh_67890", @adapter.extract_event_id(payload)
      end

      def test_extract_timestamp_returns_nil_by_default
        headers = { "X-Timestamp" => "1234567890" }
        assert_nil @adapter.extract_timestamp(headers)
      end

      # === Protected Methods Tests ===

      def test_generate_hmac_creates_sha256_signature
        secret = "test_secret"
        data = "test_data"

        signature = @adapter.send(:generate_hmac, secret, data)

        assert_kind_of String, signature
        assert_equal 64, signature.length # SHA256 produces 64 hex characters
        assert_match(/^[a-f0-9]{64}$/, signature)
      end

      def test_generate_hmac_consistent_output
        secret = "test_secret"
        data = "test_data"

        sig1 = @adapter.send(:generate_hmac, secret, data)
        sig2 = @adapter.send(:generate_hmac, secret, data)

        assert_equal sig1, sig2
      end

      def test_secure_compare_returns_true_for_identical_strings
        a = "test_string"
        b = "test_string"

        assert @adapter.send(:secure_compare, a, b)
      end

      def test_secure_compare_returns_false_for_different_strings
        a = "test_string1"
        b = "test_string2"

        refute @adapter.send(:secure_compare, a, b)
      end

      def test_secure_compare_returns_false_for_different_lengths
        a = "short"
        b = "much_longer_string"

        refute @adapter.send(:secure_compare, a, b)
      end

      def test_secure_compare_returns_false_for_blank_strings
        refute @adapter.send(:secure_compare, "", "test")
        refute @adapter.send(:secure_compare, "test", "")
        refute @adapter.send(:secure_compare, nil, "test")
        refute @adapter.send(:secure_compare, "test", nil)
      end
    end
  end
end
