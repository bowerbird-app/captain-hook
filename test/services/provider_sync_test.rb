# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class ProviderSyncTest < ActiveSupport::TestCase
      setup do
        # Clear any existing providers
        CaptainHook::Provider.delete_all

        @provider_definitions = [
          {
            "name" => "test_provider",
            "display_name" => "Test Provider",
            "description" => "A test provider",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "active" => true,
            "signing_secret" => "test_secret",
            "timestamp_tolerance_seconds" => 300,
            "rate_limit_requests" => 100,
            "rate_limit_period" => 60,
            "source_file" => "/test/providers/test_provider.yml",
            "source" => "test"
          }
        ]
      end

      test "creates new provider from definition" do
        sync = ProviderSync.new(@provider_definitions)
        results = sync.call

        assert_equal 1, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:errors].size

        provider = CaptainHook::Provider.find_by(name: "test_provider")
        assert_not_nil provider
        assert_equal "Test Provider", provider.display_name
        assert_equal "A test provider", provider.description
        assert_equal "CaptainHook::Adapters::Base", provider.adapter_class
        assert provider.active?
        assert_equal 300, provider.timestamp_tolerance_seconds
        assert_equal 100, provider.rate_limit_requests
        assert_equal 60, provider.rate_limit_period
      end

      test "updates existing provider from definition" do
        # Create initial provider
        provider = CaptainHook::Provider.create!(
          name: "test_provider",
          display_name: "Old Name",
          adapter_class: "CaptainHook::Adapters::Base",
          signing_secret: "old_secret"
        )

        sync = ProviderSync.new(@provider_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 1, results[:updated].size
        assert_equal 0, results[:errors].size

        provider.reload
        assert_equal "Test Provider", provider.display_name
        assert_equal "A test provider", provider.description
      end

      test "resolves ENV variable references in signing_secret" do
        # Set an environment variable
        ENV["TEST_WEBHOOK_SECRET"] = "secret_from_env"

        definitions = [
          {
            "name" => "env_test_provider",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "signing_secret" => "ENV[TEST_WEBHOOK_SECRET]",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(definitions)
        results = sync.call

        assert_equal 1, results[:created].size
        provider = CaptainHook::Provider.find_by(name: "env_test_provider")
        assert_not_nil provider
        assert_equal "secret_from_env", provider.signing_secret
      ensure
        ENV.delete("TEST_WEBHOOK_SECRET")
      end

      test "handles missing ENV variable gracefully" do
        definitions = [
          {
            "name" => "missing_env_provider",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "signing_secret" => "ENV[NONEXISTENT_VARIABLE]",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(definitions)
        results = sync.call

        assert_equal 1, results[:created].size
        provider = CaptainHook::Provider.find_by(name: "missing_env_provider")
        assert_not_nil provider
        # Should be nil when ENV variable doesn't exist
        assert_nil provider.signing_secret
      end

      test "handles invalid provider definition" do
        invalid_definitions = [
          {
            "name" => "",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(invalid_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 1, results[:errors].size
        assert results[:errors].first[:error].present?
      end

      test "handles multiple providers in one sync" do
        multi_definitions = [
          {
            "name" => "provider_one",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "signing_secret" => "secret1",
            "source" => "test"
          },
          {
            "name" => "provider_two",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "signing_secret" => "secret2",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(multi_definitions)
        results = sync.call

        assert_equal 2, results[:created].size
        assert CaptainHook::Provider.exists?(name: "provider_one")
        assert CaptainHook::Provider.exists?(name: "provider_two")
      end

      test "sets default active to true when not specified" do
        definitions = [
          {
            "name" => "default_active_provider",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(definitions)
        sync.call

        provider = CaptainHook::Provider.find_by(name: "default_active_provider")
        assert provider.active?, "Provider should be active by default"
      end

      test "valid_provider_definition checks for name presence" do
        sync = ProviderSync.new([])
        result = sync.send(:valid_provider_definition?, { "adapter_class" => "Test" })
        refute result, "Should be invalid without name"
      end

      test "valid_provider_definition checks for adapter_class presence" do
        sync = ProviderSync.new([])
        result = sync.send(:valid_provider_definition?, { "name" => "test" })
        refute result, "Should be invalid without adapter_class"
      end

      test "resolve_signing_secret returns nil for blank value" do
        sync = ProviderSync.new([])
        assert_nil sync.send(:resolve_signing_secret, nil)
        assert_nil sync.send(:resolve_signing_secret, "")
      end

      test "resolve_signing_secret returns direct value when not ENV reference" do
        sync = ProviderSync.new([])
        assert_equal "direct_secret", sync.send(:resolve_signing_secret, "direct_secret")
      end

      test "only updates signing_secret when value changes" do
        # Create provider with initial secret
        provider = CaptainHook::Provider.create!(
          name: "test_provider",
          adapter_class: "CaptainHook::Adapters::Base",
          signing_secret: "original_secret"
        )

        # Try to sync with same secret (via ENV)
        ENV["SAME_SECRET"] = "original_secret"
        definitions = [
          {
            "name" => "test_provider",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "signing_secret" => "ENV[SAME_SECRET]",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(definitions)
        sync.call

        provider.reload
        # Secret should remain the same
        assert_equal "original_secret", provider.signing_secret
      ensure
        ENV.delete("SAME_SECRET")
      end

      test "updates signing_secret when value is different" do
        # Create provider with initial secret
        provider = CaptainHook::Provider.create!(
          name: "test_provider",
          adapter_class: "CaptainHook::Adapters::Base",
          signing_secret: "old_secret"
        )

        # Sync with different secret
        ENV["NEW_SECRET"] = "new_secret"
        definitions = [
          {
            "name" => "test_provider",
            "adapter_class" => "CaptainHook::Adapters::Base",
            "signing_secret" => "ENV[NEW_SECRET]",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(definitions)
        sync.call

        provider.reload
        # Secret should be updated
        assert_equal "new_secret", provider.signing_secret
      ensure
        ENV.delete("NEW_SECRET")
      end
    end
  end
end
