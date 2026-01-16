# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for discovering provider configuration files in the application and loaded gems
    # Scans for YAML files in captain_hook/providers/ directories
    class ProviderDiscovery < BaseService
      def initialize
        @discovered_providers = []
      end

      # Scan for provider configuration files
      # Returns array of provider definitions (hashes)
      def call
        scan_application_providers
        scan_gem_providers

        @discovered_providers
      end

      private

      # Scan the main Rails application for provider configs
      def scan_application_providers
        app_providers_path = Rails.root.join("captain_hook", "providers")
        return unless File.directory?(app_providers_path)

        scan_directory(app_providers_path, source: "application")
      end

      # Scan loaded gems for provider configs
      def scan_gem_providers
        # Use Bundler to get all gems from Gemfile, not just loaded ones
        if defined?(Bundler)
          Bundler.load.specs.each do |spec|
            gem_providers_path = File.join(spec.gem_dir, "captain_hook", "providers")
            next unless File.directory?(gem_providers_path)

            scan_directory(gem_providers_path, source: "gem:#{spec.name}")
          end
        else
          # Fallback to Gem.loaded_specs if Bundler isn't available
          Gem.loaded_specs.each_value do |spec|
            gem_providers_path = File.join(spec.gem_dir, "captain_hook", "providers")
            next unless File.directory?(gem_providers_path)

            scan_directory(gem_providers_path, source: "gem:#{spec.name}")
          end
        end
      end

      # Scan a directory for YAML provider configuration files
      # Supports both flat structure (*.yml in providers/) and nested structure (provider_name/provider_name.yml)
      def scan_directory(directory_path, source:)
        # First, scan for any direct YAML files in the providers directory
        Dir.glob(File.join(directory_path, "*.{yml,yaml}")).each do |file_path|
          provider_def = load_provider_file(file_path, source: source)
          @discovered_providers << provider_def if provider_def
        end

        # Then, scan subdirectories for provider-specific YAML files
        Dir.glob(File.join(directory_path, "*")).select { |f| File.directory?(f) }.each do |subdir|
          provider_name = File.basename(subdir)

          # Look for YAML file matching the provider name or any YAML file
          yaml_file = Dir.glob(File.join(subdir, "#{provider_name}.{yml,yaml}")).first ||
                      Dir.glob(File.join(subdir, "*.{yml,yaml}")).first

          next unless yaml_file

          provider_def = load_provider_file(yaml_file, source: source)
          next unless provider_def

          # Autoload the adapter file if it exists
          adapter_file = File.join(subdir, "#{provider_name}.rb")
          if File.exist?(adapter_file)
            begin
              load adapter_file
              Rails.logger.debug("Loaded adapter from #{adapter_file}")
            rescue StandardError => e
              Rails.logger.error("Failed to load adapter #{adapter_file}: #{e.message}")
            end
          end

          @discovered_providers << provider_def
        end
      end

      # Load and parse a provider YAML file
      def load_provider_file(file_path, source:)
        content = File.read(file_path)
        yaml_data = YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false)

        return nil unless yaml_data.is_a?(Hash)

        # Add metadata about where this provider was discovered
        yaml_data.merge(
          "source_file" => file_path,
          "source" => source
        )
      rescue Psych::SyntaxError => e
        Rails.logger.error("Failed to parse provider YAML #{file_path}: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.error("Failed to load provider file #{file_path}: #{e.message}")
        nil
      end
    end
  end
end
