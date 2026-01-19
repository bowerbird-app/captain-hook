# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class ActionDiscoveryTest < ActiveSupport::TestCase
      setup do
        @discovery = ActionDiscovery.new
        # Clear the registry before each test
        CaptainHook.action_registry.clear!
      end

      test "discovers actions from registry" do
        # Register a test action
        CaptainHook.register_action(
          provider: "stripe",
          event_type: "payment.succeeded",
          action_class: "TestAction",
          priority: 100,
          async: true,
          max_attempts: 5,
          retry_delays: [30, 60, 300]
        )

        actions = @discovery.call

        assert_equal 1, actions.size
        action = actions.first
        assert_equal "stripe", action["provider"]
        assert_equal "payment.succeeded", action["event_type"]
        assert_equal "TestAction", action["action_class"]
        assert_equal 100, action["priority"]
        assert_equal true, action["async"]
        assert_equal 5, action["max_attempts"]
        assert_equal [30, 60, 300], action["retry_delays"]
      end

      test "discovers multiple actions for same provider" do
        CaptainHook.register_action(
          provider: "stripe",
          event_type: "payment.succeeded",
          action_class: "PaymentAction"
        )

        CaptainHook.register_action(
          provider: "stripe",
          event_type: "payment.failed",
          action_class: "FailureAction"
        )

        actions = @discovery.call

        assert_equal 2, actions.size
        provider_names = actions.map { |h| h["provider"] }
        assert(provider_names.all? { |p| p == "stripe" })
      end

      test "discovers actions for specific provider" do
        CaptainHook.register_action(
          provider: "stripe",
          event_type: "payment.succeeded",
          action_class: "StripeAction"
        )

        CaptainHook.register_action(
          provider: "square",
          event_type: "payment.succeeded",
          action_class: "SquareAction"
        )

        stripe_actions = ActionDiscovery.for_provider("stripe")
        square_actions = ActionDiscovery.for_provider("square")

        assert_equal 1, stripe_actions.size
        assert_equal 1, square_actions.size
        assert_equal "StripeAction", stripe_actions.first["action_class"]
        assert_equal "SquareAction", square_actions.first["action_class"]
      end

      test "returns empty array when no actions registered" do
        actions = @discovery.call
        assert_equal [], actions
      end

      test "for_provider returns empty array for unknown provider" do
        CaptainHook.register_action(
          provider: "stripe",
          event_type: "payment.succeeded",
          action_class: "TestAction"
        )

        actions = ActionDiscovery.for_provider("unknown_provider")
        assert_equal [], actions
      end

      test "handles multiple actions for same event type" do
        CaptainHook.register_action(
          provider: "stripe",
          event_type: "payment.succeeded",
          action_class: "Action1",
          priority: 100
        )

        CaptainHook.register_action(
          provider: "stripe",
          event_type: "payment.succeeded",
          action_class: "Action2",
          priority: 200
        )

        actions = @discovery.call
        stripe_payment_actions = actions.select do |h|
          h["provider"] == "stripe" && h["event_type"] == "payment.succeeded"
        end

        assert_equal 2, stripe_payment_actions.size
      end

      test "handler class is converted to string" do
        CaptainHook.register_action(
          provider: "test",
          event_type: "test.event",
          action_class: Object # Using a class object
        )

        actions = @discovery.call
        assert_equal "Object", actions.first["action_class"]
        assert actions.first["action_class"].is_a?(String)
      end

      test "discovered actions include all required fields" do
        CaptainHook.register_action(
          provider: "test",
          event_type: "test.event",
          action_class: "TestAction"
        )

        action = @discovery.call.first

        assert action.key?("provider")
        assert action.key?("event_type")
        assert action.key?("action_class")
        assert action.key?("async")
        assert action.key?("max_attempts")
        assert action.key?("priority")
        assert action.key?("retry_delays")
      end
    end
  end
end
