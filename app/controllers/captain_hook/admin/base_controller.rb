# frozen_string_literal: true

module CaptainHook
  module Admin
    # Base controller for admin interface
    # Inherits from configurable parent controller
    class BaseController < ApplicationController
      layout -> { CaptainHook.configuration.admin_layout }

      # Override this in the host application to add authentication
      # before_action :authenticate_admin!

      private

      def authenticate_admin!
        # Implement authentication in host application
        # Example: redirect_to root_path unless current_user&.admin?
      end
    end
  end
end
