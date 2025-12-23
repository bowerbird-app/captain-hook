# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class HandlerRegistryTest < Minitest::Test
    def setup
      @registry = HandlerRegistry.new
    end

    def teardown
      @registry.clear!
    end

    # === Registration Tests ===

    def test_register_handler_with_required_parameters
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      handlers = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal 1, handlers.size
      assert_equal "PaymentHandler", handlers.first.handler_class
    end

    def test_register_multiple_handlers_for_same_event
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler1"
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler2"
      )

      handlers = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal 2, handlers.size
    end

    def test_register_handlers_for_different_events
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.failed",
        handler_class: "FailureHandler"
      )

      succeeded_handlers = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded")
      failed_handlers = @registry.handlers_for(provider: "stripe", event_type: "payment.failed")

      assert_equal 1, succeeded_handlers.size
      assert_equal 1, failed_handlers.size
      assert_equal "PaymentHandler", succeeded_handlers.first.handler_class
      assert_equal "FailureHandler", failed_handlers.first.handler_class
    end

    def test_register_handler_with_custom_async_option
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler",
        async: false
      )

      handler = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal false, handler.async
    end

    def test_register_handler_with_default_async_true
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      handler = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal true, handler.async
    end

    def test_register_handler_with_custom_retry_delays
      custom_delays = [10, 20, 30]
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler",
        retry_delays: custom_delays
      )

      handler = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal custom_delays, handler.retry_delays
    end

    def test_register_handler_with_default_retry_delays
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      handler = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal [30, 60, 300, 900, 3600], handler.retry_delays
    end

    def test_register_handler_with_custom_max_attempts
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler",
        max_attempts: 10
      )

      handler = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal 10, handler.max_attempts
    end

    def test_register_handler_with_default_max_attempts
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      handler = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal 5, handler.max_attempts
    end

    def test_register_handler_with_custom_priority
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler",
        priority: 50
      )

      handler = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal 50, handler.priority
    end

    def test_register_handler_with_default_priority
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      handler = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal 100, handler.priority
    end

    # === Priority Sorting Tests ===

    def test_handlers_sorted_by_priority
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "HighPriorityHandler",
        priority: 10
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "LowPriorityHandler",
        priority: 100
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "MediumPriorityHandler",
        priority: 50
      )

      handlers = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal "HighPriorityHandler", handlers[0].handler_class
      assert_equal "MediumPriorityHandler", handlers[1].handler_class
      assert_equal "LowPriorityHandler", handlers[2].handler_class
    end

    def test_handlers_with_same_priority_sorted_by_class_name
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "ZebraHandler",
        priority: 100
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "AlphaHandler",
        priority: 100
      )

      handlers = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal "AlphaHandler", handlers[0].handler_class
      assert_equal "ZebraHandler", handlers[1].handler_class
    end

    # === Query Tests ===

    def test_handlers_registered_returns_true_when_handlers_exist
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      assert @registry.handlers_registered?(provider: "stripe", event_type: "payment.succeeded")
    end

    def test_handlers_registered_returns_false_when_no_handlers_exist
      refute @registry.handlers_registered?(provider: "stripe", event_type: "payment.succeeded")
    end

    def test_handlers_for_returns_empty_array_when_no_handlers
      handlers = @registry.handlers_for(provider: "unknown", event_type: "unknown.event")
      assert_equal [], handlers
    end

    def test_providers_returns_registered_provider_names
      @registry.register(provider: "stripe", event_type: "payment.succeeded", handler_class: "Handler1")
      @registry.register(provider: "square", event_type: "payment.succeeded", handler_class: "Handler2")
      @registry.register(provider: "stripe", event_type: "payment.failed", handler_class: "Handler3")

      providers = @registry.providers
      assert_equal 2, providers.size
      assert_includes providers, "stripe"
      assert_includes providers, "square"
    end

    def test_providers_returns_empty_array_when_no_handlers
      assert_equal [], @registry.providers
    end

    def test_find_handler_config_finds_correct_handler
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      config = @registry.find_handler_config(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      refute_nil config
      assert_equal "PaymentHandler", config.handler_class
    end

    def test_find_handler_config_returns_nil_when_not_found
      config = @registry.find_handler_config(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "NonexistentHandler"
      )

      assert_nil config
    end

    # === Clear Tests ===

    def test_clear_removes_all_handlers
      @registry.register(provider: "stripe", event_type: "payment.succeeded", handler_class: "Handler1")
      @registry.register(provider: "square", event_type: "payment.succeeded", handler_class: "Handler2")

      @registry.clear!

      assert_equal [], @registry.providers
      refute @registry.handlers_registered?(provider: "stripe", event_type: "payment.succeeded")
      refute @registry.handlers_registered?(provider: "square", event_type: "payment.succeeded")
    end

    # === HandlerConfig Tests ===

    def test_handler_config_delay_for_attempt
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler",
        retry_delays: [10, 20, 30]
      )

      config = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first

      assert_equal 10, config.delay_for_attempt(0)
      assert_equal 20, config.delay_for_attempt(1)
      assert_equal 30, config.delay_for_attempt(2)
      # Should return last delay for attempts beyond array size
      assert_equal 30, config.delay_for_attempt(3)
      assert_equal 30, config.delay_for_attempt(10)
    end

    def test_handler_config_delay_for_attempt_with_empty_delays
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler",
        retry_delays: []
      )

      config = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded").first

      # Should return default 3600 when delays array is empty
      assert_equal 3600, config.delay_for_attempt(0)
      assert_equal 3600, config.delay_for_attempt(5)
    end

    # === Thread Safety Tests ===

    def test_register_is_thread_safe
      threads = []
      100.times do |i|
        threads << Thread.new do
          @registry.register(
            provider: "stripe",
            event_type: "payment.succeeded",
            handler_class: "Handler#{i}"
          )
        end
      end

      threads.each(&:join)

      handlers = @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal 100, handlers.size
    end

    def test_handlers_for_is_thread_safe
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler"
      )

      results = []
      threads = []
      100.times do
        threads << Thread.new do
          results << @registry.handlers_for(provider: "stripe", event_type: "payment.succeeded")
        end
      end

      threads.each(&:join)

      # All threads should get the same result
      assert(results.all? { |r| r.size == 1 })
    end

    def test_handler_config_delay_for_attempt_returns_correct_delay
      config = CaptainHook::HandlerRegistry::HandlerConfig.new(
        provider: "test",
        event_type: "test",
        handler_class: "TestHandler",
        retry_delays: [10, 20, 30]
      )

      assert_equal 10, config.delay_for_attempt(0)
      assert_equal 20, config.delay_for_attempt(1)
      assert_equal 30, config.delay_for_attempt(2)
    end

    def test_handler_config_delay_for_attempt_returns_last_delay_when_out_of_bounds
      config = CaptainHook::HandlerRegistry::HandlerConfig.new(
        provider: "test",
        event_type: "test",
        handler_class: "TestHandler",
        retry_delays: [10, 20]
      )

      # Attempt beyond array should return last delay
      assert_equal 20, config.delay_for_attempt(5)
    end

    def test_handler_config_delay_for_attempt_returns_default_when_empty_delays
      config = CaptainHook::HandlerRegistry::HandlerConfig.new(
        provider: "test",
        event_type: "test",
        handler_class: "TestHandler",
        retry_delays: []
      )

      # Should return default 3600 when no delays configured
      assert_equal 3600, config.delay_for_attempt(0)
    end

    def test_handler_config_async_defaults_to_true_when_nil
      config = CaptainHook::HandlerRegistry::HandlerConfig.new(
        provider: "test",
        event_type: "test",
        handler_class: "TestHandler",
        async: nil
      )

      assert_equal true, config.async
    end

    def test_handler_config_retry_delays_has_default
      config = CaptainHook::HandlerRegistry::HandlerConfig.new(
        provider: "test",
        event_type: "test",
        handler_class: "TestHandler"
      )

      assert_equal [30, 60, 300, 900, 3600], config.retry_delays
    end

    def test_handler_config_max_attempts_has_default
      config = CaptainHook::HandlerRegistry::HandlerConfig.new(
        provider: "test",
        event_type: "test",
        handler_class: "TestHandler"
      )

      assert_equal 5, config.max_attempts
    end

    def test_handler_config_priority_has_default
      config = CaptainHook::HandlerRegistry::HandlerConfig.new(
        provider: "test",
        event_type: "test",
        handler_class: "TestHandler"
      )

      assert_equal 100, config.priority
    end

    def test_handler_config_returns_nil_when_no_retry_delays
      config = CaptainHook::HandlerRegistry::HandlerConfig.new(
        provider: "test",
        event_type: "test",
        handler_class: "TestHandler",
        retry_delays: nil
      )

      # Should use default when retry_delays is nil
      assert_equal [30, 60, 300, 900, 3600], config.retry_delays
    end

    def test_providers_returns_unique_provider_names
      @registry.register(provider: "stripe", event_type: "payment.succeeded", handler_class: "Handler1")
      @registry.register(provider: "stripe", event_type: "payment.failed", handler_class: "Handler2")
      @registry.register(provider: "paypal", event_type: "sale.completed", handler_class: "Handler3")

      providers = @registry.providers
      assert_equal 2, providers.size
      assert_includes providers, "stripe"
      assert_includes providers, "paypal"
    end

    def test_providers_returns_empty_array_when_no_registrations
      providers = @registry.providers
      assert_equal [], providers
    end
  end
end
