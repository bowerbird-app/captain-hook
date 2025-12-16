# frozen_string_literal: true

module CaptainHook
  # Represents a webhook provider (e.g., Stripe, OpenAI, GitHub)
  # Stores configuration for receiving webhooks from external services
  class Provider < ApplicationRecord
    self.table_name = "captain_hook_providers"

    # TODO: Enable encryption in production
    # encrypts :signing_secret, deterministic: false
    # Requires: rails credentials:edit to set active_record_encryption keys

    # Associations
    has_many :incoming_events, primary_key: :name, foreign_key: :provider, dependent: :restrict_with_error

    # Validations
    validates :name, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" }
    validates :token, presence: true, uniqueness: true
    validates :adapter_class, presence: true
    validates :timestamp_tolerance_seconds, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :max_payload_size_bytes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :rate_limit_requests, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validates :rate_limit_period, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

    # Scopes
    scope :active, -> { where(active: true) }
    scope :inactive, -> { where(active: false) }
    scope :by_name, -> { order(:name) }

    # Callbacks
    before_validation :normalize_name
    before_validation :generate_token, if: -> { token.blank? }

    # Generate webhook URL for this provider
    def webhook_url(base_url: nil)
      base = base_url || "#{ENV.fetch('APP_URL', 'http://localhost:3000')}"
      "#{base}/captain_hook/#{name}/#{token}"
    end

    # Check if rate limiting is enabled
    def rate_limiting_enabled?
      rate_limit_requests.present? && rate_limit_period.present?
    end

    # Check if payload size limit is enabled
    def payload_size_limit_enabled?
      max_payload_size_bytes.present?
    end

    # Check if timestamp validation is enabled
    def timestamp_validation_enabled?
      timestamp_tolerance_seconds.present?
    end

    # Get the adapter instance
    def adapter
      adapter_class.constantize.new(signing_secret: signing_secret)
    rescue NameError => e
      Rails.logger.error("Failed to load adapter #{adapter_class}: #{e.message}")
      CaptainHook::Adapters::Base.new(signing_secret: signing_secret)
    end

    # Activate provider
    def activate!
      update!(active: true)
    end

    # Deactivate provider
    def deactivate!
      update!(active: false)
    end

    private

    def normalize_name
      self.name = name&.downcase&.gsub(/[^a-z0-9_]/, "_")
    end

    def generate_token
      self.token = SecureRandom.urlsafe_base64(32)
    end
  end
end
