# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Adapters
    class StripeTest < Minitest::Test
      def setup
        @adapter = Stripe.new
      end

      def test_adapter_can_be_instantiated
        assert_instance_of Stripe, @adapter
      end

      def test_adapter_inherits_from_base
        assert @adapter.is_a?(Base), "Stripe adapter should inherit from Base"
      end

      def test_adapter_includes_adapter_helpers
        assert @adapter.class.included_modules.include?(CaptainHook::AdapterHelpers),
               "Stripe adapter should include AdapterHelpers"
      end

      def test_extract_event_id_from_stripe_payload
        payload = { "id" => "evt_stripe_123" }
        result = @adapter.extract_event_id(payload)
        assert_equal "evt_stripe_123", result
      end

      def test_extract_event_type_from_stripe_payload
        payload = { "type" => "payment_intent.succeeded" }
        result = @adapter.extract_event_type(payload)
        assert_equal "payment_intent.succeeded", result
      end

      def test_verify_signature_returns_false_without_signature_header
        result = @adapter.verify_signature(
          payload: "test payload",
          headers: {},
          provider_config: OpenStruct.new(
            signing_secret: "secret",
            timestamp_validation_enabled?: false
          )
        )
        refute result, "Should return false without signature header"
      end
    end
  end
end
