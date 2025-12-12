# frozen_string_literal: true

require "captain_hook/version"
require "captain_hook/engine"
require "captain_hook/configuration"
require "captain_hook/handler_registry"
require "captain_hook/provider_config"
require "captain_hook/outgoing_endpoint"

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
