# frozen_string_literal: true

module CaptainHook
  # Represents an incoming webhook event from a provider
  # Ensures idempotency via unique index on (provider, external_id)
  class IncomingEvent < ApplicationRecord
    self.table_name = "captain_hook_incoming_events"

    # Status progression: received -> processing -> processed/partially_processed/failed
    enum :status, {
      received: "received",
      processing: "processing",
      processed: "processed",
      partially_processed: "partially_processed",
      failed: "failed"
    }, prefix: true

    # Deduplication state for tracking unique vs duplicate events
    enum :dedup_state, {
      unique: "unique",
      duplicate: "duplicate",
      replayed: "replayed"
    }, prefix: true

    # Associations
    has_many :incoming_event_handlers, dependent: :destroy

    # Validations
    validates :provider, presence: true
    validates :external_id, presence: true
    validates :event_type, presence: true
    validates :status, presence: true
    validates :dedup_state, presence: true

    # Scopes
    scope :by_provider, ->(provider) { where(provider: provider) }
    scope :by_event_type, ->(event_type) { where(event_type: event_type) }
    scope :archived, -> { where.not(archived_at: nil) }
    scope :not_archived, -> { where(archived_at: nil) }
    scope :recent, -> { order(created_at: :desc) }

    # Ensure idempotency by checking for existing events
    def self.find_or_create_by_external!(provider:, external_id:, **attributes)
      find_or_create_by!(provider: provider, external_id: external_id) do |event|
        event.assign_attributes(attributes)
      end
    rescue ActiveRecord::RecordNotUnique
      # Handle race condition
      find_by!(provider: provider, external_id: external_id)
    end

    # Mark event as duplicate
    def mark_duplicate!
      update!(dedup_state: :duplicate)
    end

    # Mark event as replayed
    def mark_replayed!
      update!(dedup_state: :replayed)
    end

    # Archive this event
    def archive!
      update!(archived_at: Time.current)
    end

    # Check if event is archived
    def archived?
      archived_at.present?
    end

    # Transition to processing
    def start_processing!
      update!(status: :processing)
    end

    # Mark as processed successfully
    def mark_processed!
      update!(status: :processed)
    end

    # Mark as partially processed (some handlers succeeded, some failed)
    def mark_partially_processed!
      update!(status: :partially_processed)
    end

    # Mark as failed
    def mark_failed!
      update!(status: :failed)
    end

    # Calculate overall status based on handler states
    def recalculate_status!
      return if incoming_event_handlers.empty?

      all_processed = incoming_event_handlers.all?(&:status_processed?)
      any_failed = incoming_event_handlers.any?(&:status_failed?)
      all_failed = incoming_event_handlers.all?(&:status_failed?)

      new_status = if all_processed
                     :processed
                   elsif all_failed
                     :failed
                   elsif any_failed
                     :partially_processed
                   else
                     :processing
                   end

      update!(status: new_status)
    end
  end
end
