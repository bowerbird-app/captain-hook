# frozen_string_literal: true

require "yaml"

module CaptainHook
  # Loads and registers webhook handlers from installed gems
  # Scans for captain_hook_handlers.yml files in gem directories
  class HandlerLoader
    class << self
      # Load handlers from all installed gems
      # Scans each gem for config/captain_hook_handlers.yml
      def load_from_gems
        return unless defined?(Gem)

        loaded_count = 0
        Gem.loaded_specs.each do |gem_name, spec|
          config_path = File.join(spec.gem_dir, "config", "captain_hook_handlers.yml")
          next unless File.exist?(config_path)

          begin
            count = register_handlers_from_file(config_path, gem_name: gem_name)
            loaded_count += count
            Rails.logger.info("CaptainHook: Loaded #{count} handler(s) from #{gem_name}") if defined?(Rails)
          rescue Psych::SyntaxError, YAML::SyntaxError => e
            Rails.logger.error("CaptainHook: Invalid YAML in #{gem_name}: #{e.message}") if defined?(Rails)
          rescue NoMethodError => e
            Rails.logger.error("CaptainHook: Handler registry error in #{gem_name}: #{e.message}") if defined?(Rails)
          rescue StandardError => e
            # Re-raise critical errors like database connection issues
            raise if e.is_a?(ActiveRecord::ConnectionNotEstablished) || e.is_a?(ActiveRecord::NoDatabaseError)
            
            Rails.logger.error("CaptainHook: Failed to load handlers from #{gem_name}: #{e.message}") if defined?(Rails)
          end
        end

        Rails.logger.info("CaptainHook: Total #{loaded_count} handler(s) loaded from gems") if defined?(Rails) && loaded_count.positive?
        loaded_count
      end

      # Register handlers from a YAML configuration file
      # @param path [String] Path to the YAML file
      # @param gem_name [String] Name of the gem providing these handlers
      # @return [Integer] Number of handlers registered
      def register_handlers_from_file(path, gem_name:)
        config = YAML.safe_load_file(path, permitted_classes: [], aliases: true)
        return 0 unless config && config["handlers"]

        handlers = config["handlers"]
        
        # Validate handlers is an array or hash
        unless handlers.is_a?(Array) || handlers.is_a?(Hash)
          Rails.logger.warn("CaptainHook: Invalid handlers format in #{path} from #{gem_name}") if defined?(Rails)
          return 0
        end
        
        handlers = [handlers] unless handlers.is_a?(Array)

        handlers.each do |handler_def|
          register_handler_from_config(handler_def, gem_name: gem_name)
        end

        handlers.size
      end

      # Register a single handler from configuration hash
      # @param handler_def [Hash] Handler definition
      # @param gem_name [String] Name of the gem providing this handler
      def register_handler_from_config(handler_def, gem_name:)
        CaptainHook.register_handler(
          provider: handler_def["provider"],
          event_type: handler_def["event_type"],
          handler_class: handler_def["handler_class"],
          priority: handler_def["priority"] || 100,
          async: handler_def.fetch("async", true),
          max_attempts: handler_def["max_attempts"],
          retry_delays: handler_def["retry_delays"],
          gem_source: gem_name
        )
      rescue ArgumentError => e
        Rails.logger.warn("CaptainHook: Invalid handler configuration in #{gem_name}: #{e.message}") if defined?(Rails)
        raise # Re-raise validation errors
      rescue NoMethodError => e
        Rails.logger.error("CaptainHook: Handler class not found for #{handler_def['handler_class']} from #{gem_name}: #{e.message}") if defined?(Rails)
        nil
      end
    end
  end
end
