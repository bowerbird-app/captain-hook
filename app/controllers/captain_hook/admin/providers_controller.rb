# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for managing webhook providers
    class ProvidersController < BaseController
      before_action :set_provider, only: %i[show edit update destroy scan_actions]

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

      # POST /captain_hook/admin/providers/sync_all
      # Full sync - updates existing providers/handlers from YAML
      def sync_all
        perform_scan(update_existing: true, scan_type: "Full Sync")
      end

      # POST /captain_hook/admin/providers/discover_new
      # Discovery only - adds new providers/handlers, skips existing ones
      def discover_new
        perform_scan(update_existing: false, scan_type: "Discovery")
      end

      # POST /captain_hook/admin/providers/:id/scan_actions
      def scan_actions
        # Discover actions from ActionRegistry for this provider
        action_definitions = CaptainHook::Services::ActionDiscovery.for_provider(@provider.name)

        if action_definitions.empty?
          redirect_to [:admin, @provider],
                      alert: "No actions registered for this provider. Register actions in your application code."
          return
        end

        # Sync actions to database
        sync = CaptainHook::Services::ActionSync.new(action_definitions)
        results = sync.call

        messages = []
        messages << "Created #{results[:created].size} action(s)" if results[:created].any?
        messages << "Updated #{results[:updated].size} action(s)" if results[:updated].any?
        messages << "Skipped #{results[:skipped].size} deleted action(s)" if results[:skipped].any?

        all_errors = results[:errors]

        if all_errors.any?
          error_details = all_errors.map { |e| "#{e[:action]}: #{e[:error]}" }.join("; ")
          redirect_to [:admin, @provider], alert: "Action sync completed with errors: #{error_details}"
        elsif messages.any?
          redirect_to [:admin, @provider], notice: "Action sync completed! #{messages.join(', ')}"
        else
          redirect_to [:admin, @provider], notice: "All actions are up to date."
        end
      end

      private

      def perform_scan(update_existing:, scan_type:)
        # Discover providers from YAML files
        discovery = CaptainHook::Services::ProviderDiscovery.new
        provider_definitions = discovery.call

        Rails.logger.info "🔍 #{scan_type.upcase}: Found #{provider_definitions.length} providers"
        provider_definitions.each do |p|
          Rails.logger.info "   - #{p['name']} (source: #{p['source']})"
        end

        if provider_definitions.empty?
          redirect_to admin_providers_url,
                      alert: "No provider configuration files found. " \
                             "Add YAML files to captain_hook/<provider>/<provider>.yml directories."
          return
        end

        # Sync discovered providers to database
        sync = CaptainHook::Services::ProviderSync.new(provider_definitions, update_existing: update_existing)
        results = sync.call

        Rails.logger.info "🔍 #{scan_type.upcase} RESULTS: Created: #{results[:created].length}, Updated: #{results[:updated].length}, Skipped: #{results[:skipped].length}, Warnings: #{results[:warnings]&.length || 0}"
        if results[:warnings]&.any?
          results[:warnings].each do |w|
            Rails.logger.info "   ⚠️  #{w[:name]}: #{w[:message][0..100]}"
          end
        end

        # Also scan and sync actions
        action_discovery = CaptainHook::Services::ActionDiscovery.new
        action_definitions = action_discovery.call

        action_sync = CaptainHook::Services::ActionSync.new(action_definitions, update_existing: update_existing)
        action_results = action_sync.call

        # Update warnings with action counts now that actions are synced
        if results[:warnings]&.any?
          results[:warnings].each do |warning|
            provider = CaptainHook::Provider.find_by(name: warning[:name])
            action_count = provider&.actions&.count || 0
            next unless action_count > 0

            warning[:message] =
              warning[:message].sub(". If using",
                                    ". Note: #{action_count} action(s) are now registered to the '#{warning[:name]}' provider. If using")
          end
        end

        # Build flash message
        messages = []
        messages << "Created #{results[:created].size} provider(s)" if results[:created].any?
        messages << "Updated #{results[:updated].size} provider(s)" if results[:updated].any?
        messages << "Skipped #{results[:skipped].size} provider(s)" if results[:skipped].any?
        messages << "Created #{action_results[:created].size} action(s)" if action_results[:created].any?
        messages << "Updated #{action_results[:updated].size} action(s)" if action_results[:updated].any?
        messages << "Skipped #{action_results[:skipped].size} action(s)" if action_results[:skipped].any?

        all_errors = results[:errors] + action_results[:errors].map { |e| { name: e[:action], error: e[:error] } }

        if all_errors.any?
          error_details = all_errors.map { |e| "#{e[:name]}: #{e[:error]}" }.join("; ")
          redirect_to admin_providers_url, alert: "#{scan_type} completed with errors: #{error_details}"
        elsif messages.any?
          # Add warnings as alert if any exist
          if results[:warnings]&.any?
            warning_messages = results[:warnings].map { |w| "⚠️ #{w[:message]}" }.join("\n\n")
            flash[:warning] = warning_messages
          end
          redirect_to admin_providers_url, notice: "#{scan_type} completed! #{messages.join(', ')}"
        else
          # Add warnings as alert if any exist
          if results[:warnings]&.any?
            warning_messages = results[:warnings].map { |w| "⚠️ #{w[:message]}" }.join("\n\n")
            flash[:warning] = warning_messages
          end
          redirect_to admin_providers_url, notice: "Scan completed. All providers and actions are up to date."
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
