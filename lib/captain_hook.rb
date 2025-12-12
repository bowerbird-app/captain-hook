# frozen_string_literal: true

require "kaminari"
require "captain_hook/version"
require "captain_hook/engine"
require "captain_hook/configuration"
require "captain_hook/handler_registry"
require "captain_hook/provider_config"
require "captain_hook/outgoing_endpoint"
require "captain_hook/time_window_validator"
require "captain_hook/signature_generator"
require "captain_hook/instrumentation"

# Load adapters
require "captain_hook/adapters/base"
require "captain_hook/adapters/stripe"
require "captain_hook/adapters/webhook_site"

# Load services
require "captain_hook/services/base_service"
require "captain_hook/services/rate_limiter"
require "captain_hook/services/circuit_breaker"
require "captain_hook/services/example_service"

module CaptainHook
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    # Convenience method to access handler registry
    def handler_registry
      configuration.handler_registry
    end

    # Convenience method to register a handler
    def register_handler(**)
      handler_registry.register(**)
    end
  end
end
