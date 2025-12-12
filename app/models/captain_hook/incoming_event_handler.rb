# frozen_string_literal: true

module CaptainHook
  # Represents a single handler execution for an incoming event
  # Supports priority-based ordering and optimistic locking for concurrency
  class IncomingEventHandler < ApplicationRecord
    self.table_name = "captain_hook_incoming_event_handlers"

    # Status progression: pending -> processing -> processed/failed
    enum :status, {
      pending: "pending",
      processing: "processing",
      processed: "processed",
      failed: "failed"
    }, prefix: true

    # Associations
    belongs_to :incoming_event

    # Validations
    validates :handler_class, presence: true
    validates :status, presence: true
    validates :priority, presence: true, numericality: { only_integer: true }
    validates :attempt_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # Scopes
    scope :pending, -> { where(status: :pending) }
    scope :failed, -> { where(status: :failed) }
    scope :by_priority, -> { order(priority: :asc, handler_class: :asc) }
    scope :locked, -> { where.not(locked_at: nil) }
    scope :unlocked, -> { where(locked_at: nil) }

    # Acquire lock for processing (optimistic locking)
    def acquire_lock!(worker_id)
      # Use optimistic locking to prevent concurrent execution
      update!(
        locked_at: Time.current,
        locked_by: worker_id,
        status: :processing
      )
    rescue ActiveRecord::StaleObjectError
      # Someone else got the lock
      false
    end

    # Release lock
    def release_lock!
      update!(locked_at: nil, locked_by: nil)
    end

    # Check if locked
    def locked?
      locked_at.present?
    end

    # Mark as processed successfully
    def mark_processed!
      update!(
        status: :processed,
        error_message: nil,
        locked_at: nil,
        locked_by: nil
      )
    end

    # Mark as failed with error
    def mark_failed!(error)
      update!(
        status: :failed,
        error_message: error.to_s.truncate(1000),
        last_attempt_at: Time.current,
        locked_at: nil,
        locked_by: nil
      )
    end

    # Increment attempt counter
    def increment_attempts!
      increment!(:attempt_count)
      update!(last_attempt_at: Time.current)
    end

    # Check if max attempts reached
    def max_attempts_reached?(max_attempts)
      attempt_count >= max_attempts
    end

    # Reset for retry
    def reset_for_retry!
      update!(
        status: :pending,
        locked_at: nil,
        locked_by: nil
      )
    end
  end
end
