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

  def test_action_registry_returns_registry_from_configuration
    registry = CaptainHook.action_registry

    assert_instance_of CaptainHook::ActionRegistry, registry
    assert_same CaptainHook.configuration.action_registry, registry
  end

  def test_register_action_delegates_to_action_registry
    CaptainHook.register_action(
      provider: "test_provider",
      event_type: "test_event",
      action_class: ".*Action"
    )

    assert CaptainHook.action_registry.actions_registered?(
      provider: "test_provider",
      event_type: "test_event"
    )
  end

  def test_register_action_with_all_options
    CaptainHook.register_action(
      provider: "stripe",
      event_type: "payment.succeeded",
      action_class: "PaymentAction",
      async: true,
      priority: 50,
      max_attempts: 3,
      retry_delays: [30, 60, 120]
    )

    actions = CaptainHook.action_registry.actions_for(
      provider: "stripe",
      event_type: "payment.succeeded"
    )

    assert_equal 1, actions.size
    assert_equal "PaymentAction", actions.first[:action_class]
    assert_equal 50, actions.first[:priority]
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
