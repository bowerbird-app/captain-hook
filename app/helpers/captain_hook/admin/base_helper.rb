# frozen_string_literal: true

module CaptainHook
  module Admin
    # Helper methods for admin views
    module BaseHelper
      def status_color(status)
        case status&.to_s
        when "pending"
          "warning"
        when "processing"
          "info"
        when "completed", "sent"
          "success"
        when "failed"
          "danger"
        else
          "secondary"
        end
      end

      def response_code_color(code)
        return "secondary" unless code

        case code.to_i
        when 200..299
          "success"
        when 300..399
          "info"
        when 400..499
          "warning"
        when 500..599
          "danger"
        else
          "secondary"
        end
      end

      # Get available adapter classes for dropdown
      def available_adapter_classes
        adapters = []

        # Scan multiple locations for adapters
        scan_paths = [
          # Application adapters (Rails app)
          Rails.root.join("app", "adapters", "captain_hook", "adapters"),
          # Loaded gems with adapters
          *Gem.loaded_specs.values.flat_map do |spec|
            [
              File.join(spec.gem_dir, "app", "adapters", "captain_hook", "adapters"),
              File.join(spec.gem_dir, "lib", "captain_hook", "adapters")
            ]
          end
        ]

        # NOTE: Adapters are now provider-specific and live in captain_hook/<provider>/<provider>.rb
        # This method is kept for backward compatibility but returns empty
        # Providers should specify their adapter_file in their YAML config
        []
      end
    end
  end
end
