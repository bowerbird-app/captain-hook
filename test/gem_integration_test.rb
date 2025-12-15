# frozen_string_literal: true

require "test_helper"

class GemIntegrationTest < Minitest::Test
  include CaptainHook::GemIntegration

  def setup
    # Clear any existing configuration
    CaptainHook.configuration.outgoing_endpoints.clear
    CaptainHook.handler_registry.clear!

    # Register a test endpoint
    CaptainHook.configure do |config|
      config.register_outgoing_endpoint(
        "test_endpoint",
        base_url: "https://example.com/webhooks",
        signing_secret: "test_secret",
        signing_header: "X-Test-Signature"
      )
    end
  end

  def teardown
    CaptainHook.configuration.outgoing_endpoints.clear
    CaptainHook.handler_registry.clear!
  end

  def test_webhook_configured_returns_true_for_configured_endpoint
    assert webhook_configured?("test_endpoint")
  end

  def test_webhook_configured_returns_false_for_unconfigured_endpoint
    assert_not webhook_configured?("nonexistent_endpoint")
  end

  def test_webhook_url_returns_the_configured_url
    url = webhook_url("test_endpoint")
    assert_equal "https://example.com/webhooks", url
  end

  def test_webhook_url_returns_nil_for_unconfigured_endpoint
    url = webhook_url("nonexistent_endpoint")
    assert_nil url
  end

  def test_register_webhook_handler_registers_a_handler
    register_webhook_handler(
      provider: "test_provider",
      event_type: "test.event",
      handler_class: "TestHandler",
      priority: 50
    )

    handlers = CaptainHook.handler_registry.handlers_for(
      provider: "test_provider",
      event_type: "test.event"
    )

    assert_equal 1, handlers.size
    assert_equal "TestHandler", handlers.first.handler_class
    assert_equal 50, handlers.first.priority
  end

  def test_build_webhook_metadata_includes_default_fields
    metadata = build_webhook_metadata

    assert metadata.key?(:environment)
    assert metadata.key?(:triggered_at)
    assert metadata.key?(:hostname)
  end

  def test_build_webhook_metadata_merges_additional_metadata
    metadata = build_webhook_metadata(
      additional_metadata: { source: "test", version: "1.0" }
    )

    assert_equal "test", metadata[:source]
    assert_equal "1.0", metadata[:version]
    assert metadata.key?(:environment)
    assert metadata.key?(:triggered_at)
  end

  def test_module_methods_work_as_class_methods
    # Test that methods are available as module functions
    assert CaptainHook::GemIntegration.respond_to?(:webhook_configured?)
    assert CaptainHook::GemIntegration.respond_to?(:webhook_url)
    assert CaptainHook::GemIntegration.respond_to?(:register_webhook_handler)
  end
end
