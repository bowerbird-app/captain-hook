# frozen_string_literal: true

require_relative "hooks"
require_relative "action_registry"
require_relative "provider_config"

module CaptainHook
  class Configuration
    attr_accessor :admin_parent_controller, :admin_layout, :retention_days
    attr_reader :hooks, :action_registry, :providers

    def initialize
      @admin_parent_controller = "ApplicationController"
      @admin_layout = "application"
      @retention_days = 90 # Default retention period
      @hooks = Hooks.new
      @action_registry = ActionRegistry.new
      @providers = {}
    end

    # Deprecated: Backward compatibility for handler_registry
    def handler_registry
      warn "[DEPRECATION] `handler_registry` is deprecated. Use `action_registry` instead."
      @action_registry
    end

    # Register a provider configuration (for backward compatibility)
    # Note: Providers should now be managed via the Provider model in the database
    def register_provider(name, **)
      @providers[name.to_s] = ProviderConfig.new(name: name.to_s, **)
    end

    # Get a provider configuration (checks both DB and in-memory registrations)
    def provider(name)
      # First check database
      db_provider = CaptainHook::Provider.find_by(name: name.to_s)
      return provider_config_from_model(db_provider) if db_provider

      # Fall back to in-memory registration
      @providers[name.to_s]
    end

    def to_h
      {
        admin_parent_controller: admin_parent_controller,
        admin_layout: admin_layout,
        retention_days: retention_days,
        providers: @providers.keys,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end

    private

    # Convert Provider model to ProviderConfig for backward compatibility
    def provider_config_from_model(provider)
      ProviderConfig.new(
        name: provider.name,
        token: provider.token,
        signing_secret: provider.signing_secret,
        verifier_class: provider.verifier_class,
        timestamp_tolerance_seconds: provider.timestamp_tolerance_seconds,
        max_payload_size_bytes: provider.max_payload_size_bytes,
        rate_limit_requests: provider.rate_limit_requests,
        rate_limit_period: provider.rate_limit_period
      )
    end
  end
end
