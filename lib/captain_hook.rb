# frozen_string_literal: true

require "captain_hook/version"
require "captain_hook/engine"
require "captain_hook/configuration"
require "captain_hook/services/base_service"
require "captain_hook/services/example_service"

module CaptainHook
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end
