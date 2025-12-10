# frozen_string_literal: true

require_relative "lib/gem_template/version"

Gem::Specification.new do |spec|
  spec.name        = "gem_template"
  spec.version     = GemTemplate::VERSION
  spec.authors     = ["Your Name"]
  spec.email       = ["your.email@example.com"]
  spec.homepage    = "https://github.com/bowerbird-app/gem_template"
  spec.summary     = "Rails mountable engine template with Codespaces support"
  spec.description = "A template for creating Rails mountable engines with PostgreSQL UUID primary keys, " \
                     "TailwindCSS, and GitHub Codespaces integration"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/gem_template"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/gem_template/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.0.0"
end
