# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ProviderConfigTest < Minitest::Test
    def setup
      @config_data = {
        "name" => "stripe",
        "display_name" => "Stripe",
        "verifier_class" => "CaptainHook::Verifiers::Stripe",
        "signing_secret" => "whsec_test123",
        "rate_limit_requests" => 100,
        "rate_limit_period" => 60,
        "active" => true
      }
      @provider_config = ProviderConfig.new(@config_data)
    end

    # === Basic Attribute Tests ===

    def test_reads_name
      assert_equal "stripe", @provider_config.name
    end

    def test_reads_display_name
      assert_equal "Stripe", @provider_config.display_name
    end

    def test_reads_verifier_class
      assert_equal "CaptainHook::Verifiers::Stripe", @provider_config.verifier_class
    end

    def test_reads_signing_secret
      assert_equal "whsec_test123", @provider_config.signing_secret
    end

    def test_reads_rate_limit_requests
      assert_equal 100, @provider_config.rate_limit_requests
    end

    def test_reads_rate_limit_period
      assert_equal 60, @provider_config.rate_limit_period
    end

    def test_reads_active_status
      assert_equal true, @provider_config.active
    end

    # === Default Values Tests ===

    def test_defaults_active_to_true
      config = ProviderConfig.new("name" => "test")
      assert_equal true, config.active
    end

    def test_loads_timestamp_tolerance_from_global_config
      # GlobalConfigLoader should provide default of 300
      config = ProviderConfig.new("name" => "test")
      assert_equal 300, config.timestamp_tolerance_seconds
    end

    def test_loads_max_payload_size_from_global_config
      # GlobalConfigLoader should provide default of 1MB
      config = ProviderConfig.new("name" => "test")
      assert_equal 1_048_576, config.max_payload_size_bytes
    end

    def test_allows_custom_timestamp_tolerance
      config = ProviderConfig.new("name" => "test", "timestamp_tolerance_seconds" => 600)
      assert_equal 600, config.timestamp_tolerance_seconds
    end

    def test_allows_custom_max_payload_size
      config = ProviderConfig.new("name" => "test", "max_payload_size_bytes" => 2_097_152)
      assert_equal 2_097_152, config.max_payload_size_bytes
    end

    def test_allows_inactive_provider
      config = ProviderConfig.new("name" => "test", "active" => false)
      assert_equal false, config.active
    end

    # === Validation Tests ===

    def test_requires_name
      assert_raises(ArgumentError, KeyError) do
        ProviderConfig.new({})
      end
    end

    def test_accepts_minimal_config
      config = ProviderConfig.new("name" => "minimal")
      assert_equal "minimal", config.name
    end

    # === Verifier Class Tests ===

    def test_can_instantiate_verifier_class
      verifier_class = @provider_config.verifier_class.constantize
      assert verifier_class.ancestors.include?(CaptainHook::Verifiers::Base)
    end

    def test_validates_verifier_class_exists
      config = ProviderConfig.new(
        "name" => "test",
        "verifier_class" => "CaptainHook::Verifiers::Stripe"
      )

      # Should not raise an error
      verifier_class = config.verifier_class.constantize
      assert_kind_of Class, verifier_class
    end

    # === ENV Variable Resolution Tests ===

    def test_resolves_env_variable_in_signing_secret
      ENV["TEST_WEBHOOK_SECRET"] = "secret_from_env"

      config = ProviderConfig.new(
        "name" => "test",
        "signing_secret" => "ENV[TEST_WEBHOOK_SECRET]"
      )

      assert_equal "secret_from_env", config.resolve_signing_secret
    ensure
      ENV.delete("TEST_WEBHOOK_SECRET")
    end

    def test_returns_literal_value_when_not_env_reference
      config = ProviderConfig.new(
        "name" => "test",
        "signing_secret" => "literal_secret"
      )

      assert_equal "literal_secret", config.resolve_signing_secret
    end

    def test_handles_missing_env_variable_gracefully
      config = ProviderConfig.new(
        "name" => "test",
        "signing_secret" => "ENV[NONEXISTENT_VAR]"
      )

      # Should return nil or empty string for missing ENV vars
      result = config.resolve_signing_secret
      assert [nil, ""].include?(result)
    end

    # === Boolean Predicate Methods ===

    def test_active_predicate_method
      active_config = ProviderConfig.new("name" => "test", "active" => true)
      inactive_config = ProviderConfig.new("name" => "test", "active" => false)

      assert active_config.active?
      refute inactive_config.active?
    end

    # === Comparison Tests ===

    def test_configs_with_same_name_are_equal
      config1 = ProviderConfig.new("name" => "stripe")
      config2 = ProviderConfig.new("name" => "stripe")

      assert_equal config1, config2
    end

    def test_configs_with_different_names_are_not_equal
      config1 = ProviderConfig.new("name" => "stripe")
      config2 = ProviderConfig.new("name" => "other_provider")

      refute_equal config1, config2
    end

    # === Hash Access Tests ===

    def test_allows_hash_style_access
      assert_equal "stripe", @provider_config["name"]
      assert_equal "Stripe", @provider_config["display_name"]
    end

    def test_allows_symbol_key_access
      assert_equal "stripe", @provider_config[:name]
      assert_equal "Stripe", @provider_config[:display_name]
    end

    # === to_h Tests ===

    def test_converts_to_hash
      hash = @provider_config.to_h

      assert_instance_of Hash, hash
      assert_equal "stripe", hash["name"]
      assert_equal "Stripe", hash["display_name"]
    end

    def test_to_h_includes_all_attributes
      hash = @provider_config.to_h

      assert_includes hash.keys, "name"
      assert_includes hash.keys, "display_name"
      assert_includes hash.keys, "verifier_class"
      assert_includes hash.keys, "raw_signing_secret"
    end

    # === Metadata Tests ===

    def test_stores_source_metadata
      config_with_source = ProviderConfig.new(
        "name" => "test",
        "source" => "application",
        "source_file" => "/path/to/config.yml"
      )

      assert_equal "application", config_with_source.source
      assert_equal "/path/to/config.yml", config_with_source.source_file
    end

    # === Optional Fields Tests ===

    def test_handles_optional_description
      config = ProviderConfig.new(
        "name" => "test",
        "description" => "Test webhook provider"
      )

      assert_equal "Test webhook provider", config.description
    end

    def test_handles_optional_webhook_url
      config = ProviderConfig.new(
        "name" => "test",
        "webhook_url" => "https://example.com/webhooks"
      )

      assert_equal "https://example.com/webhooks", config.webhook_url
    end

    # === Edge Cases ===

    def test_handles_string_numbers_in_config
      config = ProviderConfig.new(
        "name" => "test",
        "timestamp_tolerance_seconds" => "600",
        "rate_limit_requests" => "200"
      )

      # Should handle string-to-integer conversion
      assert_kind_of Integer, config.timestamp_tolerance_seconds
      assert_kind_of Integer, config.rate_limit_requests
    end

    def test_handles_nil_values
      config = ProviderConfig.new(
        "name" => "test",
        "description" => nil,
        "display_name" => nil
      )

      assert_nil config.description
      # Display name might default to name
      assert [nil, "test"].include?(config.display_name)
    end

    def test_bracket_access_for_valid_fields
      config = ProviderConfig.new(
        "name" => "test",
        "description" => "test description"
      )

      assert_equal "test description", config["description"]
    end

    def test_bracket_access_returns_nil_for_undefined_keys
      config = ProviderConfig.new("name" => "test")

      assert_nil config["undefined_key"]
    end

    def test_to_h_returns_all_attributes
      config = ProviderConfig.new(
        "name" => "test",
        "signing_secret" => "secret",
        "verifier_class" => "TestVerifier"
      )

      hash = config.to_h
      assert hash.is_a?(Hash)
      assert_equal "test", hash["name"]
      assert hash.key?("signing_secret")
      assert hash.key?("verifier_class")
    end

    def test_config_with_empty_string_values
      config = ProviderConfig.new(
        "name" => "test",
        "signing_secret" => "",
        "description" => ""
      )

      assert_nil config.signing_secret # Empty string treated as no secret
      assert_equal "", config.description
    end

    def test_active_defaults_to_true
      config = ProviderConfig.new("name" => "test")

      assert config.active?
    end

    def test_verifier_class_defaults_to_base
      config = ProviderConfig.new("name" => "test")

      assert_equal "CaptainHook::Verifiers::Base", config.verifier_class
    end

    def test_rate_limiting_enabled_returns_true_when_both_present
      config = ProviderConfig.new(
        "name" => "test",
        "rate_limit_requests" => 100,
        "rate_limit_period" => 60
      )

      assert config.rate_limiting_enabled?
    end

    def test_rate_limiting_enabled_returns_true_with_defaults
      config = ProviderConfig.new("name" => "test")

      # Defaults are set, so rate limiting is enabled by default
      assert config.rate_limiting_enabled?
    end

    def test_payload_size_limit_enabled_returns_true_when_present_and_positive
      config = ProviderConfig.new(
        "name" => "test",
        "max_payload_size_bytes" => 1_048_576
      )

      assert config.payload_size_limit_enabled?
    end

    def test_payload_size_limit_enabled_returns_false_when_zero
      config = ProviderConfig.new(
        "name" => "test",
        "max_payload_size_bytes" => 0
      )

      refute config.payload_size_limit_enabled?
    end

    def test_timestamp_validation_enabled_returns_true_when_positive
      config = ProviderConfig.new(
        "name" => "test",
        "timestamp_tolerance_seconds" => 300
      )

      assert config.timestamp_validation_enabled?
    end

    def test_timestamp_validation_enabled_returns_false_when_zero
      config = ProviderConfig.new(
        "name" => "test",
        "timestamp_tolerance_seconds" => 0
      )

      refute config.timestamp_validation_enabled?
    end

    def test_verifier_returns_verifier_instance
      config = ProviderConfig.new(
        "name" => "test",
        "verifier_class" => "CaptainHook::Verifiers::Base"
      )

      verifier = config.verifier
      assert_instance_of CaptainHook::Verifiers::Base, verifier
    end

    def test_verifier_is_memoized
      config = ProviderConfig.new(
        "name" => "test",
        "verifier_class" => "CaptainHook::Verifiers::Base"
      )

      verifier1 = config.verifier
      verifier2 = config.verifier
      assert_same verifier1, verifier2
    end

    def test_display_name_can_be_explicitly_nil
      config = ProviderConfig.new(
        "name" => "test",
        "display_name" => nil
      )

      # When explicitly nil, display_name remains nil (doesn't default to name.titleize)
      assert_nil config.display_name
    end

    def test_to_h_compacts_nil_values
      config = ProviderConfig.new(
        "name" => "test",
        "description" => nil
      )

      hash = config.to_h
      refute hash.key?("description"), "Nil values should be compacted"
      assert hash.key?("name")
    end
  end
end
