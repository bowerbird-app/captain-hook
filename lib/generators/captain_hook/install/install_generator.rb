# frozen_string_literal: true

module CaptainHook
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs CaptainHook engine into your application"

      def mount_engine
        route 'mount CaptainHook::Engine, at: "/captain_hook"'
      end

      def copy_initializer
        template "captain_hook_initializer.rb", "config/initializers/captain_hook.rb"
      end

      def add_yaml_config
        return unless yes?("Would you like to add `config/captain_hook.yml` for environment-specific settings? [y/N]")

        template "captain_hook.yml", "config/captain_hook.yml"
      end

      def add_tailwind_source
        tailwind_css_path = Rails.root.join("app/assets/tailwind/application.css")

        unless File.exist?(tailwind_css_path)
          say "Tailwind CSS not detected. Skipping Tailwind configuration.", :yellow
          say "If you use Tailwind, add this line to your Tailwind CSS config:", :yellow
          say '  @source "../../vendor/bundle/**/captain_hook/app/views/**/*.erb";', :yellow
          return
        end

        tailwind_content = File.read(tailwind_css_path)
        source_line = '@source "../../vendor/bundle/**/captain_hook/app/views/**/*.erb";'

        if tailwind_content.include?(source_line)
          say "Tailwind already configured to include CaptainHook views.", :green
          return
        end

        # Insert the @source directive after @import "tailwindcss";
        if tailwind_content.include?('@import "tailwindcss"')
          inject_into_file tailwind_css_path, after: "@import \"tailwindcss\";\n" do
            "\n/* Include CaptainHook engine views for Tailwind CSS */\n#{source_line}\n"
          end
          say "Added CaptainHook views to Tailwind CSS configuration.", :green
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
