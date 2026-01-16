# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for viewing and managing handlers per provider
    class HandlersController < BaseController
      before_action :set_provider
      before_action :set_handler, only: %i[show edit update destroy]

      # GET /captain_hook/admin/providers/:provider_id/handlers
      def index
        # Get handlers from database for this provider
        @db_handlers = CaptainHook::Handler.active.for_provider(@provider.name).by_priority

        # Also get handlers from registry for comparison
        @registry_handlers = handler_registry_for_provider
      end

      # GET /captain_hook/admin/providers/:provider_id/handlers/:id
      def show; end

      # GET /captain_hook/admin/providers/:provider_id/handlers/:id/edit
      def edit; end

      # PATCH/PUT /captain_hook/admin/providers/:provider_id/handlers/:id
      def update
        if @handler.update(handler_params)
          redirect_to admin_provider_handlers_path(@provider),
                      notice: "Handler was successfully updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # DELETE /captain_hook/admin/providers/:provider_id/handlers/:id
      def destroy
        @handler.soft_delete!
        redirect_to admin_provider_handlers_path(@provider),
                    notice: "Handler was successfully deleted. It will be skipped during future scans."
      end

      private

      def set_provider
        @provider = CaptainHook::Provider.find(params[:provider_id])
      end

      def set_handler
        @handler = CaptainHook::Handler.find(params[:id])
      end

      def handler_params
        permitted = params.require(:handler).permit(
          :event_type, :async, :max_attempts, :priority, :retry_delays
        )

        # Parse retry_delays if it's a JSON string
        if permitted[:retry_delays].is_a?(String)
          begin
            permitted[:retry_delays] = JSON.parse(permitted[:retry_delays])
          rescue JSON::ParserError
            # If not JSON, try parsing as comma-separated values
            permitted[:retry_delays] = permitted[:retry_delays].split(",").map(&:strip).map(&:to_i).reject(&:zero?)
          end
        end

        permitted
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
