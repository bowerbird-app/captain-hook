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

    # Auto-load providers and handlers from gems
    initializer "captain_hook.load_gem_configurations", after: :load_config_initializers do
      Rails.application.config.after_initialize do
        # Auto-load providers from all gems
        CaptainHook::ProviderLoader.load_from_gems

        # Auto-load handlers from all gems
        CaptainHook::HandlerLoader.load_from_gems
      end
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
  end
end
