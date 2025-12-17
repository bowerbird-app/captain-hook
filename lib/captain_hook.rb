# frozen_string_literal: true

require "kaminari"
require "captain_hook/version"
require "captain_hook/engine"
require "captain_hook/configuration"
require "captain_hook/handler_registry"
require "captain_hook/provider_config"
require "captain_hook/time_window_validator"
require "captain_hook/signature_generator"
require "captain_hook/instrumentation"

# Load adapters
require "captain_hook/adapters/base"
require "captain_hook/adapters/stripe"
require "captain_hook/adapters/webhook_site"
require "captain_hook/adapters/paypal"
require "captain_hook/adapters/square"

# Load services
require "captain_hook/services/base_service"
require "captain_hook/services/rate_limiter"
require "captain_hook/services/example_service"

# Load gem communication infrastructure
require "captain_hook/provider_loader"
require "captain_hook/handler_loader"

module CaptainHook
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    # Convenience method to access handler registry
    def handler_registry
      configuration.handler_registry
    end

    # Convenience method to register a handler
    def register_handler(**)
      handler_registry.register(**)
    end

    # Register a webhook provider programmatically
    # @param name [String] Unique provider name (lowercase, underscores only)
    # @param display_name [String] Human-readable name
    # @param adapter_class [String] Adapter class name
    # @param gem_source [String] Optional gem name that provides this provider
    # @param options [Hash] Additional provider configuration
    # @option options [String] :description Provider description
    # @option options [String] :signing_secret Webhook signing secret
    # @option options [Integer] :timestamp_tolerance_seconds Timestamp validation tolerance
    # @option options [Integer] :max_payload_size_bytes Maximum payload size
    # @option options [Integer] :rate_limit_requests Rate limit requests per period
    # @option options [Integer] :rate_limit_period Rate limit time period in seconds
    # @option options [Boolean] :active Whether provider is active (default: true)
    # @return [CaptainHook::Provider] The created or updated provider
    def register_provider(name:, display_name:, adapter_class:, gem_source: nil, **options)
      unless defined?(CaptainHook::Provider)
        Rails.logger.warn("CaptainHook: Provider model not loaded, skipping provider registration for #{name}") if defined?(Rails)
        return nil
      end

      provider = CaptainHook::Provider.find_or_initialize_by(
        name: name,
        gem_source: gem_source
      )

      provider.display_name = display_name
      provider.adapter_class = adapter_class
      provider.description = options[:description] if options[:description]
      provider.signing_secret = options[:signing_secret] if options[:signing_secret]
      provider.timestamp_tolerance_seconds = options[:timestamp_tolerance_seconds] if options[:timestamp_tolerance_seconds]
      provider.max_payload_size_bytes = options[:max_payload_size_bytes] if options[:max_payload_size_bytes]
      provider.rate_limit_requests = options[:rate_limit_requests] if options[:rate_limit_requests]
      provider.rate_limit_period = options[:rate_limit_period] if options[:rate_limit_period]
      provider.active = options.fetch(:active, true) if provider.new_record?

      provider.save!
      provider
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("CaptainHook: Failed to register provider #{name}: #{e.message}") if defined?(Rails)
      nil
    end
  end
end
