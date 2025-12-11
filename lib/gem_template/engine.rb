# frozen_string_literal: true

module GemTemplate
  class Engine < ::Rails::Engine
    isolate_namespace GemTemplate

    # Run before_initialize hooks
    initializer "gem_template.before_initialize", before: "gem_template.load_config" do |_app|
      GemTemplate::Hooks.run(:before_initialize, self)
    end

    initializer "gem_template.load_config" do |app|
      # Load config/gem_template.yml via Rails config_for if present
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:gem_template)
          rescue StandardError
            nil
          end
          GemTemplate.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError => _e
          # ignore load errors; host app can provide initializer overrides
        end
      end

      # Merge Rails.application.config.x.gem_template if present
      if app.config.respond_to?(:x) && app.config.x.respond_to?(:gem_template)
        xcfg = app.config.x.gem_template
        if xcfg.respond_to?(:to_h)
          GemTemplate.configuration.merge!(xcfg.to_h)
        else
          begin
            # try converting OrderedOptions
            hash = {}
            xcfg.each_pair { |k, v| hash[k] = v } if xcfg.respond_to?(:each_pair)
            GemTemplate.configuration.merge!(hash) if hash&.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end

      # Run on_configuration hooks after config is loaded
      GemTemplate::Hooks.run(:on_configuration, GemTemplate.configuration)
    end

    # Run after_initialize hooks
    initializer "gem_template.after_initialize", after: "gem_template.load_config" do |_app|
      GemTemplate::Hooks.run(:after_initialize, self)
    end

    # Apply model extensions when models are loaded
    initializer "gem_template.apply_model_extensions" do
      ActiveSupport.on_load(:active_record) do
        # Model extensions are applied when the model class is first accessed
        # via the extend_model hook in configuration
      end
    end

    # Apply controller extensions
    initializer "gem_template.apply_controller_extensions" do
      ActiveSupport.on_load(:action_controller) do
        # Controller extensions are applied when the controller class is first accessed
        # via the extend_controller hook in configuration
      end
    end
  end
end
