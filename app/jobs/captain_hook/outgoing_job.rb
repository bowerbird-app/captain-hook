# frozen_string_literal: true

require "net/http"
require "uri"

module CaptainHook
  # Job to send outgoing webhook events
  # Supports retry logic, SSRF protection, circuit breaker, and optimistic locking
  class OutgoingJob < ApplicationJob
    queue_as :captain_hook_outgoing

    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    # Send an outgoing webhook event
    # @param event_id [String] UUID of the OutgoingEvent
    def perform(event_id)
      event = OutgoingEvent.lock.find(event_id)

      # Get endpoint configuration
      endpoint_config = CaptainHook.configuration.outgoing_endpoint(event.provider)
      return unless endpoint_config

      # Check circuit breaker if enabled
      if endpoint_config.circuit_breaker_enabled?
        circuit_breaker = CaptainHook::Services::CircuitBreaker.new
        
        begin
          circuit_breaker.check!(
            endpoint: event.target_url,
            failure_threshold: endpoint_config.circuit_failure_threshold,
            cooldown_seconds: endpoint_config.circuit_cooldown_seconds
          )
        rescue CaptainHook::Services::CircuitBreaker::CircuitOpenError => e
          # Circuit is open, reschedule for later
          delay = endpoint_config.circuit_cooldown_seconds
          self.class.set(wait: delay.seconds).perform_later(event_id)
          return
        end
      end

      # Mark as processing
      event.start_processing!

      # Instrument start
      Instrumentation.outgoing_sending(event)
      start_time = Time.current

      begin
        # Increment attempt count
        event.increment_attempts!

        # Send request
        response_code, response_body, response_time_ms = send_webhook(event, endpoint_config)

        # Check if successful (2xx)
        if OutgoingEvent.success_response?(response_code)
          # Mark as delivered
          event.mark_delivered!(
            response_code: response_code,
            response_body: response_body,
            response_time_ms: response_time_ms
          )

          # Record success in circuit breaker
          if endpoint_config.circuit_breaker_enabled?
            circuit_breaker.record_success(event.target_url)
          end

          # Instrument success
          Instrumentation.outgoing_delivered(event, response_code: response_code, response_time_ms: response_time_ms)

        elsif OutgoingEvent.client_error?(response_code)
          # 4xx error - generally not retryable
          error_message = "Client error: #{response_code} - #{response_body}"
          event.mark_failed!(error_message, response_code: response_code, response_body: response_body, response_time_ms: response_time_ms)

          # Don't retry 4xx errors in most cases
          Instrumentation.outgoing_failed(event, error: StandardError.new(error_message), response_code: response_code)

        else
          # 5xx or other error - retryable
          error_message = "Server error: #{response_code} - #{response_body}"
          event.mark_failed!(error_message, response_code: response_code, response_body: response_body, response_time_ms: response_time_ms)

          # Record failure in circuit breaker
          if endpoint_config.circuit_breaker_enabled?
            circuit_breaker.record_failure(
              endpoint: event.target_url,
              failure_threshold: endpoint_config.circuit_failure_threshold
            )
          end

          # Check if we should retry
          if event.max_attempts_reached?(endpoint_config.max_attempts)
            # Max attempts reached
            Instrumentation.outgoing_failed(event, error: StandardError.new(error_message), response_code: response_code)
          else
            # Schedule retry with backoff
            delay = endpoint_config.delay_for_attempt(event.attempt_count)
            event.reset_for_retry!
            self.class.set(wait: delay.seconds).perform_later(event_id)
            Instrumentation.outgoing_failed(event, error: StandardError.new(error_message), response_code: response_code)
          end
        end

      rescue StandardError => e
        # Network or other error
        event.mark_failed!(e.message)

        # Record failure in circuit breaker
        if endpoint_config.circuit_breaker_enabled?
          circuit_breaker ||= CaptainHook::Services::CircuitBreaker.new
          circuit_breaker.record_failure(
            endpoint: event.target_url,
            failure_threshold: endpoint_config.circuit_failure_threshold
          )
        end

        # Instrument failure
        Instrumentation.outgoing_failed(event, error: e)

        # Check if we should retry
        if event.max_attempts_reached?(endpoint_config.max_attempts)
          # Max attempts reached, don't retry
        else
          # Schedule retry with backoff
          delay = endpoint_config.delay_for_attempt(event.attempt_count)
          event.reset_for_retry!
          self.class.set(wait: delay.seconds).perform_later(event_id)
        end

        # Re-raise to mark job as failed
        raise
      end
    end

    private

    # Send webhook HTTP request
    # @return [Array] [response_code, response_body, response_time_ms]
    def send_webhook(event, endpoint_config)
      uri = build_safe_uri(event.target_url)
      
      # Validate URL is not SSRF-vulnerable
      validate_url_safety!(uri)

      start_time = Time.current
      
      # Build request
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 30
      
      request = Net::HTTP::Post.new(uri.path.presence || "/")
      
      # Set headers
      headers = endpoint_config.default_headers.merge(event.headers || {})
      headers.each { |key, value| request[key] = value }
      
      # Add signature if enabled
      if endpoint_config.signing_enabled?
        signature_gen = SignatureGenerator.new(endpoint_config.signing_secret)
        sig_data = signature_gen.generate(event.payload)
        request[endpoint_config.signing_header] = sig_data[:signature]
        request[endpoint_config.timestamp_header] = sig_data[:timestamp].to_s
      end
      
      # Set body
      request.body = JSON.generate(event.payload)
      
      # Send request
      response = http.request(request)
      
      response_time_ms = ((Time.current - start_time) * 1000).to_i
      
      [response.code.to_i, response.body, response_time_ms]
    end

    # Build URI safely
    def build_safe_uri(url)
      URI.parse(url)
    rescue URI::InvalidURIError => e
      raise ArgumentError, "Invalid URL: #{e.message}"
    end

    # Validate URL is safe (prevent SSRF)
    def validate_url_safety!(uri)
      # Must be HTTP or HTTPS
      unless %w[http https].include?(uri.scheme)
        raise ArgumentError, "URL must use HTTP or HTTPS scheme"
      end

      # Resolve hostname
      begin
        addresses = Resolv.getaddresses(uri.host)
      rescue StandardError
        raise ArgumentError, "Could not resolve hostname: #{uri.host}"
      end

      # Check for private IP addresses (SSRF protection)
      addresses.each do |address|
        ip = IPAddr.new(address)
        
        if ip.private? || ip.loopback? || ip.link_local?
          raise ArgumentError, "URL resolves to private IP address: #{address}"
        end
      end
    end
  end
end
