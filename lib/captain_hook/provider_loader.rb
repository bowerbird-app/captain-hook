# frozen_string_literal: true

module CaptainHook
  # Loads and registers webhook providers from installed gems
  # Scans for captain_hook_providers.yml files in gem directories
  class ProviderLoader
    class << self
      # Load providers from all installed gems
      # Scans each gem for config/captain_hook_providers.yml
      def load_from_gems
        return unless defined?(Gem)

        loaded_count = 0
        Gem.loaded_specs.each do |gem_name, spec|
          config_path = File.join(spec.gem_dir, "config", "captain_hook_providers.yml")
          next unless File.exist?(config_path)

          begin
            count = register_providers_from_file(config_path, gem_name: gem_name)
            loaded_count += count
            Rails.logger.info("CaptainHook: Loaded #{count} provider(s) from #{gem_name}") if defined?(Rails)
          rescue StandardError => e
            Rails.logger.error("CaptainHook: Failed to load providers from #{gem_name}: #{e.message}") if defined?(Rails)
          end
        end

        Rails.logger.info("CaptainHook: Total #{loaded_count} provider(s) loaded from gems") if defined?(Rails) && loaded_count.positive?
        loaded_count
      end

      # Register providers from a YAML configuration file
      # @param path [String] Path to the YAML file
      # @param gem_name [String] Name of the gem providing these providers
      # @return [Integer] Number of providers registered
      def register_providers_from_file(path, gem_name:)
        config = YAML.load_file(path)
        return 0 unless config && config["providers"]

        providers = config["providers"]
        providers = [providers] unless providers.is_a?(Array)

        providers.each do |provider_def|
          register_provider_from_config(provider_def, gem_name: gem_name)
        end

        providers.size
      end

      # Register a single provider from configuration hash
      # @param provider_def [Hash] Provider definition
      # @param gem_name [String] Name of the gem providing this provider
      def register_provider_from_config(provider_def, gem_name:)
        return unless defined?(CaptainHook::Provider)

        provider = CaptainHook::Provider.find_or_initialize_by(
          name: provider_def["name"],
          gem_source: gem_name
        )

        # Update provider attributes
        provider.display_name = provider_def["display_name"] if provider_def["display_name"]
        provider.description = provider_def["description"] if provider_def["description"]
        provider.adapter_class = provider_def["adapter_class"] if provider_def["adapter_class"]

        # Apply default configuration if provided
        if provider_def["default_config"]
          config = provider_def["default_config"]
          provider.timestamp_tolerance_seconds = config["timestamp_tolerance_seconds"] if config["timestamp_tolerance_seconds"]
          provider.max_payload_size_bytes = config["max_payload_size_bytes"] if config["max_payload_size_bytes"]
          provider.rate_limit_requests = config["rate_limit_requests"] if config["rate_limit_requests"]
          provider.rate_limit_period = config["rate_limit_period"] if config["rate_limit_period"]
        end

        # Mark as active by default for gem-provided providers
        provider.active = true if provider.new_record?

        provider.save!
        provider
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("CaptainHook: Failed to register provider #{provider_def['name']}: #{e.message}") if defined?(Rails)
        nil
      end
    end
  end
end
