# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Verifiers
    class StripeTest < Minitest::Test
      def setup
        @verifier = Stripe.new
      end

      def test_verifier_can_be_instantiated
        assert_instance_of Stripe, @verifier
      end

      def test_verifier_inherits_from_base
        assert @verifier.is_a?(Base), "Stripe verifier should inherit from Base"
      end

      def test_verifier_includes_verifier_helpers
        assert @verifier.class.included_modules.include?(CaptainHook::VerifierHelpers),
               "Stripe verifier should include VerifierHelpers"
      end

      def test_extract_event_id_from_stripe_payload
        payload = { "id" => "evt_stripe_123" }
        result = @verifier.extract_event_id(payload)
        assert_equal "evt_stripe_123", result
      end

      def test_extract_event_type_from_stripe_payload
        payload = { "type" => "payment_intent.succeeded" }
        result = @verifier.extract_event_type(payload)
        assert_equal "payment_intent.succeeded", result
      end

      def test_verify_signature_returns_false_without_signature_header
        result = @verifier.verify_signature(
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
