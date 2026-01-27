# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class VerifierDiscoveryTest < Minitest::Test
      def setup
        @discovery = VerifierDiscovery.new
      end

      def test_discovers_base_verifier
        verifiers = @discovery.call

        assert_includes verifiers, "CaptainHook::Verifiers::Base"
      end

      def test_discovers_stripe_verifier
        verifiers = @discovery.call

        assert_includes verifiers, "CaptainHook::Verifiers::Stripe"
      end

      def test_returns_sorted_unique_verifiers
        verifiers = @discovery.call

        assert_equal verifiers, verifiers.uniq.sort
      end

      def test_all_discovered_verifiers_are_strings
        verifiers = @discovery.call

        assert verifiers.all? { |a| a.is_a?(String) }, "All verifiers should be strings"
      end

      def test_discovers_minimum_number_of_verifiers
        verifiers = @discovery.call

        # Should at least have Base plus the built-in verifiers
        assert_operator verifiers.size, :>=, 4, "Should discover at least 4 verifiers"
      end

      def test_verifier_names_follow_correct_namespace
        verifiers = @discovery.call

        verifiers.each do |verifier|
          assert verifier.start_with?("CaptainHook::Verifiers::"),
                 "Verifier #{verifier} should be in CaptainHook::Verifiers namespace"
        end
      end

      def test_verifier_exists_returns_true_for_valid_class
        result = @discovery.send(:verifier_exists?, "CaptainHook::Verifiers::Base")
        assert result, "Should return true for valid verifier class"
      end

      def test_verifier_exists_returns_false_for_invalid_class
        result = @discovery.send(:verifier_exists?, "CaptainHook::Verifiers::NonExistent")
        refute result, "Should return false for non-existent verifier class"
      end

      def test_discover_gem_verifiers_adds_valid_verifiers
        discovery = VerifierDiscovery.new
        discovery.send(:discover_gem_verifiers)

        # Access the instance variable to check it was populated
        verifiers = discovery.instance_variable_get(:@discovered_verifiers)
        assert verifiers.size.positive?, "Should discover at least one gem verifier"
      end

      def test_call_returns_unique_verifiers
        # Call twice to ensure uniqueness logic works
        discovery = VerifierDiscovery.new
        discovery.send(:discover_gem_verifiers)
        discovery.send(:discover_gem_verifiers) # duplicate discovery

        result = discovery.call
        assert_equal result, result.uniq
      end
    end
  end
end
