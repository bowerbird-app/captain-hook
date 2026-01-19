# frozen_string_literal: true

module CaptainHook
  # Represents a webhook provider (e.g., Stripe, OpenAI, GitHub)
  # Stores configuration for receiving webhooks from external services
  class Provider < ApplicationRecord
    self.table_name = "captain_hook_providers"

    # Encryption enabled - signing secrets are encrypted at rest
    # See docs/gem_template/SIGNING_SECRET_STORAGE.md for details
    encrypts :signing_secret, deterministic: false

    # Associations
    has_many :incoming_events, primary_key: :name, foreign_key: :provider, dependent: :restrict_with_error
    has_many :actions, primary_key: :name, foreign_key: :provider, class_name: "CaptainHook::Action",
                        dependent: :destroy

    # Deprecated: Backward compatibility alias
    has_many :handlers, class_name: "CaptainHook::Action", foreign_key: :provider, primary_key: :name

    # Validations
    validates :name, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" }
    validates :token, presence: true, uniqueness: true
    validates :verifier_class, presence: true
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
      base = base_url || detect_base_url
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

    # Get signing secret (supports ENV variable override)
    # This allows storing secrets in ENV instead of DB for sensitive providers
    # Example: STRIPE_WEBHOOK_SECRET=whsec_abc123
    def signing_secret
      return super if name.blank?

      env_key = "#{name.upcase}_WEBHOOK_SECRET"
      ENV[env_key].presence || super
    end

    # Get the verifier instance
    def verifier
      # Try to constantize the verifier class first (it might be a built-in verifier)
      begin
        return verifier_class.constantize.new
      rescue NameError
        # Class doesn't exist yet, try to load from file
      end

      # Try to find and load the verifier file if the class doesn't exist yet
      load_verifier_file

      verifier_class.constantize.new
    rescue NameError => e
      Rails.logger.error("Failed to load verifier #{verifier_class}: #{e.message}")
      raise CaptainHook::VerifierNotFoundError,
            "Verifier #{verifier_class} not found. Ensure the verifier file exists in the provider directory or use a built-in verifier (CaptainHook::Verifiers::Base, Stripe, Square, Paypal, WebhookSite)."
    end

    # Load the verifier file from the filesystem
    def load_verifier_file
      return if verifier_file.blank?

      # Try to find the verifier file in common locations
      possible_paths = [
        # Application providers directory (nested structure)
        Rails.root.join("captain_hook", "providers", name, verifier_file),
        # Application providers directory (flat structure)
        Rails.root.join("captain_hook", "providers", verifier_file)
      ]

      # Check in CaptainHook gem's built-in verifiers
      # Use __dir__ to get the directory of this file, then navigate to lib/captain_hook/verifiers
      gem_verifiers_path = File.expand_path("../../lib/captain_hook/verifiers", __dir__)
      if Dir.exist?(gem_verifiers_path)
        possible_paths << File.join(gem_verifiers_path, verifier_file)
      end

      # Also check in other loaded gems
      Bundler.load.specs.each do |spec|
        gem_providers_path = File.join(spec.full_gem_path, "captain_hook", "providers")
        next unless Dir.exist?(gem_providers_path)

        possible_paths << File.join(gem_providers_path, name, verifier_file)
        possible_paths << File.join(gem_providers_path, verifier_file)
      end

      file_path = possible_paths.find { |path| File.exist?(path) }

      if file_path
        load file_path
        Rails.logger.debug("Loaded verifier from #{file_path}")
      else
        Rails.logger.warn("Verifier file not found for #{name}, tried: #{possible_paths.inspect}")
      end
    rescue StandardError => e
      Rails.logger.error("Failed to load verifier file: #{e.message}")
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
