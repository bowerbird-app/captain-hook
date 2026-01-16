# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for discovering registered handlers from the HandlerRegistry
    # Scans the in-memory handler registry and returns handler configurations
    class HandlerDiscovery < BaseService
      def initialize
        @discovered_handlers = []
      end

      # Scan the handler registry for all registered handlers
      # Returns array of handler definitions (hashes)
      def call
        registry = CaptainHook.handler_registry

        # Access the internal registry to get all handlers
        registry.instance_variable_get(:@registry).each do |key, configs|
          provider, event_type = key.split(":", 2)

          configs.each do |config|
            @discovered_handlers << {
              "provider" => provider,
              "event_type" => event_type,
              "handler_class" => config.handler_class.to_s,
              "async" => config.async,
              "max_attempts" => config.max_attempts,
              "priority" => config.priority,
              "retry_delays" => config.retry_delays
            }
          end
        end

        @discovered_handlers
      end

      # Scan handlers for a specific provider
      def self.for_provider(provider_name)
        discovery = new
        all_handlers = discovery.call
        all_handlers.select { |h| h["provider"] == provider_name }
      end
    end
  end
end
