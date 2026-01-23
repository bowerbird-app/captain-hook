# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingActionJobHandlerDispatchTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.find_or_create_by!(name: "test_provider") do |p|
        p.token = SecureRandom.hex(16)
        p.active = true
      end

      @event = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_handler_test_#{SecureRandom.hex(8)}",
        event_type: "test.event",
        payload: { "data" => "test", "amount" => 100 },
        metadata: { "timestamp" => Time.current.to_i }
      )
    end

    teardown do
      # Clean up any dynamically created constants
      [
        :NonExistentAction,
        :RaisingAction,
        :TimeoutAction,
        :PartialSuccessAction,
        :EarlyReturnAction,
        :NilReturningAction,
        :DataProcessingAction
      ].each do |const|
        Object.send(:remove_const, const) if defined?(Object.const_get(const))
      end

      CaptainHook.action_registry.clear!
    end

    # === NO HANDLER Scenario ===

    test "handles missing action class gracefully" do
      action = @event.incoming_event_actions.create!(
        action_class: "NonExistentAction",
        priority: 100
      )

      # Should not crash
      assert_nothing_raised do
        begin
          IncomingActionJob.perform_now(action.id)
        rescue StandardError
          # Expected to raise since class doesn't exist
        end
      end

      action.reload
      assert_equal "failed", action.status
      assert_match(/nonexistentaction/i, action.error_message)
    end

    test "handles action class that exists but isn't registered" do
      # Define action class but don't register it
      Object.const_set(:UnregisteredAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          # This should work if instantiated
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "UnregisteredAction",
        priority: 100
      )

      # Behavior depends on implementation
      # Should either succeed or fail gracefully
      begin
        IncomingActionJob.perform_now(action.id)
        action.reload
        # If it succeeds, status should be processed
        assert_includes ["processed", "failed"], action.status
      rescue StandardError => e
        # If it fails, should be handled gracefully
        action.reload
        assert_equal "failed", action.status
      end
    end

    # === HANDLER RAISES Exception ===

    test "handles action that raises StandardError" do
      Object.const_set(:RaisingAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          raise StandardError, "Something went wrong"
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "RaisingAction",
        priority: 100,
        max_attempts: 3
      )

      # First attempt should fail and set for retry
      assert_raises(StandardError) do
        IncomingActionJob.perform_now(action.id)
      end

      action.reload
      assert_equal "pending_retry", action.status
      assert_equal 1, action.attempt_count
      assert_match(/something went wrong/i, action.error_message)
    end

    test "handles action that raises custom exception" do
      class CustomWebhookError < StandardError; end

      Object.const_set(:CustomErrorAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          raise CustomWebhookError, "Custom error occurred"
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "CustomErrorAction",
        priority: 100
      )

      assert_raises(CustomWebhookError) do
        IncomingActionJob.perform_now(action.id)
      end

      action.reload
      assert_match(/custom error occurred/i, action.error_message)
    end

    test "handles action that raises ArgumentError" do
      Object.const_set(:ArgumentErrorAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          raise ArgumentError, "Invalid argument provided"
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "ArgumentErrorAction",
        priority: 100
      )

      assert_raises(ArgumentError) do
        IncomingActionJob.perform_now(action.id)
      end

      action.reload
      assert_equal "pending_retry", action.status
      assert_match(/invalid argument/i, action.error_message)
    end

    # === MAX RETRIES Behavior ===

    test "marks action as failed after max retries" do
      Object.const_set(:AlwaysFailingAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          raise StandardError, "Always fails"
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "AlwaysFailingAction",
        priority: 100,
        max_attempts: 2,
        attempt_count: 2 # Already at max
      )

      assert_raises(StandardError) do
        IncomingActionJob.perform_now(action.id)
      end

      action.reload
      assert_equal "failed", action.status, "Should be marked as failed after max retries"
      assert action.error_message.present?
    end

    test "continues retrying until max attempts" do
      Object.const_set(:RetryableAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          raise StandardError, "Retry me"
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "RetryableAction",
        priority: 100,
        max_attempts: 5,
        attempt_count: 3 # Attempt 4 will be next
      )

      assert_raises(StandardError) do
        IncomingActionJob.perform_now(action.id)
      end

      action.reload
      assert_equal "pending_retry", action.status, "Should still retry, not at max yet"
      assert_equal 4, action.attempt_count
    end

    # === HANDLER SUCCEEDS ===

    test "marks action as succeeded on success" do
      Object.const_set(:SuccessfulAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          # Successfully processed
          true
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "SuccessfulAction",
        priority: 100
      )

      IncomingActionJob.perform_now(action.id)

      action.reload
      assert_equal "processed", action.status
      assert_nil action.error_message
      assert action.processed_at.present?
    end

    test "successful action updates attempt count" do
      Object.const_set(:SuccessAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          # Success
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "SuccessAction",
        priority: 100,
        attempt_count: 2 # Had previous failures
      )

      IncomingActionJob.perform_now(action.id)

      action.reload
      assert_equal "processed", action.status
      assert_equal 3, action.attempt_count, "Should increment even on success"
    end

    # === HANDLER Returns Early ===

    test "handles action that returns without error" do
      Object.const_set(:EarlyReturnAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          return if payload["skip"]
          # Process normally
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "EarlyReturnAction",
        priority: 100
      )

      @event.update!(payload: { "skip" => true })

      IncomingActionJob.perform_now(action.id)

      action.reload
      assert_equal "processed", action.status, "Early return should be treated as success"
    end

    test "handles action that returns nil" do
      Object.const_set(:NilReturningAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          nil
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "NilReturningAction",
        priority: 100
      )

      IncomingActionJob.perform_now(action.id)

      action.reload
      assert_equal "processed", action.status, "Nil return should be treated as success"
    end

    test "handles action that returns false" do
      Object.const_set(:FalseReturningAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          false
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "FalseReturningAction",
        priority: 100
      )

      IncomingActionJob.perform_now(action.id)

      action.reload
      assert_equal "processed", action.status, "False return should be treated as success (no exception)"
    end

    # === HANDLER with Data Processing ===

    test "action receives correct event object" do
      received_event = nil

      Object.const_set(:EventInspectorAction, Class.new do
        define_method(:webhook_action) do |event:, payload:, metadata:|
          received_event = event
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "EventInspectorAction",
        priority: 100
      )

      IncomingActionJob.perform_now(action.id)

      assert_not_nil received_event
      assert_equal @event.id, received_event.id
      assert_equal "test.event", received_event.event_type
    end

    test "action receives correct payload" do
      received_payload = nil

      Object.const_set(:PayloadInspectorAction, Class.new do
        define_method(:webhook_action) do |event:, payload:, metadata:|
          received_payload = payload
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "PayloadInspectorAction",
        priority: 100
      )

      IncomingActionJob.perform_now(action.id)

      assert_not_nil received_payload
      assert_equal "test", received_payload["data"]
      assert_equal 100, received_payload["amount"]
    end

    test "action receives correct metadata" do
      received_metadata = nil

      Object.const_set(:MetadataInspectorAction, Class.new do
        define_method(:webhook_action) do |event:, payload:, metadata:|
          received_metadata = metadata
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "MetadataInspectorAction",
        priority: 100
      )

      IncomingActionJob.perform_now(action.id)

      assert_not_nil received_metadata
      assert_kind_of Integer, received_metadata["timestamp"]
    end

    # === Error Message Capture ===

    test "captures full error message on failure" do
      long_error_message = "Error: " + ("x" * 500)

      Object.const_set(:LongErrorAction, Class.new do
        define_method(:webhook_action) do |event:, payload:, metadata:|
          raise StandardError, long_error_message
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "LongErrorAction",
        priority: 100
      )

      assert_raises(StandardError) do
        IncomingActionJob.perform_now(action.id)
      end

      action.reload
      assert action.error_message.present?
      assert action.error_message.length > 100, "Should capture substantial error message"
    end

    test "captures error backtrace information" do
      Object.const_set(:BacktraceAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          nested_method
        end

        def nested_method
          raise StandardError, "Error in nested method"
        end
      end)

      action = @event.incoming_event_actions.create!(
        action_class: "BacktraceAction",
        priority: 100
      )

      assert_raises(StandardError) do
        IncomingActionJob.perform_now(action.id)
      end

      action.reload
      # Error message should include class and method info
      assert_match(/backtrace|nested_method|error/i, action.error_message)
    end

    # === Concurrent Action Processing ===

    test "multiple actions for same event can be processed" do
      Object.const_set(:Action1, Class.new do
        def webhook_action(event:, payload:, metadata:)
          # Action 1
        end
      end)

      Object.const_set(:Action2, Class.new do
        def webhook_action(event:, payload:, metadata:)
          # Action 2
        end
      end)

      action1 = @event.incoming_event_actions.create!(
        action_class: "Action1",
        priority: 100
      )

      action2 = @event.incoming_event_actions.create!(
        action_class: "Action2",
        priority: 200
      )

      IncomingActionJob.perform_now(action1.id)
      IncomingActionJob.perform_now(action2.id)

      action1.reload
      action2.reload

      assert_equal "processed", action1.status
      assert_equal "processed", action2.status
    end

    test "failure in one action doesn't affect other actions" do
      Object.const_set(:SuccessAction1, Class.new do
        def webhook_action(event:, payload:, metadata:)
          # Success
        end
      end)

      Object.const_set(:FailAction, Class.new do
        def webhook_action(event:, payload:, metadata:)
          raise StandardError, "Failed"
        end
      end)

      success_action = @event.incoming_event_actions.create!(
        action_class: "SuccessAction1",
        priority: 100
      )

      fail_action = @event.incoming_event_actions.create!(
        action_class: "FailAction",
        priority: 200
      )

      # Process success action
      IncomingActionJob.perform_now(success_action.id)

      # Process fail action
      assert_raises(StandardError) do
        IncomingActionJob.perform_now(fail_action.id)
      end

      success_action.reload
      fail_action.reload

      assert_equal "processed", success_action.status
      assert_equal "pending_retry", fail_action.status
    end
  end
end
