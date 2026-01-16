# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for managing webhook providers
    class ProvidersController < BaseController
      before_action :set_provider, only: %i[show edit update destroy scan_handlers]

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

      # POST /captain_hook/admin/providers/scan
      def scan
        # Discover providers from YAML files
        discovery = CaptainHook::Services::ProviderDiscovery.new
        provider_definitions = discovery.call

        if provider_definitions.empty?
          redirect_to admin_providers_url,
                      alert: "No provider configuration files found. " \
                             "Add YAML files to captain_hook/providers/ directory."
          return
        end

        # Sync discovered providers to database
        sync = CaptainHook::Services::ProviderSync.new(provider_definitions)
        results = sync.call

        # Also scan and sync handlers
        handler_discovery = CaptainHook::Services::HandlerDiscovery.new
        handler_definitions = handler_discovery.call

        handler_sync = CaptainHook::Services::HandlerSync.new(handler_definitions)
        handler_results = handler_sync.call

        # Build flash message
        messages = []
        messages << "Created #{results[:created].size} provider(s)" if results[:created].any?
        messages << "Updated #{results[:updated].size} provider(s)" if results[:updated].any?
        messages << "Skipped #{results[:skipped].size} provider(s)" if results[:skipped].any?
        messages << "Created #{handler_results[:created].size} handler(s)" if handler_results[:created].any?
        messages << "Updated #{handler_results[:updated].size} handler(s)" if handler_results[:updated].any?
        messages << "Skipped #{handler_results[:skipped].size} deleted handler(s)" if handler_results[:skipped].any?

        all_errors = results[:errors] + handler_results[:errors].map { |e| { name: e[:handler], error: e[:error] } }
        
        # Add warnings as alert if any exist
        if results[:warnings].any?
          warning_messages = results[:warnings].map { |w| "⚠️ #{w[:message]}" }.join("<br>")
          flash[:warning] = warning_messages.html_safe
        end

        if all_errors.any?
          error_details = all_errors.map { |e| "#{e[:name]}: #{e[:error]}" }.join("; ")
          redirect_to admin_providers_url, alert: "Scan completed with errors: #{error_details}"
        elsif messages.any?
          redirect_to admin_providers_url, notice: "Scan completed! #{messages.join(', ')}"
        else
          redirect_to admin_providers_url, notice: "Scan completed. All providers and handlers are up to date."
        end
      end

      # POST /captain_hook/admin/providers/:id/scan_handlers
      def scan_handlers
        # Discover handlers from HandlerRegistry for this provider
        handler_definitions = CaptainHook::Services::HandlerDiscovery.for_provider(@provider.name)

        if handler_definitions.empty?
          redirect_to [:admin, @provider],
                      alert: "No handlers registered for this provider. Register handlers in your application code."
          return
        end

        # Sync discovered handlers to database
        sync = CaptainHook::Services::HandlerSync.new(handler_definitions)
        results = sync.call

        # Build flash message
        messages = []
        messages << "Created #{results[:created].size} handler(s)" if results[:created].any?
        messages << "Updated #{results[:updated].size} handler(s)" if results[:updated].any?
        messages << "Skipped #{results[:skipped].size} deleted handler(s)" if results[:skipped].any?

        if results[:errors].any?
          error_details = results[:errors].map { |e| "#{e[:handler]}: #{e[:error]}" }.join("; ")
          redirect_to [:admin, @provider], alert: "Scan completed with errors: #{error_details}"
        elsif messages.any?
          redirect_to [:admin, @provider], notice: "Handler scan completed! #{messages.join(', ')}"
        else
          redirect_to [:admin, @provider], notice: "Handler scan completed. All handlers are up to date."
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
