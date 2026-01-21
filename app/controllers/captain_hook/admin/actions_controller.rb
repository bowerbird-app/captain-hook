# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for viewing and managing actions per provider
    class ActionsController < BaseController
      before_action :set_provider
      before_action :set_action, only: %i[show edit update destroy]

      # GET /captain_hook/admin/providers/:provider_id/actions
      def index
        # Get actions from database for this provider
        @db_actions = CaptainHook::Action.active.for_provider(@provider.name).by_priority

        # Also get actions from registry for comparison
        @registry_actions = action_registry_for_provider

        # Load registry config for display_name
        discovery = CaptainHook::Services::ProviderDiscovery.new
        provider_definitions = discovery.call
        config_data = provider_definitions.find { |p| p["name"] == @provider.name }
        @registry_config = config_data ? CaptainHook::ProviderConfig.new(config_data) : nil
      end

      # GET /captain_hook/admin/providers/:provider_id/actions/:id
      def show; end

      # GET /captain_hook/admin/providers/:provider_id/actions/:id/edit
      def edit; end

      # PATCH/PUT /captain_hook/admin/providers/:provider_id/actions/:id
      def update
        if @action.update(action_params)
          redirect_to admin_provider_actions_path(@provider),
                      notice: "Action was successfully updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # DELETE /captain_hook/admin/providers/:provider_id/actions/:id
      def destroy
        @action.soft_delete!
        redirect_to admin_provider_actions_path(@provider),
                    notice: "Action was successfully deleted. It will be skipped during future scans."
      end

      private

      def set_provider
        @provider = CaptainHook::Provider.find(params[:provider_id])
        # Load registry config for display_name
        @registry_config = CaptainHook.configuration.provider(@provider.name)
      end

      def set_action
        @action = CaptainHook::Action.find(params[:id])
      end

      def action_params
        permitted = params.require(:captain_hook_action).permit(
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

      def action_registry_for_provider
        # Get all registered actions from the action registry for this provider
        registry = CaptainHook.action_registry

        # Group actions by event_type
        actions_hash = {}

        # The registry stores actions by "provider:event_type" keys
        # We need to extract all actions for this provider
        registry.instance_variable_get(:@registry).each do |key, configs|
          provider_name, event_type = key.split(":", 2)
          next unless provider_name == @provider.name

          actions_hash[event_type] ||= []
          actions_hash[event_type].concat(configs)
        end

        actions_hash
      end
    end
  end
end
