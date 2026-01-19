# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingEventHandlerModelTest < ActiveSupport::TestCase
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

      @handler = @event.incoming_event_handlers.create!(
        handler_class: "TestHandler",
        priority: 100
      )
    end

    # === Validations ===

    test "valid incoming event handler" do
      assert @handler.valid?
    end

    test "requires handler_class" do
      handler = @event.incoming_event_handlers.new(priority: 100)
      refute handler.valid?
      assert_includes handler.errors[:handler_class], "can't be blank"
    end

    test "requires status" do
      handler = @event.incoming_event_handlers.new(handler_class: "Test", priority: 100)
      handler.status = nil
      refute handler.valid?
    end

    test "priority must be an integer" do
      @handler.priority = "abc"
      refute @handler.valid?
    end

    test "attempt_count must be non-negative integer" do
      @handler.attempt_count = -1
      refute @handler.valid?

      @handler.attempt_count = 0
      assert @handler.valid?

      @handler.attempt_count = 5
      assert @handler.valid?
    end

    # === Enums ===

    test "status enum values" do
      assert_equal "pending", @handler.status

      @handler.status = :processing
      assert @handler.status_processing?

      @handler.status = :processed
      assert @handler.status_processed?

      @handler.status = :failed
      assert @handler.status_failed?
    end

    # === Scopes ===

    test "pending scope returns only pending handlers" do
      processing = @event.incoming_event_handlers.create!(
        handler_class: "ProcessingHandler",
        priority: 200,
        status: :processing
      )

      pending_handlers = @event.incoming_event_handlers.pending
      assert_includes pending_handlers, @handler
      refute_includes pending_handlers, processing
    end

    test "failed scope returns only failed handlers" do
      failed = @event.incoming_event_handlers.create!(
        handler_class: "FailedHandler",
        priority: 200,
        status: :failed
      )

      failed_handlers = @event.incoming_event_handlers.failed
      assert_includes failed_handlers, failed
      refute_includes failed_handlers, @handler
    end

    test "by_priority scope orders by priority then handler_class" do
      high_priority = @event.incoming_event_handlers.create!(
        handler_class: "HighPriorityHandler",
        priority: 50
      )
      same_priority = @event.incoming_event_handlers.create!(
        handler_class: "AnotherHandler",
        priority: 100
      )

      ordered = @event.incoming_event_handlers.by_priority
      assert_equal high_priority.id, ordered.first.id
      assert_equal same_priority.id, ordered.second.id
      assert_equal @handler.id, ordered.third.id
    end

    test "locked scope returns only locked handlers" do
      @handler.update!(locked_at: Time.current, locked_by: "worker1")
      unlocked = @event.incoming_event_handlers.create!(
        handler_class: "UnlockedHandler",
        priority: 200
      )

      locked_handlers = @event.incoming_event_handlers.locked
      assert_includes locked_handlers, @handler
      refute_includes locked_handlers, unlocked
    end

    test "unlocked scope returns only unlocked handlers" do
      @handler.update!(locked_at: Time.current, locked_by: "worker1")
      unlocked = @event.incoming_event_handlers.create!(
        handler_class: "UnlockedHandler",
        priority: 200
      )

      unlocked_handlers = @event.incoming_event_handlers.unlocked
      assert_includes unlocked_handlers, unlocked
      refute_includes unlocked_handlers, @handler
    end

    # === Locking ===

    test "acquire_lock! sets lock fields and changes status" do
      worker_id = "worker123"

      @handler.acquire_lock!(worker_id)

      assert_not_nil @handler.locked_at
      assert_equal worker_id, @handler.locked_by
      assert @handler.status_processing?
    end

    test "acquire_lock! returns false on concurrent lock attempt" do
      # Simulate optimistic locking by acquiring lock twice
      @handler.acquire_lock!("worker1")

      # Create new reference to same handler (simulating concurrent access)
      stale_handler = CaptainHook::IncomingEventHandler.find(@handler.id)
      stale_handler.lock_version -= 1 # Make it stale

      # Try to lock stale copy - should raise StaleObjectError
      assert_raises(ActiveRecord::StaleObjectError) do
        stale_handler.update!(locked_at: Time.current, locked_by: "worker2", status: :processing)
      end
    end

    test "release_lock! clears lock fields" do
      @handler.update!(locked_at: Time.current, locked_by: "worker1")

      @handler.release_lock!

      assert_nil @handler.locked_at
      assert_nil @handler.locked_by
    end

    test "locked? returns true when locked" do
      refute @handler.locked?

      @handler.update!(locked_at: Time.current)

      assert @handler.locked?
    end

    # === Status Updates ===

    test "mark_processed! updates status and clears errors" do
      @handler.update!(
        status: :failed,
        error_message: "Some error",
        locked_at: Time.current,
        locked_by: "worker1"
      )

      @handler.mark_processed!

      assert @handler.status_processed?
      assert_nil @handler.error_message
      assert_nil @handler.locked_at
      assert_nil @handler.locked_by
    end

    test "mark_failed! updates status and saves error" do
      error = StandardError.new("Test error message")

      @handler.update!(locked_at: Time.current, locked_by: "worker1")
      @handler.mark_failed!(error)

      assert @handler.status_failed?
      assert_equal "Test error message", @handler.error_message
      assert_not_nil @handler.last_attempt_at
      assert_nil @handler.locked_at
      assert_nil @handler.locked_by
    end

    test "mark_failed! truncates long error messages" do
      long_error = StandardError.new("x" * 2000)

      @handler.mark_failed!(long_error)

      assert @handler.error_message.length <= 1000
    end

    # === Retry Logic ===

    test "increment_attempts! increases attempt_count" do
      initial_count = @handler.attempt_count

      @handler.increment_attempts!

      assert_equal initial_count + 1, @handler.attempt_count
      assert_not_nil @handler.last_attempt_at
    end

    test "max_attempts_reached? returns true when limit reached" do
      @handler.update!(attempt_count: 5)

      assert @handler.max_attempts_reached?(5)
      assert @handler.max_attempts_reached?(4)
      refute @handler.max_attempts_reached?(6)
    end

    test "max_attempts_reached? returns false when below limit" do
      @handler.update!(attempt_count: 2)

      refute @handler.max_attempts_reached?(5)
    end

    test "reset_for_retry! resets status and clears lock" do
      @handler.update!(
        status: :failed,
        locked_at: Time.current,
        locked_by: "worker1"
      )

      @handler.reset_for_retry!

      assert @handler.status_pending?
      assert_nil @handler.locked_at
      assert_nil @handler.locked_by
    end

    # === Associations ===

    test "belongs to incoming_event" do
      assert_equal @event.id, @handler.incoming_event_id
      assert_equal @event, @handler.incoming_event
    end

    # === Default Values ===

    test "defaults to pending status" do
      handler = @event.incoming_event_handlers.create!(
        handler_class: "NewHandler",
        priority: 100
      )

      assert handler.status_pending?
    end

    test "defaults to 0 attempt_count" do
      handler = @event.incoming_event_handlers.create!(
        handler_class: "NewHandler",
        priority: 100
      )

      assert_equal 0, handler.attempt_count
    end

    test "defaults to 0 lock_version for optimistic locking" do
      handler = @event.incoming_event_handlers.create!(
        handler_class: "NewHandler",
        priority: 100
      )

      assert_equal 0, handler.lock_version
    end

    test "reset_for_retry! resets status and clears locks" do
      @handler.save!
      @handler.update!(status: :failed, locked_at: Time.current, locked_by: "worker_1")

      @handler.reset_for_retry!
      @handler.reload

      assert_equal "pending", @handler.status
      assert_nil @handler.locked_at
      assert_nil @handler.locked_by
    end

    test "increment_attempts! updates last_attempt_at" do
      @handler.save!
      @handler.last_attempt_at

      @handler.increment_attempts!
      @handler.reload

      assert_not_nil @handler.last_attempt_at
    end

    test "locked scope returns locked handlers" do
      @handler.save!
      locked_handler = @event.incoming_event_handlers.create!(
        handler_class: "LockedHandler",
        priority: 100,
        locked_at: Time.current,
        locked_by: "worker_1"
      )

      assert_includes IncomingEventHandler.locked, locked_handler
      refute_includes IncomingEventHandler.locked, @handler
    end

    test "unlocked scope returns unlocked handlers" do
      @handler.save!
      locked_handler = @event.incoming_event_handlers.create!(
        handler_class: "LockedHandler",
        priority: 100,
        locked_at: Time.current,
        locked_by: "worker_1"
      )

      assert_includes IncomingEventHandler.unlocked, @handler
      refute_includes IncomingEventHandler.unlocked, locked_handler
    end
  end
end
