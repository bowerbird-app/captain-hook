# frozen_string_literal: true

module GemTemplate
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Installs GemTemplate engine into your application"

      def mount_engine
        route 'mount GemTemplate::Engine, at: "/gem_template"'
      end

      def show_readme
        readme "INSTALL.md" if behavior == :invoke
      end
    end
  end
end
