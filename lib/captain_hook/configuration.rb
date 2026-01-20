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

    # Register a provider configuration (for backward compatibility)
    # Note: Providers should now be managed via the Provider model in the database
    def register_provider(name, **)
      @providers[name.to_s] = ProviderConfig.new(name: name.to_s, **)
    end

    # Get a provider configuration (checks registry and DB)
    def provider(name)
      # Get provider from database for token and rate limits
      db_provider = CaptainHook::Provider.find_by(name: name.to_s)
      return nil unless db_provider
      
      # Use registry_config which pulls from YAML files (source of truth)
      db_provider.registry_config
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
  end
end
