# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for syncing discovered providers to the database
    # Creates or updates provider records based on YAML definitions
    class ProviderSync < BaseService
      def initialize(provider_definitions)
        @provider_definitions = provider_definitions
        @results = {
          created: [],
          updated: [],
          skipped: [],
          errors: [],
          warnings: []
        }
      end

      # Sync providers to database
      # Returns hash with results: { created: [...], updated: [...], skipped: [...], errors: [...] }
      def call
        @provider_definitions.each do |definition|
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

        # Assign attributes from YAML
        provider.display_name = definition["display_name"]
        provider.description = definition["description"]
        provider.adapter_class = definition["adapter_class"]
        provider.active = definition.fetch("active", true)

        # Optional attributes
        provider.timestamp_tolerance_seconds = definition["timestamp_tolerance_seconds"]
        provider.max_payload_size_bytes = definition["max_payload_size_bytes"]
        provider.rate_limit_requests = definition["rate_limit_requests"]
        provider.rate_limit_period = definition["rate_limit_period"]

        # Handle signing secret with ENV variable support
        if definition["signing_secret"].present?
          signing_secret = resolve_signing_secret(definition["signing_secret"])

          # Only update signing secret if:
          # 1. It's a new record, OR
          # 2. The resolved secret is different from current (and not nil)
          if is_new || (signing_secret.present? && signing_secret != provider.signing_secret)
            provider.signing_secret = signing_secret
          end
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

        if duplicates.any?
          duplicate_sources = duplicates.map { |d| d["source"] }.join(", ")
          warning_message = "Duplicate provider '#{name}' found in #{source} (already exists in: #{duplicate_sources}). " \
                           "If using the same webhook URL, just register handlers for the existing provider. " \
                           "If multi-tenant, rename one provider (e.g., '#{name}_primary')."
          
          @results[:warnings] << { name: name, message: warning_message }
          
          Rails.logger.warn("⚠️  DUPLICATE PROVIDER DETECTED: '#{name}'")
          Rails.logger.warn("   Found in: #{source}")
          Rails.logger.warn("   Already exists in: #{duplicate_sources}")
          Rails.logger.warn("   ")
          Rails.logger.warn("   If you're using the SAME webhook URL:")
          Rails.logger.warn("   → Just register your handlers for the existing '#{name}' provider")
          Rails.logger.warn("   → Remove the duplicate provider configuration")
          Rails.logger.warn("   ")
          Rails.logger.warn("   If you need DIFFERENT webhook URLs (multi-tenant):")
          Rails.logger.warn("   → Rename one provider (e.g., '#{name}_primary' and '#{name}_secondary')")
          Rails.logger.warn("   → Each provider gets its own webhook endpoint and secret")
        end
      end

      # Validate provider definition has required fields
      def valid_provider_definition?(definition)
        definition["name"].present? &&
          definition["adapter_class"].present?
      end

      # Resolve signing secret from ENV variable reference or direct value
      # Supports format: ENV[VARIABLE_NAME] or direct value
      def resolve_signing_secret(secret_value)
        return nil if secret_value.blank?

        # Check if it's an ENV variable reference
        if secret_value.is_a?(String) && secret_value.match?(/\AENV\[([^\]]+)\]\z/)
          env_var = secret_value.match(/\AENV\[([^\]]+)\]\z/)[1]
          ENV.fetch(env_var, nil)
        else
          secret_value
        end
      end
    end
  end
end
