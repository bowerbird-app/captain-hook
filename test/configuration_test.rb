# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ConfigurationTest < Minitest::Test
    def setup
      @config = Configuration.new
    end

    def test_has_handler_registry
      assert_instance_of HandlerRegistry, @config.handler_registry
    end

    def test_has_hooks
      assert_instance_of CaptainHook::Hooks, @config.hooks
    end

    def test_handler_registry_is_memoized
      registry1 = @config.handler_registry
      registry2 = @config.handler_registry
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

      config1.handler_registry.register(
        provider: "stripe",
        event_type: "test",
        handler_class: "TestHandler"
      )

      refute_same config1.handler_registry, config2.handler_registry
      assert config1.handler_registry.handlers_registered?(provider: "stripe", event_type: "test")
      refute config2.handler_registry.handlers_registered?(provider: "stripe", event_type: "test")
    end
  end
end
