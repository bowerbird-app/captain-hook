# frozen_string_literal: true

require "test_helper"

class HooksTest < Minitest::Test
  def setup
    @hooks = GemTemplate::Hooks.new
  end

  def teardown
    @hooks.clear!
  end

  # === Registration Tests ===

  def test_before_initialize_registration
    called = false
    @hooks.before_initialize { called = true }

    assert @hooks.registered?(:before_initialize)
    @hooks.run(:before_initialize)
    assert called
  end

  def test_after_initialize_registration
    called = false
    @hooks.after_initialize { called = true }

    assert @hooks.registered?(:after_initialize)
    @hooks.run(:after_initialize)
    assert called
  end

  def test_on_configuration_registration
    called = false
    @hooks.on_configuration { called = true }

    assert @hooks.registered?(:on_configuration)
    @hooks.run(:on_configuration)
    assert called
  end

  def test_before_service_registration
    called = false
    @hooks.before_service { called = true }

    assert @hooks.registered?(:before_service)
    @hooks.run(:before_service)
    assert called
  end

  def test_after_service_registration
    called = false
    @hooks.after_service { called = true }

    assert @hooks.registered?(:after_service)
    @hooks.run(:after_service)
    assert called
  end

  def test_around_service_registration
    called = false
    @hooks.around_service do |_service, block|
      called = true
      block.call
    end

    assert @hooks.registered?(:around_service)
  end

  def test_custom_event_registration
    called = false
    @hooks.on(:custom_event) { called = true }

    assert @hooks.registered?(:custom_event)
    @hooks.run(:custom_event)
    assert called
  end

  # === Handler Tests ===

  def test_handler_object_registration
    handler = Object.new
    def handler.call
      @called = true
    end

    def handler.called?
      @called
    end

    @hooks.after_initialize(handler)
    @hooks.run(:after_initialize)

    assert handler.called?
  end

  def test_handler_receives_arguments
    received_args = nil
    @hooks.before_service { |*args| received_args = args }

    @hooks.run(:before_service, "ServiceClass", { name: "test" })

    assert_equal ["ServiceClass", { name: "test" }], received_args
  end

  # === Priority Tests ===

  def test_hooks_run_in_priority_order
    order = []

    @hooks.after_initialize(priority: 30) { order << 3 }
    @hooks.after_initialize(priority: 10) { order << 1 }
    @hooks.after_initialize(priority: 20) { order << 2 }

    @hooks.run(:after_initialize)

    assert_equal [1, 2, 3], order
  end

  def test_default_priority_is_100
    order = []

    @hooks.after_initialize(priority: 50) { order << "early" }
    @hooks.after_initialize { order << "default" }
    @hooks.after_initialize(priority: 150) { order << "late" }

    @hooks.run(:after_initialize)

    assert_equal %w[early default late], order
  end

  # === Around Hooks Tests ===

  def test_around_hook_wraps_execution
    events = []

    @hooks.around_service do |_service, block|
      events << :before
      result = block.call
      events << :after
      result
    end

    result = @hooks.run_around(:around_service, "service") do
      events << :inside
      "result"
    end

    assert_equal %i[before inside after], events
    assert_equal "result", result
  end

  def test_multiple_around_hooks_nest_correctly
    events = []

    @hooks.around_service(priority: 10) do |_service, block|
      events << :outer_before
      result = block.call
      events << :outer_after
      result
    end

    @hooks.around_service(priority: 20) do |_service, block|
      events << :inner_before
      result = block.call
      events << :inner_after
      result
    end

    @hooks.run_around(:around_service, "service") do
      events << :core
    end

    assert_equal %i[outer_before inner_before core inner_after outer_after], events
  end

  def test_run_around_without_hooks_executes_block
    result = @hooks.run_around(:around_service, "service") do
      "direct result"
    end

    assert_equal "direct result", result
  end

  # === Model/Controller Extensions ===

  def test_extend_model_registration
    @hooks.extend_model(:Example) do
      def custom_method; end
    end

    extensions = @hooks.model_extensions_for(:Example)
    assert_equal 1, extensions.size
    assert extensions.first.is_a?(Proc)
  end

  def test_extend_controller_registration
    @hooks.extend_controller(:HomeController) do
      def custom_action; end
    end

    extensions = @hooks.controller_extensions_for(:HomeController)
    assert_equal 1, extensions.size
    assert extensions.first.is_a?(Proc)
  end

  def test_multiple_extensions_for_same_model
    @hooks.extend_model(:Example) { def method1; end }
    @hooks.extend_model(:Example) { def method2; end }

    extensions = @hooks.model_extensions_for(:Example)
    assert_equal 2, extensions.size
  end

  # === Error Handling Tests ===

  def test_hook_error_does_not_stop_other_hooks_by_default
    results = []

    @hooks.after_initialize(priority: 10) { results << 1 }
    @hooks.after_initialize(priority: 20) { raise "test error" }
    @hooks.after_initialize(priority: 30) { results << 3 }

    @hooks.run(:after_initialize)

    assert_equal [1, 3], results
  end

  def test_raise_on_error_raises_hook_error
    @hooks.raise_on_error = true
    @hooks.after_initialize { raise "test error" }

    assert_raises(GemTemplate::Hooks::HookError) do
      @hooks.run(:after_initialize)
    end
  end

  # === Clear Tests ===

  def test_clear_removes_all_hooks
    @hooks.after_initialize {}
    @hooks.before_service {}
    @hooks.extend_model(:Example) {}

    @hooks.clear!

    refute @hooks.registered?(:after_initialize)
    refute @hooks.registered?(:before_service)
    assert_empty @hooks.model_extensions_for(:Example)
  end

  def test_clear_specific_event
    @hooks.after_initialize {}
    @hooks.before_service {}

    @hooks.clear(:after_initialize)

    refute @hooks.registered?(:after_initialize)
    assert @hooks.registered?(:before_service)
  end

  # === Class Method Tests ===

  def test_class_run_delegates_to_configuration
    GemTemplate.configuration.hooks
    called = false

    GemTemplate.configuration.hooks.after_initialize { called = true }
    GemTemplate::Hooks.run(:after_initialize)

    assert called
  ensure
    GemTemplate.configuration.hooks.clear!
  end

  def test_class_trigger_is_alias_for_run
    called = false
    GemTemplate.configuration.hooks.on(:custom_event) { called = true }

    GemTemplate::Hooks.trigger(:custom_event)

    assert called
  ensure
    GemTemplate.configuration.hooks.clear!
  end
end
