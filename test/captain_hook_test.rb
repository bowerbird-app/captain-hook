# frozen_string_literal: true

require "test_helper"

class CaptainHookTest < Minitest::Test
  def test_version_exists
    refute_nil ::CaptainHook::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::CaptainHook::Engine
  end

  def test_configuration_returns_configuration_instance
    config = CaptainHook.configuration
    assert_kind_of CaptainHook::Configuration, config
  end

  def test_configuration_is_memoized
    config1 = CaptainHook.configuration
    config2 = CaptainHook.configuration
    assert_same config1, config2
  end

  def test_configure_yields_configuration
    yielded_config = nil
    CaptainHook.configure do |config|
      yielded_config = config
    end

    assert_kind_of CaptainHook::Configuration, yielded_config
    assert_same CaptainHook.configuration, yielded_config
  end

  def test_handler_registry_convenience_method
    registry = CaptainHook.handler_registry
    assert_kind_of CaptainHook::ActionRegistry, registry
    assert_same CaptainHook.configuration.handler_registry, registry
  end

  def test_register_action_convenience_method
    CaptainHook.handler_registry.clear!

    CaptainHook.register_action(
      provider: "test",
      event_type: "test.event",
      action_class: "TestAction"
    )

    handlers = CaptainHook.handler_registry.actions_for(
      provider: "test",
      event_type: "test.event"
    )

    assert_equal 1, handlers.size
    assert_equal "TestAction", handlers.first.action_class
  ensure
    CaptainHook.handler_registry.clear!
  end
end
