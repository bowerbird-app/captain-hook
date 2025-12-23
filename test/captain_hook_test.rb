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
    assert_kind_of CaptainHook::HandlerRegistry, registry
    assert_same CaptainHook.configuration.handler_registry, registry
  end

  def test_register_handler_convenience_method
    CaptainHook.register_handler(
      provider: "test",
      event_type: "test.event",
      handler_class: "TestHandler"
    )

    handlers = CaptainHook.handler_registry.handlers_for(
      provider: "test",
      event_type: "test.event"
    )

    assert_equal 1, handlers.size
    assert_equal "TestHandler", handlers.first.handler_class
  ensure
    CaptainHook.handler_registry.clear!
  end
end
