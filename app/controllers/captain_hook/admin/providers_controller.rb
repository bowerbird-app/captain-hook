# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for managing webhook providers
    class ProvidersController < BaseController
      before_action :set_provider, only: %i[show edit update destroy]

      # GET /captain_hook/admin/providers
      def index
        @providers = CaptainHook::Provider.by_name.page(params[:page]).per(50)
      end

      # GET /captain_hook/admin/providers/:id
      def show
        @recent_events = @provider.incoming_events.recent.limit(10)
      end

      # GET /captain_hook/admin/providers/new
      def new
        @provider = CaptainHook::Provider.new
      end

      # GET /captain_hook/admin/providers/:id/edit
      def edit
      end

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
          :adapter_class, :timestamp_tolerance_seconds, :max_payload_size_bytes,
          :rate_limit_requests, :rate_limit_period, :active
        )
      end
    end
  end
end
