# frozen_string_literal: true

module GemTemplate
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs GemTemplate engine into your application"

      def mount_engine
        route 'mount GemTemplate::Engine, at: "/gem_template"'
      end

      def copy_initializer
        template "gem_template_initializer.rb", "config/initializers/gem_template.rb"
      end

      def add_yaml_config
        return unless yes?("Would you like to add `config/gem_template.yml` for environment-specific settings? [y/N]")

        template "gem_template.yml", "config/gem_template.yml"
      end

      def add_tailwind_source
        tailwind_css_path = Rails.root.join("app/assets/tailwind/application.css")

        unless File.exist?(tailwind_css_path)
          say "Tailwind CSS not detected. Skipping Tailwind configuration.", :yellow
          say "If you use Tailwind, add this line to your Tailwind CSS config:", :yellow
          say '  @source "../../vendor/bundle/**/gem_template/app/views/**/*.erb";', :yellow
          return
        end

        tailwind_content = File.read(tailwind_css_path)
        source_line = '@source "../../vendor/bundle/**/gem_template/app/views/**/*.erb";'

        if tailwind_content.include?(source_line)
          say "Tailwind already configured to include GemTemplate views.", :green
          return
        end

        # Insert the @source directive after @import "tailwindcss";
        if tailwind_content.include?('@import "tailwindcss"')
          inject_into_file tailwind_css_path, after: "@import \"tailwindcss\";\n" do
            "\n/* Include GemTemplate engine views for Tailwind CSS */\n#{source_line}\n"
          end
          say "Added GemTemplate views to Tailwind CSS configuration.", :green
          say "Run 'bin/rails tailwindcss:build' to rebuild your CSS.", :green
        else
          say "Could not find @import \"tailwindcss\" in your Tailwind config.", :yellow
          say "Please manually add this line to your Tailwind CSS config:", :yellow
          say "  #{source_line}", :yellow
        end
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end
    end
  end
end
