# frozen_string_literal: true

require "test_helper"

class GemCommunicationTest < Minitest::Test
  def setup
    CaptainHook.handler_registry.clear!
  end

  def teardown
    CaptainHook.handler_registry.clear!
  end

  def test_captain_hook_responds_to_register_provider
    assert_respond_to CaptainHook, :register_provider
  end

  def test_captain_hook_responds_to_register_handler
    assert_respond_to CaptainHook, :register_handler
  end

  def test_register_handler_with_gem_source
    CaptainHook.register_handler(
      provider: "stripe",
      event_type: "invoice.paid",
      handler_class: "StripeInvoiceHandler",
      gem_source: "stripe_billing_gem",
      priority: 50,
      async: true
    )

    handlers = CaptainHook.handler_registry.handlers_for(provider: "stripe", event_type: "invoice.paid")
    assert_equal 1, handlers.size

    handler = handlers.first
    assert_equal "stripe", handler.provider
    assert_equal "invoice.paid", handler.event_type
    assert_equal "StripeInvoiceHandler", handler.handler_class
    assert_equal "stripe_billing_gem", handler.gem_source
    assert_equal 50, handler.priority
    assert_equal true, handler.async
  end

  def test_register_handler_without_gem_source_defaults_to_nil
    CaptainHook.register_handler(
      provider: "github",
      event_type: "push",
      handler_class: "GithubPushHandler"
    )

    handlers = CaptainHook.handler_registry.handlers_for(provider: "github", event_type: "push")
    assert_equal 1, handlers.size
    assert_nil handlers.first.gem_source
  end

  def test_handler_registry_tracks_multiple_gems
    # Register handlers from different gems
    CaptainHook.register_handler(
      provider: "stripe",
      event_type: "invoice.paid",
      handler_class: "GemA::InvoiceHandler",
      gem_source: "gem_a"
    )

    CaptainHook.register_handler(
      provider: "stripe",
      event_type: "invoice.paid",
      handler_class: "GemB::InvoiceHandler",
      gem_source: "gem_b"
    )

    handlers = CaptainHook.handler_registry.handlers_for(provider: "stripe", event_type: "invoice.paid")
    assert_equal 2, handlers.size

    gem_sources = handlers.map(&:gem_source).sort
    assert_equal ["gem_a", "gem_b"], gem_sources
  end

  def test_handler_config_struct_includes_gem_source
    config = CaptainHook::HandlerRegistry::HandlerConfig.new(
      provider: "test",
      event_type: "test.event",
      handler_class: "TestHandler",
      gem_source: "test_gem"
    )

    assert_equal "test", config.provider
    assert_equal "test.event", config.event_type
    assert_equal "TestHandler", config.handler_class
    assert_equal "test_gem", config.gem_source
  end

  def test_handler_config_gem_source_defaults_to_nil
    config = CaptainHook::HandlerRegistry::HandlerConfig.new(
      provider: "test",
      event_type: "test.event",
      handler_class: "TestHandler"
    )

    assert_nil config.gem_source
  end
end
