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

        # Scan the adapters directory
        adapter_dir = File.join(CaptainHook::Engine.root, "lib", "captain_hook", "adapters")
        Dir.glob(File.join(adapter_dir, "*.rb")).each do |file|
          adapter_name = File.basename(file, ".rb")
          next if adapter_name == "base" # Skip the base class

          class_name = "CaptainHook::Adapters::#{adapter_name.camelize}"
          display_name = adapter_name.titleize
          adapters << [display_name, class_name]
        end

        # Sort alphabetically and add Base at the end
        adapters.sort_by(&:first) + [["Base (No Verification)", "CaptainHook::Adapters::Base"]]
      end
    end
  end
end
