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
    end
  end
end
