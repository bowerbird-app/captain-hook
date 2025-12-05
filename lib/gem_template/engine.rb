# frozen_string_literal: true

module GemTemplate
  class Engine < ::Rails::Engine
    isolate_namespace GemTemplate

    initializer "gem_template.load_config" do |app|
      # Load config/gem_template.yml via Rails config_for if present
      if app.respond_to?(:config_for)
        begin
          yaml = begin
            app.config_for(:gem_template)
          rescue StandardError
            nil
          end
          GemTemplate.configuration.merge!(yaml) if yaml && yaml.respond_to?(:each)
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
            GemTemplate.configuration.merge!(hash) if hash && hash.any?
          rescue StandardError => _e
            # ignore
          end
        end
      end
    end
  end
end
