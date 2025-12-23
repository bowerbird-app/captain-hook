# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingEventModelTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.create!(
        name: "test_provider",
        adapter_class: "CaptainHook::Adapters::Base"
      )

      @event = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_123",
        event_type: "test.event",
        payload: { data: "test" },
        headers: { "Content-Type" => "application/json" }
      )
    end

    # === Validations ===

    test "valid incoming event" do
      assert @event.valid?
    end

    test "requires provider" do
      event = CaptainHook::IncomingEvent.new(external_id: "evt", event_type: "test")
      refute event.valid?
      assert_includes event.errors[:provider], "can't be blank"
    end

    test "requires external_id" do
      event = CaptainHook::IncomingEvent.new(provider: "test", event_type: "test")
      refute event.valid?
      assert_includes event.errors[:external_id], "can't be blank"
    end

    test "requires event_type" do
      event = CaptainHook::IncomingEvent.new(provider: "test", external_id: "evt")
      refute event.valid?
      assert_includes event.errors[:event_type], "can't be blank"
    end

    test "requires status" do
      event = CaptainHook::IncomingEvent.new(provider: "test", external_id: "evt", event_type: "test")
      event.status = nil
      refute event.valid?
    end

    test "requires dedup_state" do
      event = CaptainHook::IncomingEvent.new(provider: "test", external_id: "evt", event_type: "test")
      event.dedup_state = nil
      refute event.valid?
    end

    # === Enums ===

    test "status enum values" do
      assert_equal "received", @event.status

      @event.status = :processing
      assert @event.status_processing?

      @event.status = :processed
      assert @event.status_processed?

      @event.status = :partially_processed
      assert @event.status_partially_processed?

      @event.status = :failed
      assert @event.status_failed?
    end

    test "dedup_state enum values" do
      assert_equal "unique", @event.dedup_state

      @event.dedup_state = :duplicate
      assert @event.dedup_state_duplicate?

      @event.dedup_state = :replayed
      assert @event.dedup_state_replayed?
    end

    # === Scopes ===

    test "by_provider scope filters by provider" do
      other_event = CaptainHook::IncomingEvent.create!(
        provider: "other_provider",
        external_id: "evt_456",
        event_type: "test.event"
      )

      events = CaptainHook::IncomingEvent.by_provider(@provider.name)
      assert_includes events, @event
      refute_includes events, other_event
    end

    test "by_event_type scope filters by event type" do
      other_event = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_456",
        event_type: "other.event"
      )

      events = CaptainHook::IncomingEvent.by_event_type("test.event")
      assert_includes events, @event
      refute_includes events, other_event
    end

    test "archived scope returns only archived events" do
      @event.archive!
      not_archived = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_456",
        event_type: "test.event"
      )

      archived_events = CaptainHook::IncomingEvent.archived
      assert_includes archived_events, @event
      refute_includes archived_events, not_archived
    end

    test "not_archived scope returns only non-archived events" do
      @event.archive!
      not_archived = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_456",
        event_type: "test.event"
      )

      active_events = CaptainHook::IncomingEvent.not_archived
      assert_includes active_events, not_archived
      refute_includes active_events, @event
    end

    test "recent scope orders by created_at desc" do
      old_event = nil
      travel_to 1.hour.ago do
        old_event = CaptainHook::IncomingEvent.create!(
          provider: @provider.name,
          external_id: "evt_old",
          event_type: "test.event"
        )
      end

      recent = CaptainHook::IncomingEvent.recent
      assert_equal @event.id, recent.first.id
      assert_equal old_event.id, recent.last.id
    end

    # === Class Methods ===

    test "find_or_create_by_external! creates new event" do
      assert_difference "CaptainHook::IncomingEvent.count", 1 do
        event = CaptainHook::IncomingEvent.find_or_create_by_external!(
          provider: @provider.name,
          external_id: "new_evt",
          event_type: "new.event",
          payload: {}
        )
        assert_equal "new_evt", event.external_id
      end
    end

    test "find_or_create_by_external! finds existing event" do
      assert_no_difference "CaptainHook::IncomingEvent.count" do
        event = CaptainHook::IncomingEvent.find_or_create_by_external!(
          provider: @provider.name,
          external_id: @event.external_id,
          event_type: "different.event"
        )
        assert_equal @event.id, event.id
        # Should not update existing event
        assert_equal "test.event", event.event_type
      end
    end

    # === Instance Methods ===

    test "mark_duplicate! changes dedup_state" do
      @event.mark_duplicate!
      assert @event.dedup_state_duplicate?
    end

    test "mark_replayed! changes dedup_state" do
      @event.mark_replayed!
      assert @event.dedup_state_replayed?
    end

    test "archive! sets archived_at" do
      assert_nil @event.archived_at
      @event.archive!
      assert_not_nil @event.archived_at
    end

    test "archived? returns true when archived" do
      refute @event.archived?
      @event.archive!
      assert @event.archived?
    end

    test "start_processing! changes status to processing" do
      @event.start_processing!
      assert @event.status_processing?
    end

    test "mark_processed! changes status to processed" do
      @event.mark_processed!
      assert @event.status_processed?
    end

    test "mark_partially_processed! changes status to partially_processed" do
      @event.mark_partially_processed!
      assert @event.status_partially_processed?
    end

    test "mark_failed! changes status to failed" do
      @event.mark_failed!
      assert @event.status_failed?
    end

    test "recalculate_status! marks as processed when all handlers processed" do
      handler1 = @event.incoming_event_handlers.create!(handler_class: "Handler1", status: :processed)
      handler2 = @event.incoming_event_handlers.create!(handler_class: "Handler2", status: :processed)

      @event.recalculate_status!
      assert @event.status_processed?
    end

    test "recalculate_status! marks as failed when all handlers failed" do
      handler1 = @event.incoming_event_handlers.create!(handler_class: "Handler1", status: :failed)
      handler2 = @event.incoming_event_handlers.create!(handler_class: "Handler2", status: :failed)

      @event.recalculate_status!
      assert @event.status_failed?
    end

    test "recalculate_status! marks as partially_processed when some handlers failed" do
      handler1 = @event.incoming_event_handlers.create!(handler_class: "Handler1", status: :processed)
      handler2 = @event.incoming_event_handlers.create!(handler_class: "Handler2", status: :failed)

      @event.recalculate_status!
      assert @event.status_partially_processed?
    end

    test "recalculate_status! marks as processing when none processed or failed" do
      handler1 = @event.incoming_event_handlers.create!(handler_class: "Handler1", status: :pending)

      @event.recalculate_status!
      assert @event.status_processing?
    end

    test "recalculate_status! does nothing when no handlers" do
      @event.status = :processing
      @event.save!

      @event.recalculate_status!
      assert @event.status_processing?
    end

    # === Associations ===

    test "has many incoming_event_handlers" do
      assert_respond_to @event, :incoming_event_handlers
    end

    test "destroys associated handlers when destroyed" do
      handler = @event.incoming_event_handlers.create!(handler_class: "TestHandler")

      assert_difference "CaptainHook::IncomingEventHandler.count", -1 do
        @event.destroy
      end
    end

    # === Uniqueness ===

    test "prevents duplicate events with same provider and external_id" do
      duplicate = CaptainHook::IncomingEvent.new(
        provider: @event.provider,
        external_id: @event.external_id,
        event_type: "different.event"
      )

      assert_raises(ActiveRecord::RecordNotUnique) do
        duplicate.save!(validate: false)
      end
    end

    test "allows same external_id for different providers" do
      assert_nothing_raised do
        CaptainHook::IncomingEvent.create!(
          provider: "different_provider",
          external_id: @event.external_id,
          event_type: "test.event"
        )
      end
    end

    test "mark_replayed! sets status to replayed" do
      @event.mark_replayed!
      @event.reload

      assert_equal "replayed", @event.dedup_state
    end

    test "start_processing! updates status to processing" do
      @event.start_processing!
      @event.reload

      assert_equal "processing", @event.status
    end

    test "mark_failed! sets status to failed" do
      @event.mark_failed!
      @event.reload

      assert_equal "failed", @event.status
    end

    test "mark_processed! sets status to processed" do
      @event.mark_processed!
      @event.reload

      assert_equal "processed", @event.status
    end
  end
end
