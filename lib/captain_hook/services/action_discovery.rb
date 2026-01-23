# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for discovering actions by scanning the filesystem
    # Scans captain_hook/<provider>/actions directories for action classes
    class ActionDiscovery < BaseService
      def initialize
        @discovered_actions = []
      end

      # Scan the filesystem for all action classes
      # Returns array of action definitions (hashes)
      def call
        scan_filesystem_for_actions
        @discovered_actions
      end

      # Scan actions for a specific provider
      def self.for_provider(provider_name)
        discovery = new
        all_actions = discovery.call
        all_actions.select { |h| h["provider"] == provider_name }
      end

      private

      # Default retry delays for actions (can be overridden in self.details)
      DEFAULT_RETRY_DELAYS = [30, 60, 300, 900, 3600].freeze

      # Scan all load paths for captain_hook/<provider>/actions/**/*.rb files
      def scan_filesystem_for_actions
        action_files = find_action_files

        action_files.each do |file_path|
          process_action_file(file_path)
        end
      end

      # Find all action files in captain_hook/<provider>/actions directories
      def find_action_files
        action_files = []

        # Search in all load paths (includes host app and gems)
        $LOAD_PATH.each do |load_path|
          pattern = File.join(load_path, "captain_hook", "*", "actions", "**", "*.rb")
          action_files.concat(Dir.glob(pattern))
        end

        # Also search in Rails root if available (for host app)
        if defined?(Rails) && Rails.root
          pattern = File.join(Rails.root, "captain_hook", "*", "actions", "**", "*.rb")
          action_files.concat(Dir.glob(pattern))
        end

        # Search in gem root directories (for gems with actions at root level)
        if defined?(Gem)
          Gem.loaded_specs.each do |_, spec|
            pattern = File.join(spec.full_gem_path, "captain_hook", "*", "actions", "**", "*.rb")
            action_files.concat(Dir.glob(pattern))
          end
        end

        action_files.uniq
      end

      # Process a single action file
      def process_action_file(file_path)
        # Extract provider from directory structure
        # e.g., /path/to/captain_hook/stripe/actions/payment_action.rb -> "stripe"
        provider = extract_provider_from_path(file_path)
        return unless provider

        # Detect if this action is from a gem
        gem_name = detect_gem_name(file_path)

        # Load the file
        begin
          require file_path
        rescue LoadError, StandardError => e
          Rails.logger.warn "⚠️  Failed to load action file #{file_path}: #{e.class} - #{e.message}"
          Rails.logger.debug e.backtrace.join("\n") if Rails.logger.debug?
          return
        end

        # Find the action class
        action_class = find_action_class_from_file(file_path, provider)
        return unless action_class

        # Get action details
        details = extract_action_details(action_class)
        return unless details

        # Transform class name for storage (with gem namespace if from a gem)
        stored_class_name = transform_class_name(action_class, gem_name)

        # Build action definition
        @discovered_actions << {
          "provider" => provider,
          "event" => details[:event_type],
          "action" => stored_class_name,
          "async" => details[:async],
          "max_attempts" => details[:max_attempts],
          "priority" => details[:priority],
          "retry_delays" => details[:retry_delays] || DEFAULT_RETRY_DELAYS
        }

        Rails.logger.debug "✅ Discovered action: #{stored_class_name} for #{provider}:#{details[:event_type]}"
      rescue StandardError => e
        Rails.logger.warn "⚠️  Error processing action file #{file_path}: #{e.message}"
      end

      # Extract provider name from file path
      # e.g., /path/to/captain_hook/stripe/actions/file.rb -> "stripe"
      def extract_provider_from_path(file_path)
        match = file_path.match(%r{captain_hook/([^/]+)/actions/})
        match[1] if match
      end

      # Find the action class defined in the file
      # Expects classes to be namespaced like: Stripe::PaymentIntentAction
      def find_action_class_from_file(file_path, provider)
        # Get the file name without extension
        file_basename = File.basename(file_path, ".rb")

        # Convert to class name using ActiveSupport's camelize
        class_name = file_basename.camelize

        # Remove provider prefix if present (e.g., StripePaymentIntentAction -> PaymentIntentAction)
        provider_prefix = provider.camelize
        class_name = class_name.sub(/^#{provider_prefix}/, "")

        # Try to find the class in the provider module
        provider_module_name = provider.camelize

        begin
          provider_module = Object.const_get(provider_module_name)
          provider_module.const_get(class_name)
        rescue NameError => e
          Rails.logger.warn "⚠️  Could not find class #{provider_module_name}::#{class_name} for file #{file_path}"
          Rails.logger.warn "    Make sure the class is namespaced correctly:"
          Rails.logger.warn "    module #{provider_module_name}; class #{class_name}; end; end"
          nil
        end
      end

      # Extract action details from the class
      def extract_action_details(action_class)
        unless action_class.respond_to?(:details)
          Rails.logger.warn "⚠️  Action class #{action_class} does not have a .details class method"
          Rails.logger.warn "    Add: def self.details; { event_type: 'your.event', priority: 100, async: true, max_attempts: 5 }; end"
          return nil
        end

        details = action_class.details

        # Validate required fields
        unless details[:event_type].present?
          Rails.logger.warn "⚠️  Action class #{action_class} details missing :event_type"
          Rails.logger.warn "    The details hash must include: { event_type: 'your.event.type', ... }"
          return nil
        end

        # Provide defaults
        {
          event_type: details[:event_type],
          description: details[:description],
          priority: details[:priority] || 100,
          async: details.key?(:async) ? details[:async] : true,
          max_attempts: details[:max_attempts] || 5,
          retry_delays: details[:retry_delays]
        }
      end

      # Detect if action file is from a gem and return the gem name
      # Returns nil if from host application
      def detect_gem_name(file_path)
        return nil unless defined?(Gem)

        # If the file is in Rails.root, it's from the host application
        return nil if defined?(Rails) && Rails.root && file_path.start_with?(Rails.root.to_s)

        Gem.loaded_specs.each do |gem_name, spec|
          next unless file_path.start_with?(spec.full_gem_path)
          # Skip if this is the captain_hook gem itself (don't namespace its own actions)
          next if gem_name == "captain_hook"

          # Convert gem name to module name (e.g., marikit_country_list -> MarikitCountryList)
          return gem_name.camelize
        end

        nil
      end

      # Transform class name for storage
      # For unique identification when multiple gems provide same action:
      # From host app: Stripe::PaymentIntentAction -> Stripe::PaymentIntentAction
      # From gem: Stripe::PaymentIntentAction -> MarikitCountryList::Stripe::PaymentIntentAction
      def transform_class_name(action_class, gem_name = nil)
        class_name = action_class.to_s

        # Remove CaptainHook:: prefix if present (from gems)
        class_name = class_name.sub(/^CaptainHook::/, "")

        # Remove ::Actions:: if present
        class_name = class_name.sub("::Actions::", "::")

        # Prepend gem namespace for unique identification
        class_name = "#{gem_name}::#{class_name}" if gem_name.present?

        class_name
      end

      # Resolve the actual action class from stored namespaced name
      # Input: "MarikitCountryList::Stripe::PaymentIntentSucceededAction"
      # Output: Stripe::PaymentIntentSucceededAction (the actual Ruby constant)
      # Also ensures the gem's action file is loaded
      def self.resolve_action_class(stored_class_name)
        # Check if this has a gem prefix (format: GemName::Provider::ActionName)
        parts = stored_class_name.split("::")

        if parts.length >= 3
          # Try to match against known gems
          potential_gem_name = parts[0]
          actual_class_name = parts[1..-1].join("::")

          if defined?(Gem)
            gem_spec = Gem.loaded_specs.find { |name, _| name.camelize == potential_gem_name }

            if gem_spec
              # This is from a gem, make sure the file is loaded
              gem_name, spec = gem_spec
              provider = parts[1].underscore
              action_file_pattern = File.join(spec.full_gem_path, "captain_hook", provider, "actions", "**", "*.rb")
              action_files = Dir.glob(action_file_pattern)

              # Load all action files from this gem to ensure the class is defined
              action_files.each do |file|
                require file
              rescue StandardError
                nil
              end

              # Return the actual class name (without gem prefix)
              return actual_class_name
            end
          end
        end

        # No gem prefix or gem not found - use as-is
        stored_class_name
      end
    end
  end
end
