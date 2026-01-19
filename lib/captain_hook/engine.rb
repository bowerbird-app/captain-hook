# frozen_string_literal: true

module CaptainHook
  class Engine < ::Rails::Engine
    isolate_namespace CaptainHook

    # Run before_initialize hooks
    initializer "captain_hook.before_initialize", before: "captain_hook.load_config" do |_app|
      CaptainHook::Hooks.run(:before_initialize, self)
    end

    initializer "captain_hook.load_config" do |app|
      # Load config/captain_hook.yml via Rails config_for if present
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:captain_hook)
          rescue StandardError
            nil
          end
          CaptainHook.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError => _e
          # ignore load errors; host app can provide initializer overrides
        end
      end

      # Merge Rails.application.config.x.captain_hook if present
      if app.config.respond_to?(:x) && app.config.x.respond_to?(:captain_hook)
        xcfg = app.config.x.captain_hook
        if xcfg.respond_to?(:to_h)
          CaptainHook.configuration.merge!(xcfg.to_h)
        else
          begin
            # try converting OrderedOptions
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            CaptainHook.configuration.merge!(hash) if hash&.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end

      # Run on_configuration hooks after config is loaded
      CaptainHook::Hooks.run(:on_configuration, CaptainHook.configuration)
    end

    # Run after_initialize hooks
    initializer "captain_hook.after_initialize", after: "captain_hook.load_config" do |_app|
      CaptainHook::Hooks.run(:after_initialize, self)
    end

    # Apply model extensions when models are loaded
    initializer "captain_hook.apply_model_extensions" do
      ActiveSupport.on_load(:active_record) do
        # Model extensions are applied when the model class is first accessed
        # via the extend_model hook in configuration
      end
    end

    # Apply controller extensions
    initializer "captain_hook.apply_controller_extensions" do
      ActiveSupport.on_load(:action_controller) do
        # Controller extensions are applied when the controller class is first accessed
        # via the extend_controller hook in configuration
      end
    end

    # Auto-scan providers and actions on boot
    # This runs after all initializers have completed, ensuring action registrations are loaded
    initializer "captain_hook.auto_scan", after: :load_config_initializers do
      config.after_initialize do
        # Only run in server/console contexts, skip for rake tasks and migrations
        next if !defined?(Rails::Console) && File.basename($PROGRAM_NAME) == "rake"

        CaptainHook::Engine.perform_auto_scan
      end
    end

    # Auto-scan providers and actions on Rails boot
    def self.perform_auto_scan
      Rails.logger.info "🔍 CaptainHook: Auto-scanning providers and actions..."

      # Discover and sync providers
      sync_providers

      # Discover and sync actions
      sync_actions

      Rails.logger.info "🎣 CaptainHook: Auto-scan complete"
    end

    def self.sync_providers
      provider_definitions = CaptainHook::Services::ProviderDiscovery.new.call

      if provider_definitions.any?
        Rails.logger.info "🔍 CaptainHook: Found #{provider_definitions.length} provider(s)"

        # Sync providers to database (always overwrite existing with update_existing: true)
        sync = CaptainHook::Services::ProviderSync.new(provider_definitions, update_existing: true)
        results = sync.call

        log_provider_sync_results(results)
      else
        Rails.logger.info "🔍 CaptainHook: No provider YAML files found"
      end
    end

    def self.log_provider_sync_results(results)
      created = results[:created].length
      updated = results[:updated].length
      skipped = results[:skipped].length
      Rails.logger.info "✅ CaptainHook: Synced providers - Created: #{created}, Updated: #{updated}, " \
                        "Skipped: #{skipped}"

      # Log warnings if any
      results[:warnings]&.each do |warning|
        Rails.logger.warn "⚠️  CaptainHook: #{warning[:message]}"
      end

      # Log errors if any
      results[:errors]&.each do |error|
        Rails.logger.error "❌ CaptainHook: #{error[:name]} - #{error[:error]}"
      end
    end

    def self.sync_actions
      action_definitions = CaptainHook::Services::ActionDiscovery.new.call

      if action_definitions.any?
        Rails.logger.info "🔍 CaptainHook: Found #{action_definitions.length} registered action(s)"

        # Sync actions to database (always overwrite existing with update_existing: true)
        action_sync = CaptainHook::Services::ActionSync.new(action_definitions, update_existing: true)
        action_results = action_sync.call

        log_action_sync_results(action_results)
      else
        Rails.logger.info "🔍 CaptainHook: No actions registered"
      end
    end

    def self.log_action_sync_results(action_results)
      created = action_results[:created].length
      updated = action_results[:updated].length
      skipped = action_results[:skipped].length
      Rails.logger.info "✅ CaptainHook: Synced actions - Created: #{created}, Updated: #{updated}, " \
                        "Skipped: #{skipped}"

      # Log errors if any
      action_results[:errors]&.each do |error|
        Rails.logger.error "❌ CaptainHook: Action #{error[:action]} - #{error[:error]}"
      end
    end
  end
end
