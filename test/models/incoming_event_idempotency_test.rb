# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingEventIdempotencyTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.find_or_create_by!(name: "test_provider") do |p|
        p.token = SecureRandom.hex(16)
        p.active = true
      end
    end

    # === FIRST Request - Creates Event ===

    test "creates event on first request" do
      assert_difference "IncomingEvent.count", 1 do
        event = IncomingEvent.find_or_create_by_external!(
          provider: "test_provider",
          external_id: "evt_unique_#{SecureRandom.hex(8)}",
          event_type: "charge.succeeded",
          payload: { data: "test" }
        )

        assert event.persisted?
        assert_equal "unique", event.dedup_state
        assert_equal "received", event.status
      end
    end

    test "sets correct attributes on first request" do
      event = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: "evt_first_123",
        event_type: "payment.succeeded",
        payload: { amount: 1000 },
        headers: { "Content-Type" => "application/json" }
      )

      assert_equal "test_provider", event.provider
      assert_equal "evt_first_123", event.external_id
      assert_equal "payment.succeeded", event.event_type
      assert_equal({ "amount" => 1000 }, event.payload)
      assert event.headers.present?
      assert_equal "unique", event.dedup_state
    end

    # === DUPLICATE Request - Returns Existing Event ===

    test "returns existing event on duplicate request" do
      # Create first event
      first_event = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: "evt_duplicate_123",
        event_type: "charge.succeeded",
        payload: { data: "first" }
      )

      # Try to create duplicate
      assert_no_difference "IncomingEvent.count" do
        second_event = IncomingEvent.find_or_create_by_external!(
          provider: "test_provider",
          external_id: "evt_duplicate_123",
          event_type: "charge.succeeded",
          payload: { data: "second" }
        )

        assert_equal first_event.id, second_event.id
        assert_equal "duplicate", second_event.dedup_state
      end
    end

    test "marks duplicate event with correct dedup_state" do
      # Create first event
      IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: "evt_dup_state",
        event_type: "test.event",
        payload: {}
      )

      # Duplicate request
      duplicate_event = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: "evt_dup_state",
        event_type: "test.event",
        payload: {}
      )

      assert_equal "duplicate", duplicate_event.dedup_state
    end

    test "preserves original payload on duplicate" do
      original_payload = { "original" => "data", "amount" => 500 }

      first_event = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: "evt_payload_test",
        event_type: "test.event",
        payload: original_payload
      )

      # Duplicate with different payload
      second_event = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: "evt_payload_test",
        event_type: "test.event",
        payload: { "different" => "payload" }
      )

      assert_equal first_event.id, second_event.id
      assert_equal original_payload, second_event.payload
    end

    # === RACE CONDITION - Concurrent Duplicate Requests ===

    test "handles race condition with concurrent duplicate requests" do
      external_id = "evt_race_#{SecureRandom.hex(8)}"

      # Simulate race condition using threads
      threads = 5.times.map do
        Thread.new do
          IncomingEvent.find_or_create_by_external!(
            provider: "test_provider",
            external_id: external_id,
            event_type: "test.event",
            payload: { "thread" => Thread.current.object_id }
          )
        end
      end

      events = threads.map(&:value)

      # Should only create one event despite race
      unique_event_ids = events.map(&:id).uniq
      assert_equal 1, unique_event_ids.size, "Should create exactly one event"

      # Verify in database
      db_count = IncomingEvent.where(
        provider: "test_provider",
        external_id: external_id
      ).count
      assert_equal 1, db_count
    end

    test "race condition returns same event to all threads" do
      external_id = "evt_race_same_#{SecureRandom.hex(8)}"

      threads = 10.times.map do
        Thread.new do
          IncomingEvent.find_or_create_by_external!(
            provider: "test_provider",
            external_id: external_id,
            event_type: "race.test",
            payload: {}
          )
        end
      end

      events = threads.map(&:value)

      # All threads should get the same event
      unique_ids = events.map(&:id).uniq
      assert_equal 1, unique_ids.size, "All threads should receive same event ID"
    end

    test "race condition with RecordNotUnique is handled gracefully" do
      external_id = "evt_race_recovery_#{SecureRandom.hex(8)}"

      # Create first event
      first_event = IncomingEvent.create!(
        provider: "test_provider",
        external_id: external_id,
        event_type: "test.event",
        payload: {},
        dedup_state: :unique
      )

      # Simulate race condition by trying to create duplicate
      assert_nothing_raised do
        event = IncomingEvent.find_or_create_by_external!(
          provider: "test_provider",
          external_id: external_id,
          event_type: "test.event",
          payload: {}
        )

        assert_equal first_event.id, event.id
        assert_equal "duplicate", event.dedup_state
      end
    end

    # === DATABASE CONSTRAINT - Unique Index ===

    test "database unique constraint prevents duplicates" do
      IncomingEvent.create!(
        provider: "test_provider",
        external_id: "evt_constraint_test",
        event_type: "test.event",
        payload: {},
        dedup_state: :unique
      )

      # Direct insert should fail due to unique index
      assert_raises(ActiveRecord::RecordNotUnique) do
        IncomingEvent.create!(
          provider: "test_provider",
          external_id: "evt_constraint_test",
          event_type: "test.event",
          payload: {},
          dedup_state: :unique
        )
      end
    end

    test "unique index allows same external_id for different providers" do
      external_id = "evt_multi_provider"

      assert_nothing_raised do
        IncomingEvent.create!(
          provider: "stripe",
          external_id: external_id,
          event_type: "test.event",
          payload: {}
        )

        IncomingEvent.create!(
          provider: "square",
          external_id: external_id,
          event_type: "test.event",
          payload: {}
        )
      end

      assert_equal 2, IncomingEvent.where(external_id: external_id).count
    end

    test "unique index is case-sensitive" do
      IncomingEvent.create!(
        provider: "test_provider",
        external_id: "evt_case_test",
        event_type: "test.event",
        payload: {}
      )

      # Different case should be allowed (if case-sensitive)
      # Or prevented (if case-insensitive) - depends on DB collation
      # This test documents the behavior
      begin
        IncomingEvent.create!(
          provider: "test_provider",
          external_id: "EVT_CASE_TEST",
          event_type: "test.event",
          payload: {}
        )
        # If we get here, index is case-sensitive
        assert_equal 2, IncomingEvent.where("LOWER(external_id) = ?", "evt_case_test").count
      rescue ActiveRecord::RecordNotUnique
        # If we get here, index is case-insensitive
        assert true
      end
    end

    # === Multiple Duplicate Attempts ===

    test "handles multiple duplicate attempts correctly" do
      external_id = "evt_multiple_#{SecureRandom.hex(8)}"

      # First request
      first = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: external_id,
        event_type: "test.event",
        payload: { attempt: 1 }
      )
      assert_equal "unique", first.dedup_state

      # Second request (duplicate)
      second = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: external_id,
        event_type: "test.event",
        payload: { attempt: 2 }
      )
      assert_equal first.id, second.id
      assert_equal "duplicate", second.dedup_state

      # Third request (another duplicate)
      third = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: external_id,
        event_type: "test.event",
        payload: { attempt: 3 }
      )
      assert_equal first.id, third.id
      assert_equal "duplicate", third.dedup_state

      # Should still only have one event in database
      assert_equal 1, IncomingEvent.where(external_id: external_id).count
    end

    # === Edge Cases ===

    test "handles empty external_id" do
      assert_raises(ActiveRecord::RecordInvalid) do
        IncomingEvent.find_or_create_by_external!(
          provider: "test_provider",
          external_id: "",
          event_type: "test.event",
          payload: {}
        )
      end
    end

    test "handles nil external_id" do
      assert_raises(ActiveRecord::RecordInvalid) do
        IncomingEvent.find_or_create_by_external!(
          provider: "test_provider",
          external_id: nil,
          event_type: "test.event",
          payload: {}
        )
      end
    end

    test "handles very long external_id" do
      long_id = "evt_#{'x' * 500}"

      event = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: long_id,
        event_type: "test.event",
        payload: {}
      )

      assert event.persisted?
      assert_equal long_id, event.external_id
    end

    test "handles special characters in external_id" do
      special_id = "evt-test_123!@#$%^&*()"

      event = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: special_id,
        event_type: "test.event",
        payload: {}
      )

      assert event.persisted?
      assert_equal special_id, event.external_id

      # Duplicate with same special characters
      duplicate = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: special_id,
        event_type: "test.event",
        payload: {}
      )

      assert_equal event.id, duplicate.id
    end

    test "handles unicode in external_id" do
      unicode_id = "evt_世界_🌍_#{SecureRandom.hex(4)}"

      event = IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: unicode_id,
        event_type: "test.event",
        payload: {}
      )

      assert event.persisted?
      assert_equal unicode_id, event.external_id
    end

    # === Performance ===

    test "find_or_create_by_external is efficient for duplicates" do
      external_id = "evt_perf_#{SecureRandom.hex(8)}"

      # Create first event
      IncomingEvent.find_or_create_by_external!(
        provider: "test_provider",
        external_id: external_id,
        event_type: "test.event",
        payload: {}
      )

      # Measure time for duplicate lookups
      start_time = Time.current
      100.times do
        IncomingEvent.find_or_create_by_external!(
          provider: "test_provider",
          external_id: external_id,
          event_type: "test.event",
          payload: {}
        )
      end
      elapsed = Time.current - start_time

      # Should be fast (< 1 second for 100 lookups)
      assert elapsed < 1.0, "Duplicate lookups should be fast, took #{elapsed}s"

      # Should still only have one event
      assert_equal 1, IncomingEvent.where(external_id: external_id).count
    end
  end
end
