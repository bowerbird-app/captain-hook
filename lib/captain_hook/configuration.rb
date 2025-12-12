# frozen_string_literal: true

require_relative "hooks"
require_relative "handler_registry"
require_relative "provider_config"
require_relative "outgoing_endpoint"

module CaptainHook
  class Configuration
    attr_accessor :admin_parent_controller, :admin_layout, :retention_days
    attr_reader :hooks, :handler_registry, :providers, :outgoing_endpoints

    def initialize
      @admin_parent_controller = "ApplicationController"
      @admin_layout = "application"
      @retention_days = 90 # Default retention period
      @hooks = Hooks.new
      @handler_registry = HandlerRegistry.new
      @providers = {}
      @outgoing_endpoints = {}
    end

    # Register a provider configuration
    def register_provider(name, **)
      @providers[name.to_s] = ProviderConfig.new(name: name.to_s, **)
    end

    # Get a provider configuration
    def provider(name)
      @providers[name.to_s]
    end

    # Register an outgoing endpoint
    def register_outgoing_endpoint(name, **)
      @outgoing_endpoints[name.to_s] = OutgoingEndpoint.new(name: name.to_s, **)
    end

    # Get an outgoing endpoint configuration
    def outgoing_endpoint(name)
      @outgoing_endpoints[name.to_s]
    end

    def to_h
      {
        admin_parent_controller: admin_parent_controller,
        admin_layout: admin_layout,
        retention_days: retention_days,
        providers: @providers.keys,
        outgoing_endpoints: @outgoing_endpoints.keys,
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
