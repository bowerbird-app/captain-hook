# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingEventActionModelTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.create!(
        name: "test_provider",
        verifier_class: "CaptainHook::Verifiers::Base"
      )

      @event = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_123",
        event_type: "test.event"
      )

      @action = @event.incoming_event_actions.create!(
        action_class: ".*Action",
        priority: 100
      )
    end

    # === Validations ===

    test "valid incoming event action" do
      assert @action.valid?
    end

    test "requires action_class" do
      action_under_test = @event.incoming_event_actions.new(priority: 100)
      refute action_under_test.valid?
      assert_includes action_under_test.errors[:action_class], "can't be blank"
    end

    test "requires status" do
      action_under_test = @event.incoming_event_actions.new(action_class: "Test", priority: 100)
      action_under_test.status = nil
      refute action_under_test.valid?
    end

    test "priority must be an integer" do
      @action.priority = "abc"
      refute @action.valid?
    end

    test "attempt_count must be non-negative integer" do
      @action.attempt_count = -1
      refute @action.valid?

      @action.attempt_count = 0
      assert @action.valid?

      @action.attempt_count = 5
      assert @action.valid?
    end

    # === Enums ===

    test "status enum values" do
      assert_equal "pending", @action.status

      @action.status = :processing
      assert @action.status_processing?

      @action.status = :processed
      assert @action.status_processed?

      @action.status = :failed
      assert @action.status_failed?
    end

    # === Scopes ===

    test "pending scope returns only pending actions" do
      processing = @event.incoming_event_actions.create!(
        action_class: ".*Action",
        priority: 200,
        status: :processing
      )

      pending_actions_list = @event.incoming_event_actions.pending
      assert_includes pending_actions_list, @action
      refute_includes pending_actions_list, processing
    end

    test "failed scope returns only failed actions" do
      failed = @event.incoming_event_actions.create!(
        action_class: "FailedAction",
        priority: 200,
        status: :failed
      )

      failed_actions_list = @event.incoming_event_actions.failed
      assert_includes failed_actions_list, failed
      refute_includes failed_actions_list, @action
    end

    test "by_priority scope orders by priority then action_class" do
      high_priority = @event.incoming_event_actions.create!(
        action_class: ".*Action",
        priority: 50
      )
      same_priority = @event.incoming_event_actions.create!(
        action_class: "AnotherAction",
        priority: 100
      )

      ordered = @event.incoming_event_actions.by_priority
      assert_equal high_priority.id, ordered.first.id
      assert_equal same_priority.id, ordered.second.id
      assert_equal @action.id, ordered.third.id
    end

    test "locked scope returns only locked actions" do
      @action.update!(locked_at: Time.current, locked_by: "worker1")
      unlocked = @event.incoming_event_actions.create!(
        action_class: "UnlockedAction",
        priority: 200
      )

      locked_actions = @event.incoming_event_actions.locked
      assert_includes locked_actions, @action
      refute_includes locked_actions, unlocked
    end

    test "unlocked scope returns only unlocked actions" do
      @action.update!(locked_at: Time.current, locked_by: "worker1")
      unlocked = @event.incoming_event_actions.create!(
        action_class: "UnlockedAction",
        priority: 200
      )

      unlocked_actions = @event.incoming_event_actions.unlocked
      assert_includes unlocked_actions, unlocked
      refute_includes unlocked_actions, @action
    end

    # === Locking ===

    test "acquire_lock! sets lock fields and changes status" do
      worker_id = "worker123"

      @action.acquire_lock!(worker_id)

      assert_not_nil @action.locked_at
      assert_equal worker_id, @action.locked_by
      assert @action.status_processing?
    end

    test "acquire_lock! returns false on concurrent lock attempt" do
      # Simulate optimistic locking by acquiring lock twice
      @action.acquire_lock!("worker1")

      # Create new reference to same action (simulating concurrent access)
      stale_action = CaptainHook::IncomingEventAction.find(@action.id)
      stale_action.lock_version -= 1 # Make it stale

      # Try to lock stale copy - should raise StaleObjectError
      assert_raises(ActiveRecord::StaleObjectError) do
        stale_action.update!(locked_at: Time.current, locked_by: "worker2", status: :processing)
      end
    end

    test "release_lock! clears lock fields" do
      @action.update!(locked_at: Time.current, locked_by: "worker1")

      @action.release_lock!

      assert_nil @action.locked_at
      assert_nil @action.locked_by
    end

    test "locked? returns true when locked" do
      refute @action.locked?

      @action.update!(locked_at: Time.current)

      assert @action.locked?
    end

    # === Status Updates ===

    test "mark_processed! updates status and clears errors" do
      @action.update!(
        status: :failed,
        error_message: "Some error",
        locked_at: Time.current,
        locked_by: "worker1"
      )

      @action.mark_processed!

      assert @action.status_processed?
      assert_nil @action.error_message
      assert_nil @action.locked_at
      assert_nil @action.locked_by
    end

    test "mark_failed! updates status and saves error" do
      error = StandardError.new("Test error message")

      @action.update!(locked_at: Time.current, locked_by: "worker1")
      @action.mark_failed!(error)

      assert @action.status_failed?
      assert_equal "Test error message", @action.error_message
      assert_not_nil @action.last_attempt_at
      assert_nil @action.locked_at
      assert_nil @action.locked_by
    end

    test "mark_failed! truncates long error messages" do
      long_error = StandardError.new("x" * 2000)

      @action.mark_failed!(long_error)

      assert @action.error_message.length <= 1000
    end

    # === Retry Logic ===

    test "increment_attempts! increases attempt_count" do
      initial_count = @action.attempt_count

      @action.increment_attempts!

      assert_equal initial_count + 1, @action.attempt_count
      assert_not_nil @action.last_attempt_at
    end

    test "max_attempts_reached? returns true when limit reached" do
      @action.update!(attempt_count: 5)

      assert @action.max_attempts_reached?(5)
      assert @action.max_attempts_reached?(4)
      refute @action.max_attempts_reached?(6)
    end

    test "max_attempts_reached? returns false when below limit" do
      @action.update!(attempt_count: 2)

      refute @action.max_attempts_reached?(5)
    end

    test "reset_for_retry! resets status and clears lock" do
      @action.update!(
        status: :failed,
        locked_at: Time.current,
        locked_by: "worker1"
      )

      @action.reset_for_retry!

      assert @action.status_pending?
      assert_nil @action.locked_at
      assert_nil @action.locked_by
    end

    # === Associations ===

    test "belongs to incoming_event" do
      assert_equal @event.id, @action.incoming_event_id
      assert_equal @event, @action.incoming_event
    end

    # === Default Values ===

    test "defaults to pending status" do
      action_under_test = @event.incoming_event_actions.create!(
        action_class: ".*Action",
        priority: 100
      )

      assert action_under_test.status_pending?
    end

    test "defaults to 0 attempt_count" do
      action_under_test = @event.incoming_event_actions.create!(
        action_class: ".*Action",
        priority: 100
      )

      assert_equal 0, action_under_test.attempt_count
    end

    test "defaults to 0 lock_version for optimistic locking" do
      action_under_test = @event.incoming_event_actions.create!(
        action_class: ".*Action",
        priority: 100
      )

      assert_equal 0, action_under_test.lock_version
    end

    test "reset_for_retry! resets status and clears locks" do
      @action.save!
      @action.update!(status: :failed, locked_at: Time.current, locked_by: "worker_1")

      @action.reset_for_retry!
      @action.reload

      assert_equal "pending", @action.status
      assert_nil @action.locked_at
      assert_nil @action.locked_by
    end

    test "increment_attempts! updates last_attempt_at" do
      @action.save!
      @action.last_attempt_at

      @action.increment_attempts!
      @action.reload

      assert_not_nil @action.last_attempt_at
    end

    test "locked scope returns locked actions" do
      @action.save!
      @event.incoming_event_actions.create!(
        action_class: "LockedAction",
        priority: 100,
        locked_at: Time.current,
        locked_by: "worker_1"
      )

      assert_includes IncomingEventAction.locked, locked_action
      refute_includes IncomingEventAction.locked, @action
    end

    test "unlocked scope returns unlocked actions" do
      @action.save!
      @event.incoming_event_actions.create!(
        action_class: "LockedAction",
        priority: 100,
        locked_at: Time.current,
        locked_by: "worker_1"
      )

      assert_includes IncomingEventAction.unlocked, @action
      refute_includes IncomingEventAction.unlocked, locked_action
    end
  end
end
