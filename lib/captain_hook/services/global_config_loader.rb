# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for loading global CaptainHook configuration from captain_hook.yml
    # Provides defaults and per-provider overrides
    class GlobalConfigLoader < BaseService
      def initialize(config_path = nil)
        @config_path = config_path || Rails.root.join("config", "captain_hook.yml")
        @config = {}
      end

      # Load configuration from YAML file
      # Returns hash with global defaults and per-provider overrides
      def call
        load_config_file
        @config
      end

      # Get global default for a setting
      def self.global_default(key)
        instance = new
        config = instance.call
        config.dig("defaults", key.to_s)
      end

      # Get provider-specific setting with fallback to global default
      def self.provider_setting(provider_name, key)
        instance = new
        config = instance.call
        
        # Check provider-specific override first
        provider_override = config.dig("providers", provider_name.to_s, key.to_s)
        return provider_override if provider_override.present?

        # Fall back to global default
        config.dig("defaults", key.to_s)
      end

      private

      def load_config_file
        unless File.exist?(@config_path)
          # Return default config if file doesn't exist
          @config = default_config
          return
        end

        begin
          yaml_data = YAML.safe_load_file(@config_path, permitted_classes: [], permitted_symbols: [], aliases: false)
          @config = yaml_data.is_a?(Hash) ? yaml_data : default_config
        rescue Psych::SyntaxError => e
          Rails.logger.error("Failed to parse captain_hook.yml: #{e.message}")
          @config = default_config
        rescue StandardError => e
          Rails.logger.error("Failed to load captain_hook.yml: #{e.message}")
          @config = default_config
        end
      end

      # Default configuration if no file exists
      def default_config
        {
          "defaults" => {
            "max_payload_size_bytes" => 1_048_576, # 1MB
            "timestamp_tolerance_seconds" => 300    # 5 minutes
          },
          "providers" => {}
        }
      end
    end
  end
end
