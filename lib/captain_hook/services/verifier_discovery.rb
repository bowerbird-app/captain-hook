# frozen_string_literal: true

module CaptainHook
  module Services
    # Service for discovering available webhook verifiers
    # Scans for verifier classes in the CaptainHook::Verifiers namespace
    class VerifierDiscovery < BaseService
      def initialize
        @discovered_verifiers = []
      end

      # Discover all available verifiers
      # Returns array of verifier class names (strings)
      def call
        # Get all verifiers from the CaptainHook::Verifiers namespace
        discover_gem_verifiers
        discover_application_verifiers

        @discovered_verifiers.uniq.sort
      end

      private

      # Discover verifiers bundled with the gem
      def discover_gem_verifiers
        # These are the verifiers that ship with CaptainHook
        gem_verifiers = [
          "CaptainHook::Verifiers::Base",
          "CaptainHook::Verifiers::Stripe",
          "CaptainHook::Verifiers::Square",
          "CaptainHook::Verifiers::Paypal",
          "CaptainHook::Verifiers::WebhookSite"
        ]

        gem_verifiers.each do |verifier_class|
          @discovered_verifiers << verifier_class if verifier_exists?(verifier_class)
        end
      end

      # Discover custom verifiers in the host application
      def discover_application_verifiers
        # Scan for verifier classes in app/verifiers/captain_hook/verifiers/
        app_verifiers_path = Rails.root.join("app", "verifiers", "captain_hook", "verifiers")
        return unless File.directory?(app_verifiers_path)

        Dir.glob(File.join(app_verifiers_path, "*.rb")).each do |file_path|
          verifier_name = File.basename(file_path, ".rb").camelize
          verifier_class = "CaptainHook::Verifiers::#{verifier_name}"

          @discovered_verifiers << verifier_class if verifier_exists?(verifier_class)
        end
      end

      # Check if a verifier class exists and can be instantiated
      def verifier_exists?(verifier_class_name)
        verifier_class_name.constantize
        true
      rescue NameError
        false
      end
    end
  end
end
