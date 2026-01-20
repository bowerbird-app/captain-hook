# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for syncing discovered providers to the database
    # Creates or updates provider records based on YAML definitions
    class ProviderSync < BaseService
      def initialize(provider_definitions, update_existing: true)
        @provider_definitions = provider_definitions
        @update_existing = update_existing
        @results = {
          created: [],
          updated: [],
          skipped: [],
          errors: [],
          warnings: []
        }
        @warned_duplicates = Set.new # Track which duplicate pairs we've already warned about
      end

      # Sync providers to database
      # Returns hash with results: { created: [...], updated: [...], skipped: [...], errors: [...] }
      def call
        # Deduplicate providers by name - only sync each provider once
        # Keep the first occurrence (application takes precedence over gems)
        unique_providers = @provider_definitions.uniq { |p| p["name"] }

        unique_providers.each do |definition|
          sync_provider(definition)
        end

        @results
      end

      private

      def sync_provider(definition)
        name = definition["name"]

        unless valid_provider_definition?(definition)
          @results[:errors] << { name: name, error: "Invalid provider definition" }
          return
        end

        # Check for duplicate provider definitions from different sources
        check_for_duplicate_provider(definition)

        provider = CaptainHook::Provider.find_or_initialize_by(name: name)

        # Track if this is a new record
        is_new = provider.new_record?

        # Skip updating existing providers if update_existing is false
        if !is_new && !@update_existing
          @results[:skipped] << provider
          Rails.logger.info("⏭️  Skipped existing provider: #{name} (update_existing=false)")
          return
        end

        # Only sync database-managed fields: active, rate_limit_requests, rate_limit_period
        # Note: token is auto-generated if blank via before_validation callback
        
        # For new providers, set defaults
        # For existing providers, only update if YAML explicitly specifies a value (preserve manual DB changes)
        if is_new
          # Set defaults for new providers
          provider.active = definition.fetch("active", true)
          provider.rate_limit_requests = definition.fetch("rate_limit_requests", 100)
          provider.rate_limit_period = definition.fetch("rate_limit_period", 60)
        else
          # For existing providers, only update if explicitly set in YAML (preserve manual changes)
          provider.active = definition["active"] if definition.key?("active")
          provider.rate_limit_requests = definition["rate_limit_requests"] if definition.key?("rate_limit_requests")
          provider.rate_limit_period = definition["rate_limit_period"] if definition.key?("rate_limit_period")
        end

        if provider.save
          if is_new
            @results[:created] << provider
            Rails.logger.info("✅ Created provider: #{name} (from #{definition['source']})")
          else
            @results[:updated] << provider
            Rails.logger.info("🔄 Updated provider: #{name} (from #{definition['source']})")
          end
        else
          @results[:errors] << { name: name, error: provider.errors.full_messages.join(", ") }
          Rails.logger.error("❌ Failed to sync provider #{name}: #{provider.errors.full_messages.join(', ')}")
        end
      rescue StandardError => e
        @results[:errors] << { name: name, error: e.message }
        Rails.logger.error("❌ Error syncing provider #{name}: #{e.message}")
      end

      # Check for duplicate provider definitions from different sources
      def check_for_duplicate_provider(definition)
        name = definition["name"]
        source = definition["source"]

        # Find other definitions with the same name from different sources
        duplicates = @provider_definitions.select do |d|
          d["name"] == name && d["source"] != source
        end

        return unless duplicates.any?

        # Only warn once per provider name (not once per source pair)
        return if @warned_duplicates.include?(name)

        @warned_duplicates.add(name)

        # Get all sources for this provider name
        all_sources = @provider_definitions.select { |d| d["name"] == name }.map { |d| d["source"] }

        # Check if there are actions registered for this provider
        existing_provider = CaptainHook::Provider.find_by(name: name)
        action_count = existing_provider&.actions&.count || 0
        action_info = action_count.positive? ? " Note: #{action_count} action(s) are already registered to the '#{name}' provider." : ""

        warning_message = "Duplicate provider '#{name}' found in multiple sources: #{all_sources.join(', ')}. " \
                          "If using the same webhook URL, just register actions for the existing provider. " \
                          "If multi-tenant, rename one provider (e.g., '#{name}_primary').#{action_info}"

        @results[:warnings] << { name: name, message: warning_message, sources: all_sources }

        Rails.logger.warn("⚠️  DUPLICATE PROVIDER DETECTED: '#{name}'")
        Rails.logger.warn("   Found in multiple sources: #{all_sources.join(', ')}")
        Rails.logger.warn("   ")
        Rails.logger.warn("   If you're using the SAME webhook URL:")
        Rails.logger.warn("   → Just register your actions for the existing '#{name}' provider")
        Rails.logger.warn("   → Remove the duplicate provider configuration")
        Rails.logger.warn("   ")
        Rails.logger.warn("   If you need DIFFERENT webhook URLs (multi-tenant):")
        Rails.logger.warn("   → Rename one provider (e.g., '#{name}_primary' and '#{name}_secondary')")
        Rails.logger.warn("   → Each provider gets its own webhook endpoint and secret")
      end

      # Validate provider definition has required fields
      def valid_provider_definition?(definition)
        definition["name"].present?
      end
    end
  end
end
