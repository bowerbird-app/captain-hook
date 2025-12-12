# frozen_string_literal: true

module CaptainHook
  # Represents an outgoing webhook event to be delivered to an endpoint
  # Includes retry logic, circuit breaker integration, and response tracking
  class OutgoingEvent < ApplicationRecord
    self.table_name = "captain_hook_outgoing_events"

    # Status progression: pending -> processing -> delivered/failed
    enum :status, {
      pending: "pending",
      processing: "processing",
      delivered: "delivered",
      failed: "failed"
    }, prefix: true

    # Serialize JSON fields
    serialize :headers, coder: JSON
    serialize :payload, coder: JSON
    serialize :metadata, coder: JSON

    # Validations
    validates :provider, presence: true
    validates :event_type, presence: true
    validates :target_url, presence: true
    validates :status, presence: true
    validates :attempt_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    # Scopes
    scope :pending, -> { where(status: :pending) }
    scope :failed, -> { where(status: :failed) }
    scope :delivered, -> { where(status: :delivered) }
    scope :by_provider, ->(provider) { where(provider: provider) }
    scope :archived, -> { where.not(archived_at: nil) }
    scope :not_archived, -> { where(archived_at: nil) }
    scope :recent, -> { order(created_at: :desc) }
    scope :ready_for_retry, -> {
      where(status: :failed)
        .where("last_attempt_at IS NULL OR last_attempt_at < ?", 5.minutes.ago)
    }

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
      update!(status: :processing, queued_at: Time.current)
    end

    # Mark as delivered successfully
    def mark_delivered!(response_code:, response_body:, response_time_ms:)
      update!(
        status: :delivered,
        delivered_at: Time.current,
        response_code: response_code,
        response_body: truncate_response_body(response_body),
        response_time_ms: response_time_ms,
        error_message: nil
      )
    end

    # Mark as failed with error
    def mark_failed!(error, response_code: nil, response_body: nil, response_time_ms: nil)
      update!(
        status: :failed,
        error_message: error.to_s.truncate(1000),
        response_code: response_code,
        response_body: truncate_response_body(response_body),
        response_time_ms: response_time_ms,
        last_attempt_at: Time.current
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
        error_message: nil
      )
    end

    # Check if response code indicates success (2xx)
    def self.success_response?(code)
      code && code >= 200 && code < 300
    end

    # Check if response code indicates client error (4xx) - generally non-retryable
    def self.client_error?(code)
      code && code >= 400 && code < 500
    end

    # Check if response code indicates server error (5xx) - retryable
    def self.server_error?(code)
      code && code >= 500 && code < 600
    end

    private

    # Truncate response body to prevent excessive storage usage
    def truncate_response_body(body)
      return nil if body.blank?

      body.to_s.truncate(10_000)
    end
  end
end
