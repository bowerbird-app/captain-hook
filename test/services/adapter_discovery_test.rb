# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class AdapterDiscoveryTest < Minitest::Test
      def setup
        @discovery = AdapterDiscovery.new
      end

      def test_discovers_base_adapter
        adapters = @discovery.call

        assert_includes adapters, "CaptainHook::Adapters::Base"
      end

      def test_discovers_stripe_adapter
        adapters = @discovery.call

        assert_includes adapters, "CaptainHook::Adapters::Stripe"
      end

      def test_discovers_square_adapter
        adapters = @discovery.call

        assert_includes adapters, "CaptainHook::Adapters::Square"
      end

      def test_discovers_paypal_adapter
        adapters = @discovery.call

        assert_includes adapters, "CaptainHook::Adapters::Paypal"
      end

      def test_discovers_webhook_site_adapter
        adapters = @discovery.call

        assert_includes adapters, "CaptainHook::Adapters::WebhookSite"
      end

      def test_returns_sorted_unique_adapters
        adapters = @discovery.call

        assert_equal adapters, adapters.uniq.sort
      end

      def test_all_discovered_adapters_are_strings
        adapters = @discovery.call

        assert adapters.all? { |a| a.is_a?(String) }, "All adapters should be strings"
      end

      def test_discovers_minimum_number_of_adapters
        adapters = @discovery.call

        # Should at least have Base plus the built-in adapters
        assert_operator adapters.size, :>=, 4, "Should discover at least 4 adapters"
      end

      def test_adapter_names_follow_correct_namespace
        adapters = @discovery.call

        adapters.each do |adapter|
          assert adapter.start_with?("CaptainHook::Adapters::"),
                 "Adapter #{adapter} should be in CaptainHook::Adapters namespace"
        end
      end

      def test_adapter_exists_returns_true_for_valid_class
        result = @discovery.send(:adapter_exists?, "CaptainHook::Adapters::Base")
        assert result, "Should return true for valid adapter class"
      end

      def test_adapter_exists_returns_false_for_invalid_class
        result = @discovery.send(:adapter_exists?, "CaptainHook::Adapters::NonExistent")
        refute result, "Should return false for non-existent adapter class"
      end

      def test_discover_gem_adapters_adds_valid_adapters
        discovery = AdapterDiscovery.new
        discovery.send(:discover_gem_adapters)

        # Access the instance variable to check it was populated
        adapters = discovery.instance_variable_get(:@discovered_adapters)
        assert adapters.size > 0, "Should discover at least one gem adapter"
      end

      def test_call_returns_unique_adapters
        # Call twice to ensure uniqueness logic works
        discovery = AdapterDiscovery.new
        discovery.send(:discover_gem_adapters)
        discovery.send(:discover_gem_adapters) # duplicate discovery

        result = discovery.call
        assert_equal result, result.uniq
      end
    end
  end
end
