# frozen_string_literal: true

module CaptainHook
  module Admin
    # Helper methods for admin views
    module BaseHelper
      # Get available verifier classes for dropdown
      def available_verifier_classes
        # Scan multiple locations for verifiers
        [
          # Application verifiers (Rails app)
          Rails.root.join("app", "verifiers", "captain_hook", "verifiers"),
          # Loaded gems with verifiers
          *Gem.loaded_specs.values.flat_map do |spec|
            [
              File.join(spec.gem_dir, "app", "verifiers", "captain_hook", "verifiers"),
              File.join(spec.gem_dir, "lib", "captain_hook", "verifiers")
            ]
          end
        ]

        # NOTE: Verifiers are now provider-specific and live in captain_hook/<provider>/<provider>.rb
        # This method is kept for backward compatibility but returns empty
        # Providers should specify their verifier_file in their YAML config
        []
      end
    end
  end
end
