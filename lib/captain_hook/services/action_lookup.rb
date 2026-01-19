# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for looking up action configurations
    # Queries database first, falls back to in-memory registry
    # This provides a transition path from registry-only to DB-backed actions
    class ActionLookup
      # Find all actions for a specific provider and event type
      # Returns array of ActionConfig objects (compatible with ActionRegistry format)
      #
      # @param provider [String] Provider name
      # @param event_type [String] Event type
      # @return [Array<ActionRegistry::ActionConfig>] Array of action configurations
      def self.actions_for(provider:, event_type:)
        new.actions_for(provider: provider, event_type: event_type)
      end

      # Find a specific action configuration
      #
      # @param provider [String] Provider name
      # @param event_type [String] Event type
      # @param action_class [String] Action class name
      # @return [ActionRegistry::ActionConfig, nil] Action configuration or nil
      def self.find_action_config(provider:, event_type:, action_class:)
        new.find_action_config(
          provider: provider,
          event_type: event_type,
          action_class: action_class
        )
      end

      def actions_for(provider:, event_type:)
        # First, try to get active actions from database
        db_actions = CaptainHook::Action
                      .active
                      .for_provider(provider)
                      .for_event_type(event_type)
                      .by_priority

        if db_actions.any?
          Rails.logger.info "🔍 [ActionLookup] Found #{db_actions.count} active action(s) in DB for #{provider}:#{event_type}"
          return db_actions.map { |h| action_to_config(h, source: :database) }
        end

        # Check if there are soft-deleted actions for this provider/event_type
        # If yes, respect the deletion and don't fall back to registry
        deleted_actions = CaptainHook::Action
                           .deleted
                           .for_provider(provider)
                           .for_event_type(event_type)

        if deleted_actions.any?
          Rails.logger.info "🗑️  [ActionLookup] Found #{deleted_actions.count} deleted action(s) in DB for #{provider}:#{event_type}, not falling back to registry"
          return []
        end

        # No actions in DB at all (neither active nor deleted) - fall back to in-memory registry
        registry_actions = CaptainHook.action_registry.actions_for(
          provider: provider,
          event_type: event_type
        )

        # Mark registry configs with source for tracking
        registry_actions.each do |config|
          config.define_singleton_method(:config_source) { :registry }
        end

        registry_actions
      end

      def find_action_config(provider:, event_type:, action_class:)
        # First, try to find active action in database
        db_action = CaptainHook::Action
                     .active
                     .for_provider(provider)
                     .for_event_type(event_type)
                     .find_by(action_class: action_class.to_s)

        if db_action
          Rails.logger.info "🔍 [ActionLookup] Found action #{action_class} in DB (active)"
          return action_to_config(db_action, source: :database)
        end

        # Check if this specific action was soft-deleted
        # If yes, respect the deletion and don't fall back to registry
        deleted_action = CaptainHook::Action
                          .deleted
                          .for_provider(provider)
                          .for_event_type(event_type)
                          .find_by(action_class: action_class.to_s)

        if deleted_action
          Rails.logger.info "🗑️  [ActionLookup] Action #{action_class} is soft-deleted in DB, not falling back to registry"
          return nil
        end

        # Action doesn't exist in DB at all - fall back to in-memory registry
        Rails.logger.warn "⚠️  [ActionLookup] Action #{action_class} not found in DB, falling back to registry"
        config = CaptainHook.action_registry.find_action_config(
          provider: provider,
          event_type: event_type,
          action_class: action_class
        )

        config.define_singleton_method(:config_source) { :registry } if config

        config
      end

      private

      # Convert an Action model to an ActionRegistry::ActionConfig struct
      def action_to_config(action, source: :database)
        config = CaptainHook::ActionRegistry::ActionConfig.new(
          provider: action.provider,
          event_type: action.event_type,
          action_class: action.action_class,
          async: action.async,
          retry_delays: action.retry_delays,
          max_attempts: action.max_attempts,
          priority: action.priority
        )

        # Add metadata about where this config came from
        config.define_singleton_method(:config_source) { source }

        config
      end
    end
  end
end
