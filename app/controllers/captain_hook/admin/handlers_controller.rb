# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for viewing handlers per provider
    class HandlersController < BaseController
      before_action :set_provider

      # GET /captain_hook/admin/providers/:provider_id/handlers
      def index
        @handlers = handler_registry_for_provider
      end

      private

      def set_provider
        @provider = CaptainHook::Provider.find(params[:provider_id])
      end

      def handler_registry_for_provider
        # Get all registered handlers from the handler registry for this provider
        registry = CaptainHook.handler_registry
        
        # Group handlers by event_type
        handlers_hash = {}
        
        # The registry stores handlers by "provider:event_type" keys
        # We need to extract all handlers for this provider
        registry.instance_variable_get(:@registry).each do |key, configs|
          provider_name, event_type = key.split(":", 2)
          next unless provider_name == @provider.name
          
          handlers_hash[event_type] ||= []
          handlers_hash[event_type].concat(configs)
        end
        
        handlers_hash
      end
    end
  end
end
