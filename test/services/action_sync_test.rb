# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class ActionSyncTest < ActiveSupport::TestCase
      setup do
        @action_definitions = [
          {
            "provider" => "stripe",
            "event_type" => "payment.succeeded",
            "action_class" => "PaymentAction",
            "async" => true,
            "max_attempts" => 5,
            "priority" => 100,
            "retry_delays" => [30, 60, 300]
          }
        ]
      end

      teardown do
        CaptainHook::Action.destroy_all
      end

      test "creates new action from definition" do
        sync = ActionSync.new(@action_definitions)
        results = sync.call

        assert_equal 1, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 0, results[:errors].size

        action = results[:created].first
        assert_equal "stripe", action.provider
        assert_equal "payment.succeeded", action.event_type
        assert_equal "PaymentAction", action.action_class
        assert_equal true, action.async
        assert_equal 5, action.max_attempts
        assert_equal 100, action.priority
        assert_equal [30, 60, 300], action.retry_delays
      end

      test "updates existing action" do
        # Create initial action
        action = CaptainHook::Action.create!(
          provider: "stripe",
          event_type: "payment.succeeded",
          action_class: "PaymentAction",
          async: false,
          max_attempts: 3,
          priority: 200,
          retry_delays: [60, 120]
        )

        sync = ActionSync.new(@action_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 1, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 0, results[:errors].size

        action.reload
        assert_equal true, action.async
        assert_equal 5, action.max_attempts
        assert_equal 100, action.priority
        assert_equal [30, 60, 300], action.retry_delays
      end

      test "skips deleted actions" do
        # Create and soft-delete an action
        action = CaptainHook::Action.create!(
          provider: "stripe",
          event_type: "payment.succeeded",
          action_class: "PaymentAction",
          async: true,
          max_attempts: 5,
          priority: 100,
          retry_delays: [30, 60]
        )
        action.soft_delete!

        sync = ActionSync.new(@action_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 1, results[:skipped].size
        assert_equal 0, results[:errors].size

        # Verify action is still deleted
        action.reload
        assert action.deleted?
      end

      test "handles multiple actions" do
        definitions = [
          {
            "provider" => "stripe",
            "event_type" => "payment.succeeded",
            "action_class" => "PaymentAction",
            "async" => true,
            "max_attempts" => 5,
            "priority" => 100,
            "retry_delays" => [30, 60]
          },
          {
            "provider" => "stripe",
            "event_type" => "payment.failed",
            ".*Action",
            "async" => true,
            "max_attempts" => 3,
            "priority" => 50,
            "retry_delays" => [60, 120]
          }
        ]

        sync = ActionSync.new(definitions)
        results = sync.call

        assert_equal 2, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 0, results[:errors].size
      end

      test "handles invalid action definition" do
        invalid_definitions = [
          {
            "provider" => "stripe",
            "event_type" => "payment.succeeded"
            # Missing action_class
          }
        ]

        sync = ActionSync.new(invalid_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 1, results[:errors].size
      end

      test "handles validation errors" do
        invalid_definitions = [
          {
            "provider" => "stripe",
            "event_type" => "payment.succeeded",
            "action_class" => "PaymentAction",
            "async" => true,
            "max_attempts" => 0, # Invalid - must be > 0
            "priority" => 100,
            "retry_delays" => [30]
          }
        ]

        sync = ActionSync.new(invalid_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 1, results[:errors].size
      end
    end
  end
end
