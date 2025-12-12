# frozen_string_literal: true

require_relative "lib/captain_hook/version"

Gem::Specification.new do |spec|
  spec.name        = "captain_hook"
  spec.version     = CaptainHook::VERSION
  spec.authors     = ["Your Name"]
  spec.email       = ["your.email@example.com"]
  spec.homepage    = "https://github.com/bowerbird-app/captain_hook"
  spec.summary     = "Rails webhook management engine with incoming and outgoing webhook support"
  spec.description = "A comprehensive Rails engine for managing webhooks with features including " \
                     "signature verification, rate limiting, circuit breakers, retry logic, and admin UI"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/captain_hook"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/captain_hook/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.0.0"
  spec.add_dependency "kaminari", "~> 1.2"
end
