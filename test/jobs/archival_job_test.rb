# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ArchivalJobIntegrationTest < ActiveJob::TestCase
    setup do
      @old_event = CaptainHook::IncomingEvent.create!(
        provider: "stripe",
        external_id: "evt_old",
        event_type: "payment.succeeded",
        payload: { data: "old" },
        status: :processed,
        created_at: 100.days.ago
      )

      @recent_event = CaptainHook::IncomingEvent.create!(
        provider: "stripe",
        external_id: "evt_recent",
        event_type: "payment.succeeded",
        payload: { data: "recent" },
        status: :processed,
        created_at: 30.days.ago
      )
    end

    teardown do
      IncomingEvent.destroy_all
    end

    test "archives events older than retention period" do
      ArchivalJob.new.perform(retention_days: 90, batch_size: 100)

      @old_event.reload
      @recent_event.reload

      assert @old_event.archived?
      refute @recent_event.archived?
    end

    test "uses configuration retention_days when not specified" do
      CaptainHook.configuration.retention_days = 90

      ArchivalJob.new.perform

      @old_event.reload
      assert @old_event.archived?
    end

    test "respects custom retention period" do
      # With 20 days retention, both should be archived
      ArchivalJob.new.perform(retention_days: 20, batch_size: 100)

      @old_event.reload
      @recent_event.reload

      assert @old_event.archived?
      assert @recent_event.archived?
    end

    test "does not re-archive already archived events" do
      @old_event.archive!
      initial_archived_at = @old_event.archived_at

      ArchivalJob.new.perform(retention_days: 90, batch_size: 100)

      @old_event.reload
      assert_equal initial_archived_at.to_i, @old_event.archived_at.to_i
    end

    test "processes events in batches" do
      # Create more events
      5.times do |i|
        IncomingEvent.create!(
          provider: "stripe",
          external_id: "evt_batch_#{i}",
          event_type: "test",
          payload: {},
          status: :processed,
          created_at: 100.days.ago
        )
      end

      # Should process in smaller batches
      ArchivalJob.new.perform(retention_days: 90, batch_size: 2)

      # All old events should be archived
      old_count = IncomingEvent.where("created_at < ?", 90.days.ago).archived.count
      assert old_count >= 6 # @old_event + 5 new ones
    end

    test "returns count of archived events" do
      count = ArchivalJob.new.perform(retention_days: 90, batch_size: 100)

      assert_equal 1, count # Only @old_event should be archived
    end

    test "handles empty result set" do
      # Archive all events first
      IncomingEvent.update_all(archived_at: Time.current)

      count = ArchivalJob.new.perform(retention_days: 90, batch_size: 100)

      assert_equal 0, count
    end

    test "uses captain_hook_maintenance queue" do
      assert_enqueued_with(job: ArchivalJob, queue: "captain_hook_maintenance") do
        ArchivalJob.perform_later
      end
    end

    test "archives only events older than cutoff date" do
      # Create event right at the boundary
      boundary_event = IncomingEvent.create!(
        provider: "stripe",
        external_id: "evt_boundary",
        event_type: "test",
        payload: {},
        status: :processed,
        created_at: 90.days.ago
      )

      ArchivalJob.new.perform(retention_days: 90, batch_size: 100)

      boundary_event.reload
      # Events exactly at 90 days should be archived (created_at < cutoff)
      assert boundary_event.archived?
    end
  end
end
