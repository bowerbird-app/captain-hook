# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for looking up handler configurations
    # Queries database first, falls back to in-memory registry
    # This provides a transition path from registry-only to DB-backed handlers
    class HandlerLookup
      # Find all handlers for a specific provider and event type
      # Returns array of HandlerConfig objects (compatible with HandlerRegistry format)
      #
      # @param provider [String] Provider name
      # @param event_type [String] Event type
      # @return [Array<HandlerRegistry::HandlerConfig>] Array of handler configurations
      def self.handlers_for(provider:, event_type:)
        new.handlers_for(provider: provider, event_type: event_type)
      end

      # Find a specific handler configuration
      #
      # @param provider [String] Provider name
      # @param event_type [String] Event type
      # @param handler_class [String] Handler class name
      # @return [HandlerRegistry::HandlerConfig, nil] Handler configuration or nil
      def self.find_handler_config(provider:, event_type:, handler_class:)
        new.find_handler_config(
          provider: provider,
          event_type: event_type,
          handler_class: handler_class
        )
      end

      def handlers_for(provider:, event_type:)
        # First, try to get active handlers from database
        db_handlers = CaptainHook::Handler
          .active
          .for_provider(provider)
          .for_event_type(event_type)
          .by_priority

        if db_handlers.any?
          Rails.logger.info "🔍 [HandlerLookup] Found #{db_handlers.count} active handler(s) in DB for #{provider}:#{event_type}"
          return db_handlers.map { |h| handler_to_config(h, source: :database) }
        end

        # Check if there are soft-deleted handlers for this provider/event_type
        # If yes, respect the deletion and don't fall back to registry
        deleted_handlers = CaptainHook::Handler
          .deleted
          .for_provider(provider)
          .for_event_type(event_type)

        if deleted_handlers.any?
          Rails.logger.info "🗑️  [HandlerLookup] Found #{deleted_handlers.count} deleted handler(s) in DB for #{provider}:#{event_type}, not falling back to registry"
          return []
        end

        # No handlers in DB at all (neither active nor deleted) - fall back to in-memory registry
        registry_handlers = CaptainHook.handler_registry.handlers_for(
          provider: provider,
          event_type: event_type
        )

        # Mark registry configs with source for tracking
        registry_handlers.each do |config|
          config.define_singleton_method(:config_source) { :registry }
        end

        registry_handlers
      end

      def find_handler_config(provider:, event_type:, handler_class:)
        # First, try to find active handler in database
        db_handler = CaptainHook::Handler
                     .active
                     .for_provider(provider)
                     .for_event_type(event_type)
                     .find_by(handler_class: handler_class.to_s)

        if db_handler
          Rails.logger.info "🔍 [HandlerLookup] Found handler #{handler_class} in DB (active)"
          return handler_to_config(db_handler, source: :database)
        end

        # Check if this specific handler was soft-deleted
        # If yes, respect the deletion and don't fall back to registry
        deleted_handler = CaptainHook::Handler
                          .deleted
                          .for_provider(provider)
                          .for_event_type(event_type)
                          .find_by(handler_class: handler_class.to_s)

        if deleted_handler
          Rails.logger.info "🗑️  [HandlerLookup] Handler #{handler_class} is soft-deleted in DB, not falling back to registry"
          return nil
        end

        # Handler doesn't exist in DB at all - fall back to in-memory registry
        Rails.logger.warn "⚠️  [HandlerLookup] Handler #{handler_class} not found in DB, falling back to registry"
        config = CaptainHook.handler_registry.find_handler_config(
          provider: provider,
          event_type: event_type,
          handler_class: handler_class
        )

        config.define_singleton_method(:config_source) { :registry } if config

        config
      end

      private

      # Convert a Handler model to a HandlerRegistry::HandlerConfig struct
      def handler_to_config(handler, source: :database)
        config = CaptainHook::HandlerRegistry::HandlerConfig.new(
          provider: handler.provider,
          event_type: handler.event_type,
          handler_class: handler.handler_class,
          async: handler.async,
          retry_delays: handler.retry_delays,
          max_attempts: handler.max_attempts,
          priority: handler.priority
        )

        # Add metadata about where this config came from
        config.define_singleton_method(:config_source) { source }

        config
      end
    end
  end
end
