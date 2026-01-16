# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for discovering available webhook adapters
    # Scans for adapter classes in the CaptainHook::Adapters namespace
    class AdapterDiscovery < BaseService
      def initialize
        @discovered_adapters = []
      end

      # Discover all available adapters
      # Returns array of adapter class names (strings)
      def call
        # Get all adapters from the CaptainHook::Adapters namespace
        discover_gem_adapters
        discover_application_adapters

        @discovered_adapters.uniq.sort
      end

      private

      # Discover adapters bundled with the gem
      def discover_gem_adapters
        # These are the adapters that ship with CaptainHook
        gem_adapters = [
          "CaptainHook::Adapters::Base",
          "CaptainHook::Adapters::Stripe",
          "CaptainHook::Adapters::Square",
          "CaptainHook::Adapters::Paypal",
          "CaptainHook::Adapters::WebhookSite"
        ]

        gem_adapters.each do |adapter_class|
          @discovered_adapters << adapter_class if adapter_exists?(adapter_class)
        end
      end

      # Discover custom adapters in the host application
      def discover_application_adapters
        # Scan for adapter classes in app/adapters/captain_hook/adapters/
        app_adapters_path = Rails.root.join("app", "adapters", "captain_hook", "adapters")
        return unless File.directory?(app_adapters_path)

        Dir.glob(File.join(app_adapters_path, "*.rb")).each do |file_path|
          adapter_name = File.basename(file_path, ".rb").camelize
          adapter_class = "CaptainHook::Adapters::#{adapter_name}"

          @discovered_adapters << adapter_class if adapter_exists?(adapter_class)
        end
      end

      # Check if an adapter class exists and can be instantiated
      def adapter_exists?(adapter_class_name)
        adapter_class_name.constantize
        true
      rescue NameError
        false
      end
    end
  end
end
