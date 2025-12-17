# frozen_string_literal: true

require "test_helper"

class HandlerLoaderTest < Minitest::Test
  def setup
    # Create a temporary directory structure to simulate a gem
    @temp_dir = Dir.mktmpdir
    @config_dir = File.join(@temp_dir, "config")
    FileUtils.mkdir_p(@config_dir)

    # Clear handler registry before each test
    CaptainHook.handler_registry.clear!
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
    CaptainHook.handler_registry.clear!
  end

  def test_register_handlers_from_file_with_single_handler
    # Create a test YAML file
    yaml_content = <<~YAML
      handlers:
        - provider: stripe
          event_type: invoice.paid
          handler_class: StripeInvoiceHandler
          priority: 100
          async: true
    YAML

    config_path = File.join(@config_dir, "captain_hook_handlers.yml")
    File.write(config_path, yaml_content)

    # Test registration
    count = CaptainHook::HandlerLoader.register_handlers_from_file(config_path, gem_name: "test_gem")
    assert_equal 1, count

    # Verify handler was registered
    handlers = CaptainHook.handler_registry.handlers_for(provider: "stripe", event_type: "invoice.paid")
    assert_equal 1, handlers.size
    assert_equal "StripeInvoiceHandler", handlers.first.handler_class
    assert_equal "test_gem", handlers.first.gem_source
  end

  def test_register_handlers_from_file_with_multiple_handlers
    yaml_content = <<~YAML
      handlers:
        - provider: stripe
          event_type: invoice.paid
          handler_class: StripeInvoiceHandler
          priority: 100
          async: true
        - provider: stripe
          event_type: subscription.*
          handler_class: StripeSubscriptionHandler
          priority: 100
          async: true
    YAML

    config_path = File.join(@config_dir, "captain_hook_handlers.yml")
    File.write(config_path, yaml_content)

    count = CaptainHook::HandlerLoader.register_handlers_from_file(config_path, gem_name: "test_gem")
    assert_equal 2, count

    # Verify both handlers were registered
    handlers1 = CaptainHook.handler_registry.handlers_for(provider: "stripe", event_type: "invoice.paid")
    assert_equal 1, handlers1.size

    handlers2 = CaptainHook.handler_registry.handlers_for(provider: "stripe", event_type: "subscription.*")
    assert_equal 1, handlers2.size
  end

  def test_register_handlers_from_file_with_empty_config
    yaml_content = <<~YAML
      handlers: []
    YAML

    config_path = File.join(@config_dir, "captain_hook_handlers.yml")
    File.write(config_path, yaml_content)

    count = CaptainHook::HandlerLoader.register_handlers_from_file(config_path, gem_name: "test_gem")
    assert_equal 0, count
  end

  def test_register_handlers_from_file_with_no_handlers_key
    yaml_content = <<~YAML
      other_config: value
    YAML

    config_path = File.join(@config_dir, "captain_hook_handlers.yml")
    File.write(config_path, yaml_content)

    count = CaptainHook::HandlerLoader.register_handlers_from_file(config_path, gem_name: "test_gem")
    assert_equal 0, count
  end

  def test_handler_loader_class_exists
    assert_kind_of Class, CaptainHook::HandlerLoader
  end

  def test_handler_loader_responds_to_load_from_gems
    assert_respond_to CaptainHook::HandlerLoader, :load_from_gems
  end

  def test_handler_loader_responds_to_register_handlers_from_file
    assert_respond_to CaptainHook::HandlerLoader, :register_handlers_from_file
  end

  def test_handler_config_includes_gem_source
    CaptainHook.register_handler(
      provider: "test",
      event_type: "test.event",
      handler_class: "TestHandler",
      gem_source: "my_gem"
    )

    handlers = CaptainHook.handler_registry.handlers_for(provider: "test", event_type: "test.event")
    assert_equal 1, handlers.size
    assert_equal "my_gem", handlers.first.gem_source
  end
end
