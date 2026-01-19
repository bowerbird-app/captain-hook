# frozen_string_literal: true

require "kaminari"
require "captain_hook/version"
require "captain_hook/engine"
require "captain_hook/configuration"
require "captain_hook/action_registry"
require "captain_hook/provider_config"
require "captain_hook/time_window_validator"
require "captain_hook/signature_generator"
require "captain_hook/instrumentation"

# Load verifier helpers (available to host app and external verifiers)
require "captain_hook/verifier_helpers"

# Load default verifiers bundled with the gem
require "captain_hook/verifiers/base"
require "captain_hook/verifiers/stripe"
require "captain_hook/verifiers/square"
require "captain_hook/verifiers/paypal"
require "captain_hook/verifiers/webhook_site"

# Load services
require "captain_hook/services/base_service"
require "captain_hook/services/rate_limiter"
require "captain_hook/services/example_service"
require "captain_hook/services/verifier_discovery"
require "captain_hook/services/provider_discovery"
require "captain_hook/services/provider_sync"
require "captain_hook/services/action_discovery"
require "captain_hook/services/action_sync"
require "captain_hook/services/action_lookup"

module CaptainHook
  # Custom error classes
  class VerifierNotFoundError < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    # Convenience method to access action registry
    def action_registry
      configuration.action_registry
    end

    # Convenience method to register an action
    def register_action(**)
      action_registry.register(**)
    end

    # Deprecated: Backward compatibility aliases
    def handler_registry
      warn "[DEPRECATION] `handler_registry` is deprecated. Use `action_registry` instead."
      action_registry
    end

    def register_handler(**)
      warn "[DEPRECATION] `register_handler` is deprecated. Use `register_action` instead."
      register_action(**)
    end
  end
end
