# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for managing webhook providers
    class ProvidersController < BaseController
      before_action :set_provider, only: %i[show edit update destroy]

      # GET /captain_hook/admin/providers
      def index
        # Load providers from registry
        discovery = CaptainHook::Services::ProviderDiscovery.new
        provider_definitions = discovery.call

        # Convert to ProviderConfig objects
        @providers = provider_definitions.map do |config_data|
          CaptainHook::ProviderConfig.new(config_data)
        end.sort_by(&:name)

        # Get database providers for status
        @db_providers = CaptainHook::Provider.all.index_by(&:name)
      end

      # GET /captain_hook/admin/providers/:id
      def show
        @recent_events = @provider.incoming_events.recent.limit(10)

        # Load registry config for this provider (with hierarchy applied)
        discovery = CaptainHook::Services::ProviderDiscovery.new
        provider_definitions = discovery.call
        config_data = provider_definitions.find { |p| p["name"] == @provider.name }
        @registry_config = config_data ? CaptainHook::ProviderConfig.new(config_data) : nil

        # Load raw provider YAML (before hierarchy)
        @provider_yaml = config_data

        # Load global config
        return unless defined?(CaptainHook::Services::GlobalConfigLoader)

        config_loader = CaptainHook::Services::GlobalConfigLoader.new
        @global_config = config_loader.call
      end

      # GET /captain_hook/admin/providers/new
      def new
        @provider = CaptainHook::Provider.new
      end

      # GET /captain_hook/admin/providers/:id/edit
      def edit; end

      # POST /captain_hook/admin/providers
      def create
        @provider = CaptainHook::Provider.new(provider_params)

        if @provider.save
          redirect_to [:admin, @provider], notice: "Provider was successfully created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /captain_hook/admin/providers/:id
      def update
        if @provider.update(provider_params)
          redirect_to [:admin, @provider], notice: "Provider was successfully updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      # DELETE /captain_hook/admin/providers/:id
      def destroy
        if @provider.incoming_events.any?
          redirect_to [:admin, @provider], alert: "Cannot delete provider with associated events."
        else
          @provider.destroy
          redirect_to admin_providers_url, notice: "Provider was successfully deleted."
        end
      end

      private

      def set_provider
        @provider = CaptainHook::Provider.find(params[:id])
      end

      def provider_params
        params.require(:provider).permit(
          :name, :display_name, :description, :signing_secret,
          :verifier_class, :timestamp_tolerance_seconds, :max_payload_size_bytes,
          :rate_limit_requests, :rate_limit_period, :active
        )
      end
    end
  end
end
