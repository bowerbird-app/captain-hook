# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for discovering registered actions from the ActionRegistry
    # Scans the in-memory action registry and returns action configurations
    class ActionDiscovery < BaseService
      def initialize
        @discovered_actions = []
      end

      # Scan the action registry for all registered actions
      # Returns array of action definitions (hashes)
      def call
        registry = CaptainHook.action_registry

        # Access the internal registry to get all actions
        registry.instance_variable_get(:@registry).each do |key, configs|
          provider, event_type = key.split(":", 2)

          configs.each do |config|
            @discovered_actions << {
              "provider" => provider,
              "event_type" => event_type,
              "action_class" => config.action_class.to_s,
              "async" => config.async,
              "max_attempts" => config.max_attempts,
              "priority" => config.priority,
              "retry_delays" => config.retry_delays
            }
          end
        end

        @discovered_actions
      end

      # Scan actions for a specific provider
      def self.for_provider(provider_name)
        discovery = new
        all_actions = discovery.call
        all_actions.select { |h| h["provider"] == provider_name }
      end
    end
  end
end
