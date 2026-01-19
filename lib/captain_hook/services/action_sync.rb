# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for syncing discovered actions to the database
    # Creates or updates action records based on ActionRegistry configurations
    # Skips actions that have been soft-deleted
    class ActionSync < BaseService
      def initialize(action_definitions, update_existing: true)
        @action_definitions = action_definitions
        @update_existing = update_existing
        @results = {
          created: [],
          updated: [],
          skipped: [],
          errors: []
        }
      end

      # Sync actions to database
      # Returns hash with results: { created: [...], updated: [...], skipped: [...], errors: [...] }
      def call
        @action_definitions.each do |definition|
          sync_action(definition)
        end

        @results
      end

      private

      def sync_action(definition)
        provider = definition["provider"]
        event_type = definition["event_type"]
        action_class = definition["action_class"]

        unless valid_action_definition?(definition)
          @results[:errors] << {
            action: action_class,
            error: "Invalid action definition"
          }
          return
        end

        # Find existing action by unique key
        action = CaptainHook::Action.find_by(
          provider: provider,
          event_type: event_type,
          action_class: action_class
        )

        # Skip if action was soft-deleted (user manually deleted it)
        if action&.deleted?
          @results[:skipped] << action
          Rails.logger.info("⏭️  Skipped deleted action: #{action_class} for #{provider}:#{event_type}")
          return
        end

        # Track if this is a new record
        is_new = action.nil?

        # Skip updating existing actions if update_existing is false
        if !is_new && !@update_existing
          @results[:skipped] << action
          Rails.logger.info("⏭️  Skipped existing action: #{action_class} for #{provider}:#{event_type} (update_existing=false)")
          return
        end

        action ||= CaptainHook::Action.new(
          provider: provider,
          event_type: event_type,
          action_class: action_class
        )

        # Assign attributes from discovery
        action.async = definition["async"]
        action.max_attempts = definition["max_attempts"]
        action.priority = definition["priority"]
        action.retry_delays = definition["retry_delays"]

        if action.save
          if is_new
            @results[:created] << action
            Rails.logger.info("✅ Created action: #{action_class} for #{provider}:#{event_type}")
          else
            @results[:updated] << action
            Rails.logger.info("🔄 Updated action: #{action_class} for #{provider}:#{event_type}")
          end
        else
          @results[:errors] << {
            action: action_class,
            error: action.errors.full_messages.join(", ")
          }
          Rails.logger.error("❌ Failed to sync action #{action_class}: #{action.errors.full_messages.join(', ')}")
        end
      rescue StandardError => e
        @results[:errors] << { action: action_class, error: e.message }
        Rails.logger.error("❌ Error syncing action #{action_class}: #{e.message}")
      end

      # Validate action definition has required fields
      def valid_action_definition?(definition)
        definition["provider"].present? &&
          definition["event_type"].present? &&
          definition["action_class"].present? &&
          definition["async"].in?([true, false]) &&
          definition["max_attempts"].present? &&
          definition["priority"].present? &&
          definition["retry_delays"].is_a?(Array)
      end
    end
  end
end
