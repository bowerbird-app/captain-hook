# frozen_string_literal: true

module CaptainHook
  # Configuration for a webhook provider
  # Stores settings for rate limiting, payload size, timestamp tolerance, etc.
  ProviderConfig = Struct.new(
    :name,
    :token,
    :signing_secret,
    :timestamp_tolerance_seconds,
    :max_payload_size_bytes,
    :rate_limit_requests,
    :rate_limit_period,
    :adapter_class,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.timestamp_tolerance_seconds ||= 300 # 5 minutes default
      self.max_payload_size_bytes ||= 1_048_576 # 1MB default
      self.rate_limit_requests ||= 100 # 100 requests
      self.rate_limit_period ||= 60 # per 60 seconds
      self.adapter_class ||= "CaptainHook::Adapters::Base"
    end

    # Check if rate limiting is enabled
    def rate_limiting_enabled?
      rate_limit_requests.present? && rate_limit_period.present?
    end

    # Check if timestamp tolerance is enabled
    def timestamp_validation_enabled?
      timestamp_tolerance_seconds.present? && timestamp_tolerance_seconds.positive?
    end

    # Check if payload size limit is enabled
    def payload_size_limit_enabled?
      max_payload_size_bytes.present? && max_payload_size_bytes.positive?
    end

    # Get the adapter instance
    def adapter
      @adapter ||= adapter_class.constantize.new(self)
    end
  end
end
