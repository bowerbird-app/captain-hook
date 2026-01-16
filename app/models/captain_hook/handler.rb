# frozen_string_literal: true

module CaptainHook
  # Represents a webhook handler configuration persisted to the database
  # Handlers are discovered from HandlerRegistry and synced to the database
  class Handler < ApplicationRecord
    self.table_name = "captain_hook_handlers"

    # Validations
    validates :provider, presence: true
    validates :event_type, presence: true
    validates :handler_class, presence: true
    validates :priority, presence: true, numericality: { only_integer: true }
    validates :max_attempts, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :retry_delays, presence: true

    # Ensure retry_delays is an array of integers
    validate :retry_delays_must_be_array_of_integers

    # Scopes
    scope :active, -> { where(deleted_at: nil) }
    scope :deleted, -> { where.not(deleted_at: nil) }
    scope :by_priority, -> { order(priority: :asc, handler_class: :asc) }
    scope :for_provider, ->(provider) { where(provider: provider) }
    scope :for_event_type, ->(event_type) { where(event_type: event_type) }

    # Soft delete
    def soft_delete!
      update!(deleted_at: Time.current)
    end

    # Restore from soft delete
    def restore!
      update!(deleted_at: nil)
    end

    # Check if handler is deleted
    def deleted?
      deleted_at.present?
    end

    # Get the full registry key
    def registry_key
      "#{provider}:#{event_type}"
    end

    # Get the associated Provider record
    def provider_record
      CaptainHook::Provider.find_by(name: provider)
    end

    private

    def retry_delays_must_be_array_of_integers
      return if retry_delays.is_a?(Array) && retry_delays.all? { |d| d.is_a?(Integer) && d.positive? }

      errors.add(:retry_delays, "must be an array of positive integers")
    end
  end
end
