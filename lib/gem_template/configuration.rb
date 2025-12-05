# frozen_string_literal: true

module GemTemplate
  class Configuration
    attr_accessor :api_key, :enable_feature_x, :timeout

    def initialize
      @api_key = ENV.fetch("GEM_TEMPLATE_API_KEY", nil)
      @enable_feature_x = false
      @timeout = 5
    end

    def to_h
      {
        api_key: api_key,
        enable_feature_x: enable_feature_x,
        timeout: timeout
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end
  end
end
