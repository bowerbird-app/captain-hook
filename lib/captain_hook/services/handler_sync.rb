# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for syncing discovered handlers to the database
    # Creates or updates handler records based on HandlerRegistry configurations
    # Skips handlers that have been soft-deleted
    class HandlerSync < BaseService
      def initialize(handler_definitions)
        @handler_definitions = handler_definitions
        @results = {
          created: [],
          updated: [],
          skipped: [],
          errors: []
        }
      end

      # Sync handlers to database
      # Returns hash with results: { created: [...], updated: [...], skipped: [...], errors: [...] }
      def call
        @handler_definitions.each do |definition|
          sync_handler(definition)
        end

        @results
      end

      private

      def sync_handler(definition)
        provider = definition["provider"]
        event_type = definition["event_type"]
        handler_class = definition["handler_class"]

        unless valid_handler_definition?(definition)
          @results[:errors] << { 
            handler: handler_class, 
            error: "Invalid handler definition" 
          }
          return
        end

        # Find existing handler by unique key
        handler = CaptainHook::Handler.find_by(
          provider: provider,
          event_type: event_type,
          handler_class: handler_class
        )

        # Skip if handler was soft-deleted (user manually deleted it)
        if handler&.deleted?
          @results[:skipped] << handler
          Rails.logger.info("⏭️  Skipped deleted handler: #{handler_class} for #{provider}:#{event_type}")
          return
        end

        # Track if this is a new record
        is_new = handler.nil?
        handler ||= CaptainHook::Handler.new(
          provider: provider,
          event_type: event_type,
          handler_class: handler_class
        )

        # Assign attributes from discovery
        handler.async = definition["async"]
        handler.max_attempts = definition["max_attempts"]
        handler.priority = definition["priority"]
        handler.retry_delays = definition["retry_delays"]

        if handler.save
          if is_new
            @results[:created] << handler
            Rails.logger.info("✅ Created handler: #{handler_class} for #{provider}:#{event_type}")
          else
            @results[:updated] << handler
            Rails.logger.info("🔄 Updated handler: #{handler_class} for #{provider}:#{event_type}")
          end
        else
          @results[:errors] << { 
            handler: handler_class, 
            error: handler.errors.full_messages.join(", ") 
          }
          Rails.logger.error("❌ Failed to sync handler #{handler_class}: #{handler.errors.full_messages.join(', ')}")
        end
      rescue StandardError => e
        @results[:errors] << { handler: handler_class, error: e.message }
        Rails.logger.error("❌ Error syncing handler #{handler_class}: #{e.message}")
      end

      # Validate handler definition has required fields
      def valid_handler_definition?(definition)
        definition["provider"].present? &&
          definition["event_type"].present? &&
          definition["handler_class"].present? &&
          definition["async"].in?([true, false]) &&
          definition["max_attempts"].present? &&
          definition["priority"].present? &&
          definition["retry_delays"].is_a?(Array)
      end
    end
  end
end
