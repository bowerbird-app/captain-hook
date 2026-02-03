# frozen_string_literal: true

module CaptainHook
  module Admin
    # Helper methods for admin views
    module BaseHelper
      def status_color(status)
        case status&.to_s
        when "pending"
          "yellow"
        when "processing"
          "blue"
        when "completed", "sent"
          "green"
        when "failed"
          "red"
        else
          "gray"
        end
      end

      # Render a simple badge with Tailwind classes
      def badge(text, color: "gray", **options)
        color_classes = case color.to_s
                        when "green"
                          "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
                        when "red"
                          "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
                        when "blue"
                          "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"
                        when "yellow"
                          "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"
                        else
                          "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
                        end

        css_class = [
          "inline-flex items-center px-2 py-1 text-xs font-medium rounded",
          color_classes,
          options[:class]
        ].compact.join(" ")

        content_tag(:span, text, class: css_class, **options.except(:class))
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
