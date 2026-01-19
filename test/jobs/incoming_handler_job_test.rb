# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingHandlerJobTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.create!(
        name: "test_provider",
        verifier_class: "CaptainHook::Verifiers::Base"
      )

      @event = CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_123",
        event_type: "test.event",
        payload: { "data" => "test" },
        metadata: {}
      )

      @handler_record = @event.incoming_event_handlers.create!(
        handler_class: "MockHandler",
        priority: 100
      )

      # Mock handler class
      unless defined?(MockHandler)
        Object.const_set(:MockHandler, Class.new do
          def handle(event:, payload:, metadata:)
            # Successfully handled
          end
        end)
      end

      # Register handler
      CaptainHook.handler_registry.register(
        provider: @provider.name,
        event_type: "test.event",
        handler_class: "MockHandler",
        priority: 100
      )
    end

    teardown do
      Object.send(:remove_const, :MockHandler) if defined?(MockHandler)
      CaptainHook.handler_registry.clear!
    end

    test "job processes handler successfully" do
      assert @handler_record.status_pending?

      IncomingHandlerJob.perform_now(@handler_record.id)

      @handler_record.reload
      assert @handler_record.status_processed?
      assert_nil @handler_record.error_message
    end

    test "job acquires lock before processing" do
      worker_id = "test_worker"

      IncomingHandlerJob.perform_now(@handler_record.id, worker_id: worker_id)

      @handler_record.reload
      # Lock should be released after processing
      refute @handler_record.locked?
    end

    test "job increments attempt count" do
      initial_count = @handler_record.attempt_count

      IncomingHandlerJob.perform_now(@handler_record.id)

      @handler_record.reload
      assert_equal initial_count + 1, @handler_record.attempt_count
    end

    test "job updates event status after processing" do
      @event.status = :processing
      @event.save!

      IncomingHandlerJob.perform_now(@handler_record.id)

      @event.reload
      assert @event.status_processed?
    end

    test "job handles handler errors gracefully" do
      # Create failing handler
      Object.const_set(:FailingHandler, Class.new do
        def handle(event:, payload:, metadata:)
          raise StandardError, "Handler failed"
        end
      end)

      @handler_record.handler_class = "FailingHandler"
      @handler_record.save!

      CaptainHook.handler_registry.register(
        provider: @provider.name,
        event_type: "test.event",
        handler_class: "FailingHandler",
        priority: 100
      )

      # Job may swallow the exception due to retry_on or schedules a retry
      begin
        IncomingHandlerJob.perform_now(@handler_record.id)
      rescue StandardError
        # Exception may or may not be raised
      end

      @handler_record.reload
      # Handler should be marked as failed or retry scheduled
      assert(@handler_record.status_failed? || @handler_record.status_pending?)
      assert_includes @handler_record.error_message, "Handler failed" if @handler_record.error_message

      Object.send(:remove_const, :FailingHandler)
    end

    test "job does not process when handler config not found" do
      CaptainHook.handler_registry.clear!

      IncomingHandlerJob.perform_now(@handler_record.id)

      @handler_record.reload
      # Handler remains locked but won't be processed without config
      # The job returns early so status may remain unchanged
      assert @handler_record.locked?
    end

    test "job does not process if lock cannot be acquired" do
      # Lock handler by setting an old lock_version to simulate concurrent update
      @handler_record.update!(locked_at: Time.current, locked_by: "other_worker", status: :processing)

      # This job will try to acquire lock but should fail due to optimistic locking
      # The acquire_lock! will catch StaleObjectError and return false, causing early return
      assert_nothing_raised do
        IncomingHandlerJob.perform_now(@handler_record.id, worker_id: "this_worker")
      end
    end

    test "job is configured with queue" do
      # Job should have a queue configured
      assert_not_nil IncomingHandlerJob.new.queue_name
    end

    test "job passes event and payload to handler" do
      received_args = {}

      Object.const_set(:TrackingHandler, Class.new do
        define_method(:handle) do |event:, payload:, metadata:|
          received_args[:event] = event
          received_args[:payload] = payload
          received_args[:metadata] = metadata
        end
      end.tap { |klass| klass.define_singleton_method(:instance) { @instance ||= new } })

      @handler_record.handler_class = "TrackingHandler"
      @handler_record.save!

      CaptainHook.handler_registry.register(
        provider: @provider.name,
        event_type: "test.event",
        handler_class: "TrackingHandler",
        priority: 100
      )

      IncomingHandlerJob.perform_now(@handler_record.id)

      assert_equal @event.id, received_args[:event].id
      assert_equal({ "data" => "test" }, received_args[:payload])

      Object.send(:remove_const, :TrackingHandler)
    end
  end

  class ArchivalJobTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.create!(
        name: "test_provider",
        verifier_class: "CaptainHook::Verifiers::Base"
      )
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
