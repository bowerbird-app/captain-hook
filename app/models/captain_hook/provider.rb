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
    has_many :handlers, primary_key: :name, foreign_key: :provider, class_name: "CaptainHook::Handler",
                        dependent: :destroy

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

    # Get the adapter instance
    def adapter
      # Try to find and load the adapter file if the class doesn't exist yet
      load_adapter_file unless Object.const_defined?(adapter_class)

      adapter_class.constantize.new
    rescue NameError => e
      Rails.logger.error("Failed to load adapter #{adapter_class}: #{e.message}")
      raise CaptainHook::AdapterNotFoundError,
            "Adapter #{adapter_class} not found. Ensure the adapter file exists in the provider directory."
    end

    # Load the adapter file from the filesystem
    def load_adapter_file
      # Try to find the adapter file in common locations
      possible_paths = [
        # Application providers directory (nested structure)
        Rails.root.join("captain_hook", "providers", name, "#{name}.rb"),
        # Application providers directory (flat structure)
        Rails.root.join("captain_hook", "providers", "#{name}.rb")
      ]

      # Also check in loaded gems
      Bundler.load.specs.each do |spec|
        gem_providers_path = File.join(spec.full_gem_path, "captain_hook", "providers")
        next unless Dir.exist?(gem_providers_path)

        possible_paths << File.join(gem_providers_path, name, "#{name}.rb")
        possible_paths << File.join(gem_providers_path, "#{name}.rb")
      end

      adapter_file = possible_paths.find { |path| File.exist?(path) }

      if adapter_file
        load adapter_file
        Rails.logger.debug("Loaded adapter from #{adapter_file}")
      else
        Rails.logger.warn("Adapter file not found for #{name}, tried: #{possible_paths.inspect}")
      end
    rescue StandardError => e
      Rails.logger.error("Failed to load adapter file: #{e.message}")
    end

    # Activate provider
    def activate!
      update!(active: true)
    end

    # Deactivate provider
    def deactivate!
      update!(active: false)
    end

    # Extract adapter class name from loaded file
    # Looks for classes that include AdapterHelpers or end with "Adapter"
    def self.extract_adapter_class_from_file(file_path)
      return nil unless File.exist?(file_path)
      
      # First try to guess the class name from the file name
      # e.g., stripe.rb -> StripeAdapter
      file_name = File.basename(file_path, ".rb")
      guessed_class_name = "#{file_name.camelize}Adapter"
      
      # Check if this class already exists (file was already loaded)
      if Object.const_defined?(guessed_class_name)
        klass = Object.const_get(guessed_class_name)
        if klass.is_a?(Class) && (
          klass.included_modules.any? { |m| m.name == "CaptainHook::AdapterHelpers" } ||
          guessed_class_name.end_with?("Adapter")
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
      
      # Look for adapter classes (contain "Adapter" or include AdapterHelpers)
      adapter_class = new_constants.find do |const_name|
        klass = Object.const_get(const_name)
        next unless klass.is_a?(Class)
        
        # Check if it's an adapter (includes AdapterHelpers or ends with Adapter)
        klass.included_modules.any? { |m| m.name == "CaptainHook::AdapterHelpers" } ||
          const_name.to_s.end_with?("Adapter")
      end
      
      adapter_class&.to_s
    rescue StandardError => e
      Rails.logger.error("Failed to extract adapter class from #{file_path}: #{e.message}")
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
