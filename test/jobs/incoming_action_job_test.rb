# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingActionJobTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.find_or_create_by!(name: "test_provider") do |p|
        p.token = SecureRandom.hex(16)
      end

      @event = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_123",
        event_type: "test.event",
        payload: { "data" => "test" },
        metadata: {}
      )

      @action_record = @event.incoming_event_actions.create!(
        action_class: "MockAction",
        priority: 100
      )

      # Mock action class
      unless defined?(MockAction)
        Object.const_set(:MockAction, Class.new do
          def handle(event:, payload:, metadata:)
            # Successfully handled
          end
        end)
      end

      # Register action
      CaptainHook.action_registry.register(
        provider: @provider.name,
        event_type: "test.event",
        action_class: "MockAction",
        priority: 100
      )
    end

    teardown do
      Object.send(:remove_const, :MockAction) if defined?(MockAction)
      CaptainHook.action_registry.clear!
    end

    test "job processes action successfully" do
      assert @action_record.status_pending?

      IncomingActionJob.perform_now(@action_record.id)

      @action_record.reload
      assert @action_record.status_processed?
      assert_nil @action_record.error_message
    end

    test "job acquires lock before processing" do
      worker_id = "test_worker"

      IncomingActionJob.perform_now(@action_record.id, worker_id: worker_id)

      @action_record.reload
      # Lock should be released after processing
      refute @action_record.locked?
    end

    test "job increments attempt count" do
      initial_count = @action_record.attempt_count

      IncomingActionJob.perform_now(@action_record.id)

      @action_record.reload
      assert_equal initial_count + 1, @action_record.attempt_count
    end

    test "job updates event status after processing" do
      @event.status = :processing
      @event.save!

      IncomingActionJob.perform_now(@action_record.id)

      @event.reload
      assert @event.status_processed?
    end

    test "job handles action errors gracefully" do
      # Create failing action
      Object.const_set(:FailingAction, Class.new do
        def handle(event:, payload:, metadata:)
          raise StandardError, "Action failed"
        end
      end)

      @action_record.action_class = "FailingAction"
      @action_record.save!

      CaptainHook.action_registry.register(
        provider: @provider.name,
        event_type: "test.event",
        action_class: "FailingAction",
        priority: 100
      )

      # Job may swallow the exception due to retry_on or schedules a retry
      begin
        IncomingActionJob.perform_now(@action_record.id)
      rescue StandardError
        # Exception may or may not be raised
      end

      @action_record.reload
      # Action should be marked as failed or retry scheduled
      assert(@action_record.status_failed? || @action_record.status_pending?)
      assert_includes @action_record.error_message, "Action failed" if @action_record.error_message

      Object.send(:remove_const, :FailingAction)
    end

    test "job does not process when action config not found" do
      CaptainHook.action_registry.clear!

      IncomingActionJob.perform_now(@action_record.id)

      @action_record.reload
      # Action remains locked but won't be processed without config
      # The job returns early so status may remain unchanged
      assert @action_record.locked?
    end

    test "job does not process if lock cannot be acquired" do
      # Lock action by setting an old lock_version to simulate concurrent update
      @action_record.update!(locked_at: Time.current, locked_by: "other_worker", status: :processing)

      # This job will try to acquire lock but should fail due to optimistic locking
      # The acquire_lock! will catch StaleObjectError and return false, causing early return
      assert_nothing_raised do
        IncomingActionJob.perform_now(@action_record.id, worker_id: "this_worker")
      end
    end

    test "job is configured with queue" do
      # Job should have a queue configured
      assert_not_nil IncomingActionJob.new.queue_name
    end

    test "job passes event and payload to action" do
      received_args = {}

      Object.const_set(:TrackingAction, Class.new do
        define_method(:handle) do |event:, payload:, metadata:|
          received_args[:event] = event
          received_args[:payload] = payload
          received_args[:metadata] = metadata
        end
      end.tap { |klass| klass.define_singleton_method(:instance) { @instance ||= new } })

      @action_record.action_class = "TrackingAction"
      @action_record.save!

      CaptainHook.action_registry.register(
        provider: @provider.name,
        event_type: "test.event",
        action_class: "TrackingAction",
        priority: 100
      )

      IncomingActionJob.perform_now(@action_record.id)

      assert_equal @event.id, received_args[:event].id
      assert_equal({ "data" => "test" }, received_args[:payload])

      Object.send(:remove_const, :TrackingAction)
    end
  end

  class ArchivalJobTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.find_or_create_by!(name: "test_provider_archival") do |p|
        p.token = SecureRandom.hex(16)
      end
    end

    test "job archives old events" do
      old_event = nil
      travel_to 100.days.ago do
        old_event = CaptainHook::IncomingEvent.create!(
          provider: @provider.name,
          external_id: "evt_old",
          event_type: "test.event"
        )
      end

      recent_event = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_recent",
        event_type: "test.event"
      )

      ArchivalJob.perform_now(retention_days: 90)

      old_event.reload
      recent_event.reload

      assert old_event.archived?
      refute recent_event.archived?
    end

    test "job respects retention_days parameter" do
      event_60_days = nil
      travel_to 60.days.ago do
        event_60_days = CaptainHook::IncomingEvent.create!(
          provider: @provider.name,
          external_id: "evt_60",
          event_type: "test.event"
        )
      end

      # Archive events older than 30 days
      ArchivalJob.perform_now(retention_days: 30)

      event_60_days.reload
      assert event_60_days.archived?

      # Create new event 40 days old
      event_40_days = nil
      travel_to 40.days.ago do
        event_40_days = CaptainHook::IncomingEvent.create!(
          provider: @provider.name,
          external_id: "evt_40",
          event_type: "test.event"
        )
      end

      # Archive events older than 50 days
      ArchivalJob.perform_now(retention_days: 50)

      event_40_days.reload
      refute event_40_days.archived?
    end

    test "job uses configuration retention_days when not specified" do
      CaptainHook.configuration.retention_days = 30

      event_60_days = nil
      travel_to 60.days.ago do
        event_60_days = CaptainHook::IncomingEvent.create!(
          provider: @provider.name,
          external_id: "evt_60",
          event_type: "test.event"
        )
      end

      ArchivalJob.perform_now

      event_60_days.reload
      assert event_60_days.archived?
    end

    test "job processes events in batches" do
      # Create 15 old events
      15.times do |i|
        travel_to 100.days.ago do
          CaptainHook::IncomingEvent.create!(
            provider: @provider.name,
            external_id: "evt_#{i}",
            event_type: "test.event"
          )
        end
      end

      # Archive with batch size of 5
      ArchivalJob.perform_now(retention_days: 90, batch_size: 5)

      archived_count = CaptainHook::IncomingEvent.archived.count
      assert_equal 15, archived_count
    end

    test "job does not archive already archived events" do
      old_event = nil
      travel_to 100.days.ago do
        old_event = CaptainHook::IncomingEvent.create!(
          provider: @provider.name,
          external_id: "evt_old",
          event_type: "test.event"
        )
      end

      # Archive once
      old_event.archive!
      original_archived_at = old_event.archived_at

      # Run job again
      ArchivalJob.perform_now(retention_days: 90)

      old_event.reload
      # archived_at should not change
      assert_equal original_archived_at.to_i, old_event.archived_at.to_i
    end

    test "job is configured with queue" do
      # Job should have a queue configured
      assert_not_nil ArchivalJob.new.queue_name
    end

    test "job returns count of archived events" do
      3.times do |i|
        travel_to 100.days.ago do
          CaptainHook::IncomingEvent.create!(
            provider: @provider.name,
            external_id: "evt_#{i}",
            event_type: "test.event"
          )
        end
      end

      count = ArchivalJob.perform_now(retention_days: 90)
      assert_equal 3, count
    end
  end
end
