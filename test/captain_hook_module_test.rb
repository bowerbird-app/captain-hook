# frozen_string_literal: true

require "test_helper"

class CaptainHookModuleTest < Minitest::Test
  def setup
    # Reset configuration before each test
    CaptainHook.instance_variable_set(:@configuration, nil)
  end

  def test_configuration_returns_configuration_instance
    config = CaptainHook.configuration

    assert_instance_of CaptainHook::Configuration, config
  end

  def test_configuration_is_memoized
    config1 = CaptainHook.configuration
    config2 = CaptainHook.configuration

    assert_same config1, config2
  end

  def test_configure_yields_configuration
    called = false
    configured_object = nil

    CaptainHook.configure do |config|
      called = true
      configured_object = config
    end

    assert called
    assert_instance_of CaptainHook::Configuration, configured_object
  end

  def test_configure_without_block
    # Should not raise error
    CaptainHook.configure

    # Configuration should still be accessible
    assert_instance_of CaptainHook::Configuration, CaptainHook.configuration
  end

  def test_handler_registry_returns_registry_from_configuration
    registry = CaptainHook.handler_registry

    assert_instance_of CaptainHook::HandlerRegistry, registry
    assert_same CaptainHook.configuration.handler_registry, registry
  end

  def test_register_handler_delegates_to_handler_registry
    CaptainHook.register_handler(
      provider: "test_provider",
      event_type: "test_event",
      handler_class: "TestHandler"
    )

    assert CaptainHook.handler_registry.handlers_registered?(
      provider: "test_provider",
      event_type: "test_event"
    )
  end

  def test_register_handler_with_all_options
    CaptainHook.register_handler(
      provider: "stripe",
      event_type: "payment.succeeded",
      handler_class: "PaymentHandler",
      async: true,
      priority: 50,
      max_attempts: 3,
      retry_delays: [30, 60, 120]
    )

    handlers = CaptainHook.handler_registry.handlers_for(
      provider: "stripe",
      event_type: "payment.succeeded"
    )

    assert_equal 1, handlers.size
    assert_equal "PaymentHandler", handlers.first[:handler_class]
    assert_equal 50, handlers.first[:priority]
  end

  def test_multiple_configurations_independent
    config1 = CaptainHook::Configuration.new
    config2 = CaptainHook::Configuration.new

    config1.retention_days = 30
    config2.retention_days = 90

    refute_same config1, config2
    assert_equal 30, config1.retention_days
    assert_equal 90, config2.retention_days
  end
end
