# frozen_string_literal: true

module CaptainHook
  # Configuration for an outgoing webhook endpoint
  # Stores settings for signing, headers, retry logic, and circuit breaker
  OutgoingEndpoint = Struct.new(
    :name,
    :base_url,
    :signing_secret,
    :signing_header,
    :timestamp_header,
    :default_headers,
    :retry_delays,
    :max_attempts,
    :circuit_breaker_enabled,
    :circuit_failure_threshold,
    :circuit_cooldown_seconds,
    keyword_init: true
  ) do
    def initialize(**kwargs)
      super
      self.signing_header ||= "X-Captain-Hook-Signature"
      self.timestamp_header ||= "X-Captain-Hook-Timestamp"
      self.default_headers ||= { "Content-Type" => "application/json" }
      self.retry_delays ||= [30, 60, 300, 900, 3600] # exponential backoff
      self.max_attempts ||= 5
      self.circuit_breaker_enabled ||= true
      self.circuit_failure_threshold ||= 5
      self.circuit_cooldown_seconds ||= 300 # 5 minutes
    end

    # Build full URL for a given path
    def build_url(path = "/")
      uri = URI.parse(base_url)
      uri.path = path unless path.blank?
      uri.to_s
    end

    # Check if circuit breaker is enabled
    def circuit_breaker_enabled?
      circuit_breaker_enabled == true
    end

    # Get delay for a given attempt (0-indexed)
    def delay_for_attempt(attempt)
      retry_delays[attempt] || retry_delays.last || 3600
    end

    # Check if signing is enabled
    def signing_enabled?
      signing_secret.present?
    end
  end
end
