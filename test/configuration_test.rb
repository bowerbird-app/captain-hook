# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ConfigurationTest < Minitest::Test
    def setup
      @config = Configuration.new
    end

    def test_has_action_registry
      assert_instance_of ActionRegistry, @config.action_registry
    end

    def test_has_hooks
      assert_instance_of CaptainHook::Hooks, @config.hooks
    end

    def test_action_registry_is_memoized
      registry1 = @config.action_registry
      registry2 = @config.action_registry
      assert_same registry1, registry2
    end

    def test_hooks_is_memoized
      hooks1 = @config.hooks
      hooks2 = @config.hooks
      assert_same hooks1, hooks2
    end

    def test_configuration_is_independent_per_instance
      config1 = Configuration.new
      config2 = Configuration.new

      config1.action_registry.register(
        provider: "stripe",
        event_type: "test",
        action_class: "TestAction"
      )

      refute_same config1.action_registry, config2.action_registry
      assert config1.action_registry.actions_registered?(provider: "stripe", event_type: "test")
      refute config2.action_registry.actions_registered?(provider: "stripe", event_type: "test")
    end

    def test_to_h_returns_configuration_summary
      @config.admin_parent_controller = "AdminController"
      @config.retention_days = 30
      @config.register_provider("stripe", signing_secret: "secret")

      hash = @config.to_h

      assert_equal "AdminController", hash[:admin_parent_controller]
      assert_equal 30, hash[:retention_days]
      assert_includes hash[:providers], "stripe"
      assert hash[:hooks_registered].is_a?(Hash)
    end

    def test_merge_updates_attributes
      @config.merge!(
        admin_parent_controller: "NewController",
        retention_days: 45
      )

      assert_equal "NewController", @config.admin_parent_controller
      assert_equal 45, @config.retention_days
    end

    def test_merge_ignores_unknown_attributes
      @config.merge!(unknown_attribute: "value")

      # Should not raise error, just ignore unknown attributes
      assert_equal "ApplicationController", @config.admin_parent_controller
    end

    def test_merge_handles_string_keys
      @config.merge!(
        "admin_parent_controller" => "StringKeyController",
        "retention_days" => 60
      )

      assert_equal "StringKeyController", @config.admin_parent_controller
      assert_equal 60, @config.retention_days
    end

    def test_merge_returns_nil_for_non_enumerable
      result = @config.merge!(nil)
      assert_nil result

      result = @config.merge!("not a hash")
      assert_nil result
    end

    def test_provider_returns_db_provider_first
      # Create a provider in the database
      db_provider = CaptainHook::Provider.find_or_create_by!(name: "stripe") do |p|
        p.active = true
      end

      # Also register in memory
      @config.register_provider("stripe", signing_secret: "memory_secret")

      # Should prioritize database
      provider_config = @config.provider("stripe")
      # NOTE: signing_secret now comes from registry, not DB
      assert_equal "memory_secret", provider_config.signing_secret
    ensure
      db_provider&.destroy
    end

    def test_provider_falls_back_to_memory_registration
      @config.register_provider("test_provider", signing_secret: "memory_secret")

      provider_config = @config.provider("test_provider")
      assert_equal "memory_secret", provider_config.signing_secret
    end

    def test_provider_returns_nil_for_unknown_provider
      assert_nil @config.provider("unknown_provider")
    end

    def test_provider_uses_db_and_registry_attributes
      # Create provider in database (minimal fields)
      provider_model = CaptainHook::Provider.find_or_create_by!(name: "test_provider") do |p|
        p.token = "test_token"
        p.active = true
        p.rate_limit_requests = 50
        p.rate_limit_period = 120
      end

      # Register in memory with additional attributes
      @config.register_provider("test_provider",
                                signing_secret: "test_secret",
                                verifier_class: "TestVerifier")

      # Get provider config (should combine DB and registry)
      provider_config = @config.provider("test_provider")

      assert_equal "test_provider", provider_config.name
      assert_equal "test_token", provider_config.token
      assert_equal 50, provider_config.rate_limit_requests
      assert_equal 120, provider_config.rate_limit_period
      assert_equal "test_secret", provider_config.signing_secret
      assert_equal "TestVerifier", provider_config.verifier_class
    ensure
      provider_model&.destroy
    end

    def test_admin_parent_controller_default
      assert_equal "ApplicationController", @config.admin_parent_controller
    end

    def test_admin_layout_default
      assert_equal "application", @config.admin_layout
    end

    def test_retention_days_default
      assert_equal 90, @config.retention_days
    end

    def test_providers_returns_hash
      assert_instance_of Hash, @config.providers
    end

    def test_register_provider_stores_in_hash
      @config.register_provider("test", signing_secret: "secret")

      assert @config.providers.key?("test")
      assert_instance_of CaptainHook::ProviderConfig, @config.providers["test"]
    end

    def test_hooks_returns_hooks_instance
      assert_instance_of CaptainHook::Hooks, @config.hooks
    end

    def test_action_registry_returns_registry_instance
      assert_instance_of CaptainHook::ActionRegistry, @config.action_registry
    end
  end
end
