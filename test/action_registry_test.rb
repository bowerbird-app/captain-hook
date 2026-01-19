# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ActionRegistryTest < Minitest::Test
    def setup
      @registry = ActionRegistry.new
    end

    def teardown
      @registry.clear!
    end

    # === Registration Tests ===

    def test_register_handler_with_required_parameters
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      actions = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal 1, actions.size
      assert_equal "Payment Action", actions.first.action_class
    end

    def test_register_multiple_actions_for_same_event
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action1"
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action2"
      )

      actions = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal 2, actions.size
    end

    def test_register_actions_for_different_events
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.failed",
        action_class: "Failure Action"
      )

      succeeded_actions = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded")
      failed_actions = @registry.actions_for(provider: "stripe", event_type: "payment.failed")

      assert_equal 1, succeeded_actions.size
      assert_equal 1, failed_actions.size
      assert_equal "Payment Action", succeeded_actions.first.action_class
      assert_equal "Failure Action", failed_actions.first.action_class
    end

    def test_register_handler_with_custom_async_option
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action",
        async: false
      )

      action = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal false, action.async
    end

    def test_register_handler_with_default_async_true
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      action = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal true, action.async
    end

    def test_register_handler_with_custom_retry_delays
      custom_delays = [10, 20, 30]
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action",
        retry_delays: custom_delays
      )

      action = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal custom_delays, action.retry_delays
    end

    def test_register_handler_with_default_retry_delays
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      action = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal [30, 60, 300, 900, 3600], action.retry_delays
    end

    def test_register_handler_with_custom_max_attempts
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action",
        max_attempts: 10
      )

      action = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal 10, action.max_attempts
    end

    def test_register_handler_with_default_max_attempts
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      action = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal 5, action.max_attempts
    end

    def test_register_handler_with_custom_priority
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action",
        priority: 50
      )

      action = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal 50, action.priority
    end

    def test_register_handler_with_default_priority
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      action = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first
      assert_equal 100, action.priority
    end

    # === Priority Sorting Tests ===

    def test_actions_sorted_by_priority
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "HighPriority Action",
        priority: 10
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "LowPriority Action",
        priority: 100
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "MediumPriority Action",
        priority: 50
      )

      actions = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal "HighPriority Action", actions[0].action_class
      assert_equal "MediumPriority Action", actions[1].action_class
      assert_equal "LowPriority Action", actions[2].action_class
    end

    def test_actions_with_same_priority_sorted_by_class_name
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Zebra Action",
        priority: 100
      )
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Alpha Action",
        priority: 100
      )

      actions = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal "Alpha Action", actions[0].action_class
      assert_equal "Zebra Action", actions[1].action_class
    end

    # === Query Tests ===

    def test_actions_registered_returns_true_when_actions_exist
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      assert @registry.actions_registered?(provider: "stripe", event_type: "payment.succeeded")
    end

    def test_actions_registered_returns_false_when_no_actions_exist
      refute @registry.actions_registered?(provider: "stripe", event_type: "payment.succeeded")
    end

    def test_actions_for_returns_empty_array_when_no_actions
      actions = @registry.actions_for(provider: "unknown", event_type: "unknown.event")
      assert_equal [], actions
    end

    def test_providers_returns_registered_provider_names
      @registry.register(provider: "stripe", event_type: "payment.succeeded", action_class: " Action1")
      @registry.register(provider: "square", event_type: "payment.succeeded", action_class: " Action2")
      @registry.register(provider: "stripe", event_type: "payment.failed", action_class: " Action3")

      providers = @registry.providers
      assert_equal 2, providers.size
      assert_includes providers, "stripe"
      assert_includes providers, "square"
    end

    def test_providers_returns_empty_array_when_no_actions
      assert_equal [], @registry.providers
    end

    def test_find_handler_config_finds_correct_handler
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      config = @registry.find_handler_config(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      refute_nil config
      assert_equal "Payment Action", config.action_class
    end

    def test_find_handler_config_returns_nil_when_not_found
      config = @registry.find_handler_config(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Nonexistent Action"
      )

      assert_nil config
    end

    # === Clear Tests ===

    def test_clear_removes_all_actions
      @registry.register(provider: "stripe", event_type: "payment.succeeded", action_class: " Action1")
      @registry.register(provider: "square", event_type: "payment.succeeded", action_class: " Action2")

      @registry.clear!

      assert_equal [], @registry.providers
      refute @registry.actions_registered?(provider: "stripe", event_type: "payment.succeeded")
      refute @registry.actions_registered?(provider: "square", event_type: "payment.succeeded")
    end

    # ===  ActionConfig Tests ===

    def test_handler_config_delay_for_attempt
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action",
        retry_delays: [10, 20, 30]
      )

      config = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first

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
        action_class: "Payment Action",
        retry_delays: []
      )

      config = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded").first

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
            action_class: " Action#{i}"
          )
        end
      end

      threads.each(&:join)

      actions = @registry.actions_for(provider: "stripe", event_type: "payment.succeeded")
      assert_equal 100, actions.size
    end

    def test_actions_for_is_thread_safe
      @registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "Payment Action"
      )

      results = []
      threads = []
      100.times do
        threads << Thread.new do
          results << @registry.actions_for(provider: "stripe", event_type: "payment.succeeded")
        end
      end

      threads.each(&:join)

      # All threads should get the same result
      assert(results.all? { |r| r.size == 1 })
    end

    def test_handler_config_delay_for_attempt_returns_correct_delay
      config = CaptainHook::ActionRegistry:: ActionConfig.new(
        provider: "test",
        event_type: "test",
        action_class: "Test Action",
        retry_delays: [10, 20, 30]
      )

      assert_equal 10, config.delay_for_attempt(0)
      assert_equal 20, config.delay_for_attempt(1)
      assert_equal 30, config.delay_for_attempt(2)
    end

    def test_handler_config_delay_for_attempt_returns_last_delay_when_out_of_bounds
      config = CaptainHook::ActionRegistry:: ActionConfig.new(
        provider: "test",
        event_type: "test",
        action_class: "Test Action",
        retry_delays: [10, 20]
      )

      # Attempt beyond array should return last delay
      assert_equal 20, config.delay_for_attempt(5)
    end

    def test_handler_config_delay_for_attempt_returns_default_when_empty_delays
      config = CaptainHook::ActionRegistry:: ActionConfig.new(
        provider: "test",
        event_type: "test",
        action_class: "Test Action",
        retry_delays: []
      )

      # Should return default 3600 when no delays configured
      assert_equal 3600, config.delay_for_attempt(0)
    end

    def test_handler_config_async_defaults_to_true_when_nil
      config = CaptainHook::ActionRegistry:: ActionConfig.new(
        provider: "test",
        event_type: "test",
        action_class: "Test Action",
        async: nil
      )

      assert_equal true, config.async
    end

    def test_handler_config_retry_delays_has_default
      config = CaptainHook::ActionRegistry:: ActionConfig.new(
        provider: "test",
        event_type: "test",
        action_class: "Test Action"
      )

      assert_equal [30, 60, 300, 900, 3600], config.retry_delays
    end

    def test_handler_config_max_attempts_has_default
      config = CaptainHook::ActionRegistry:: ActionConfig.new(
        provider: "test",
        event_type: "test",
        action_class: "Test Action"
      )

      assert_equal 5, config.max_attempts
    end

    def test_handler_config_priority_has_default
      config = CaptainHook::ActionRegistry:: ActionConfig.new(
        provider: "test",
        event_type: "test",
        action_class: "Test Action"
      )

      assert_equal 100, config.priority
    end

    def test_handler_config_returns_nil_when_no_retry_delays
      config = CaptainHook::ActionRegistry:: ActionConfig.new(
        provider: "test",
        event_type: "test",
        action_class: "Test Action",
        retry_delays: nil
      )

      # Should use default when retry_delays is nil
      assert_equal [30, 60, 300, 900, 3600], config.retry_delays
    end

    def test_providers_returns_unique_provider_names
      @registry.register(provider: "stripe", event_type: "payment.succeeded", action_class: " Action1")
      @registry.register(provider: "stripe", event_type: "payment.failed", action_class: " Action2")
      @registry.register(provider: "paypal", event_type: "sale.completed", action_class: " Action3")

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
