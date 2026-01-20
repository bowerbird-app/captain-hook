# frozen_string_literal: true

module CaptainHook
  # Represents a webhook provider (e.g., Stripe, OpenAI, GitHub)
  # Stores minimal database configuration: token, rate limits, and active status
  # Main configuration comes from YAML files in captain_hook/<provider>/ (registry)
  class Provider < ApplicationRecord
    self.table_name = "captain_hook_providers"

    # Associations
    has_many :incoming_events, primary_key: :name, foreign_key: :provider, dependent: :restrict_with_error
    has_many :actions, primary_key: :name, foreign_key: :provider, class_name: "CaptainHook::Action",
                       dependent: :destroy

    # Validations
    validates :name, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" }
    validates :token, presence: true, uniqueness: true
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
      base = base_url || detect_base_url
      "#{base}/captain_hook/#{name}/#{token}"
    end

    # Check if rate limiting is enabled
    def rate_limiting_enabled?
      rate_limit_requests.present? && rate_limit_period.present?
    end

    # Activate provider
    def activate!
      update!(active: true)
    end

    # Deactivate provider
    def deactivate!
      update!(active: false)
    end

    # Extract verifier class name from loaded file
    # Looks for classes that include VerifierHelpers or end with "Verifier"
    def self.extract_verifier_class_from_file(file_path)
      return nil unless File.exist?(file_path)

      # First try to guess the class name from the file name
      # e.g., stripe.rb -> StripeVerifier
      file_name = File.basename(file_path, ".rb")
      guessed_class_name = "#{file_name.camelize}Verifier"

      # Check if this class already exists (file was already loaded)
      if Object.const_defined?(guessed_class_name)
        klass = Object.const_get(guessed_class_name)
        if klass.is_a?(Class) && (
          klass.included_modules.any? { |m| m.name == "CaptainHook::VerifierHelpers" } ||
          guessed_class_name.end_with?("Verifier")
        )
          return guessed_class_name
        end
      end

      # Track constants before loading (for new files)
      constants_before = Object.constants

      # Load the file
      load file_path

      # Find new constants (classes defined in the file)
      new_constants = Object.constants - constants_before

      # Look for verifier classes (contain "Verifier" or include VerifierHelpers)
      verifier_class = new_constants.find do |const_name|
        klass = Object.const_get(const_name)
        next unless klass.is_a?(Class)

        # Check if it's a verifier (includes VerifierHelpers or ends with Verifier)
        klass.included_modules.any? { |m| m.name == "CaptainHook::VerifierHelpers" } ||
          const_name.to_s.end_with?("Verifier")
      end

      verifier_class&.to_s
    rescue StandardError => e
      Rails.logger.error("Failed to extract verifier class from #{file_path}: #{e.message}")
      nil
    end

    private

    def normalize_name
      self.name = name&.downcase&.gsub(/[^a-z0-9_]/, "_")
    end

    def generate_token
      self.token = SecureRandom.urlsafe_base64(32)
    end

    def detect_base_url
      # Check for explicit APP_URL first
      return ENV["APP_URL"] if ENV["APP_URL"].present?

      # Detect GitHub Codespaces environment
      if ENV["CODESPACES"] == "true" && ENV["CODESPACE_NAME"].present?
        port = ENV.fetch("PORT", "3004")
        "https://#{ENV.fetch('CODESPACE_NAME', nil)}-#{port}.app.github.dev"
      else
        # Default to localhost with PORT or 3000
        port = ENV.fetch("PORT", "3000")
        "http://localhost:#{port}"
      end
    end
  end
end
