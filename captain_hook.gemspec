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

  spec.post_install_message = <<~MSG
    ⚓ CaptainHook installed successfully!

    🚀 Quick setup:  rails captain_hook:setup
    📖 Full guide:   https://github.com/bowerbird-app/captain-hook#installation

    The setup command will:
      • Mount the engine in your routes
      • Create configuration files
      • Install migrations
      • Set up encryption keys
      • Create example provider (development)
  MSG

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,captain_hook,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.post_install_message = <<~MSG
    ⚓ CaptainHook installed successfully!

    � REQUIRED: Add flat_pack to your Gemfile:
      gem "flat_pack", github: "bowerbird-app/flatpack", ref: "12ef99c5a29e8b5506cc3c9427d686c2477f774c"
      
    Then run: bundle install

    �🚀 Quick setup:
      rails captain_hook:setup

    📖 Documentation:
      https://github.com/bowerbird-app/captain-hook#installation
  MSG

  spec.add_dependency "kaminari", "~> 1.2"
  spec.add_dependency "rails", ">= 7.0.0"

  # Security: Require patched action_text-trix to avoid known XSS vulnerabilities.
  spec.add_dependency "action_text-trix", ">= 2.1.18"
end
