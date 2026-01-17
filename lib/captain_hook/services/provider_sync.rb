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

        # Assign attributes from YAML
        provider.display_name = definition["display_name"]
        provider.description = definition["description"]
        provider.adapter_file = definition["adapter_file"]
        provider.active = definition.fetch("active", true)

        # Extract adapter_class from file if adapter_file is provided
        if definition["adapter_file"].present? && (is_new || provider.adapter_class.blank?)
          adapter_class = extract_adapter_class(definition)
          provider.adapter_class = adapter_class if adapter_class.present?
        end

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

        return unless duplicates.any?

        # Only warn once per provider name (not once per source pair)
        return if @warned_duplicates.include?(name)

        @warned_duplicates.add(name)

        # Get all sources for this provider name
        all_sources = @provider_definitions.select { |d| d["name"] == name }.map { |d| d["source"] }

        # Check if there are handlers registered for this provider
        existing_provider = CaptainHook::Provider.find_by(name: name)
        handler_count = existing_provider&.handlers&.count || 0
        handler_info = handler_count > 0 ? " Note: #{handler_count} handler(s) are already registered to the '#{name}' provider." : ""

        warning_message = "Duplicate provider '#{name}' found in multiple sources: #{all_sources.join(', ')}. " \
                          "If using the same webhook URL, just register handlers for the existing provider. " \
                          "If multi-tenant, rename one provider (e.g., '#{name}_primary').#{handler_info}"

        @results[:warnings] << { name: name, message: warning_message, sources: all_sources }

        Rails.logger.warn("⚠️  DUPLICATE PROVIDER DETECTED: '#{name}'")
        Rails.logger.warn("   Found in multiple sources: #{all_sources.join(', ')}")
        Rails.logger.warn("   ")
        Rails.logger.warn("   If you're using the SAME webhook URL:")
        Rails.logger.warn("   → Just register your handlers for the existing '#{name}' provider")
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

      # Extract adapter class name from the adapter file
      def extract_adapter_class(definition)
        name = definition["name"]
        adapter_file = definition["adapter_file"]

        return nil if adapter_file.blank?

        # Find the file in possible locations
        possible_paths = [
          Rails.root.join("captain_hook", "providers", name, adapter_file),
          Rails.root.join("captain_hook", "providers", adapter_file)
        ]

        # Also check in gems
        Bundler.load.specs.each do |spec|
          gem_providers_path = File.join(spec.gem_dir, "captain_hook", "providers")
          next unless File.directory?(gem_providers_path)

          possible_paths << File.join(gem_providers_path, name, adapter_file)
          possible_paths << File.join(gem_providers_path, adapter_file)
        end

        file_path = possible_paths.find { |path| File.exist?(path) }

        if file_path
          CaptainHook::Provider.extract_adapter_class_from_file(file_path)
        else
          Rails.logger.warn("⚠️  Adapter file '#{adapter_file}' not found for provider '#{name}'")
          nil
        end
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
