# frozen_string_literal: true

require "test_helper"

class ProviderLoaderTest < Minitest::Test
  def setup
    # Create a temporary directory structure to simulate a gem
    @temp_dir = Dir.mktmpdir
    @config_dir = File.join(@temp_dir, "config")
    FileUtils.mkdir_p(@config_dir)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def test_register_providers_from_file_with_single_provider
    # Create a test YAML file
    yaml_content = <<~YAML
      providers:
        - name: stripe
          display_name: Stripe
          adapter_class: CaptainHook::Adapters::Stripe
          description: Stripe payment webhooks
          default_config:
            timestamp_tolerance_seconds: 300
            max_payload_size_bytes: 1048576
            rate_limit_requests: 100
            rate_limit_period: 60
    YAML

    config_path = File.join(@config_dir, "captain_hook_providers.yml")
    File.write(config_path, yaml_content)

    # Test registration
    count = CaptainHook::ProviderLoader.register_providers_from_file(config_path, gem_name: "test_gem")
    assert_equal 1, count
  end

  def test_register_providers_from_file_with_multiple_providers
    yaml_content = <<~YAML
      providers:
        - name: stripe
          display_name: Stripe
          adapter_class: CaptainHook::Adapters::Stripe
        - name: github
          display_name: GitHub
          adapter_class: CaptainHook::Adapters::GitHub
    YAML

    config_path = File.join(@config_dir, "captain_hook_providers.yml")
    File.write(config_path, yaml_content)

    count = CaptainHook::ProviderLoader.register_providers_from_file(config_path, gem_name: "test_gem")
    assert_equal 2, count
  end

  def test_register_providers_from_file_with_empty_config
    yaml_content = <<~YAML
      providers: []
    YAML

    config_path = File.join(@config_dir, "captain_hook_providers.yml")
    File.write(config_path, yaml_content)

    count = CaptainHook::ProviderLoader.register_providers_from_file(config_path, gem_name: "test_gem")
    assert_equal 0, count
  end

  def test_register_providers_from_file_with_no_providers_key
    yaml_content = <<~YAML
      other_config: value
    YAML

    config_path = File.join(@config_dir, "captain_hook_providers.yml")
    File.write(config_path, yaml_content)

    count = CaptainHook::ProviderLoader.register_providers_from_file(config_path, gem_name: "test_gem")
    assert_equal 0, count
  end

  def test_provider_loader_class_exists
    assert_kind_of Class, CaptainHook::ProviderLoader
  end

  def test_provider_loader_responds_to_load_from_gems
    assert_respond_to CaptainHook::ProviderLoader, :load_from_gems
  end

  def test_provider_loader_responds_to_register_providers_from_file
    assert_respond_to CaptainHook::ProviderLoader, :register_providers_from_file
  end
end
