# frozen_string_literal: true

module CaptainHook
  module Services
    # Circuit breaker service for outgoing webhooks
    # Tracks endpoint health and prevents requests to failing endpoints
    class CircuitBreaker
      class CircuitOpenError < StandardError; end

      State = Struct.new(:status, :failure_count, :last_failure_at, :opened_at, keyword_init: true) do
        def open?
          status == :open
        end

        def half_open?
          status == :half_open
        end

        def closed?
          status == :closed
        end
      end

      def initialize
        @mutex = Mutex.new
        @circuits = Hash.new do |h, k|
          h[k] = State.new(status: :closed, failure_count: 0, last_failure_at: nil, opened_at: nil)
        end
      end

      # Check if circuit allows requests
      # @param endpoint [String] Endpoint identifier
      # @param failure_threshold [Integer] Failures before opening circuit
      # @param cooldown_seconds [Integer] Cooldown period before trying again
      # @return [Boolean] true if allowed
      def allowed?(endpoint:, failure_threshold:, cooldown_seconds:)
        @mutex.synchronize do
          state = @circuits[endpoint]

          case state.status
          when :closed
            true
          when :open
            # Check if cooldown period has passed
            if state.opened_at && (Time.current - state.opened_at) >= cooldown_seconds
              # Transition to half-open
              state.status = :half_open
              true
            else
              false
            end
          when :half_open
            true
          else
            true
          end
        end
      end

      # Record a success
      # @param endpoint [String] Endpoint identifier
      def record_success(endpoint)
        @mutex.synchronize do
          state = @circuits[endpoint]

          if state.half_open?
            # Successful request in half-open state closes the circuit
            state.status = :closed
            state.failure_count = 0
            state.last_failure_at = nil
            state.opened_at = nil
          elsif state.closed?
            # Reset failure count on success
            state.failure_count = 0
          end
        end
      end

      # Record a failure
      # @param endpoint [String] Endpoint identifier
      # @param failure_threshold [Integer] Failures before opening circuit
      def record_failure(endpoint:, failure_threshold:)
        @mutex.synchronize do
          state = @circuits[endpoint]
          state.failure_count += 1
          state.last_failure_at = Time.current

          if state.failure_count >= failure_threshold
            state.status = :open
            state.opened_at = Time.current
          end
        end
      end

      # Manually open a circuit
      def open!(endpoint)
        @mutex.synchronize do
          state = @circuits[endpoint]
          state.status = :open
          state.opened_at = Time.current
        end
      end

      # Manually close a circuit
      def close!(endpoint)
        @mutex.synchronize do
          state = @circuits[endpoint]
          state.status = :closed
          state.failure_count = 0
          state.last_failure_at = nil
          state.opened_at = nil
        end
      end

      # Get current state of a circuit
      # @param endpoint [String] Endpoint identifier
      # @return [State] Current circuit state
      def state(endpoint)
        @mutex.synchronize do
          @circuits[endpoint].dup
        end
      end

      # Get all circuit states
      # @return [Hash] Hash of endpoint => state
      def all_states
        @mutex.synchronize do
          @circuits.transform_values(&:dup)
        end
      end

      # Reset a circuit
      def reset!(endpoint)
        @mutex.synchronize do
          @circuits.delete(endpoint)
        end
      end

      # Clear all circuits
      def clear!
        @mutex.synchronize do
          @circuits.clear
        end
      end

      # Check if a request should be attempted
      # @param endpoint [String] Endpoint identifier
      # @param failure_threshold [Integer] Failures before opening circuit
      # @param cooldown_seconds [Integer] Cooldown period before trying again
      # @raise [CircuitOpenError] if circuit is open
      def check!(endpoint:, failure_threshold:, cooldown_seconds:)
        return if allowed?(endpoint: endpoint, failure_threshold: failure_threshold, cooldown_seconds: cooldown_seconds)

        state = state(endpoint)
        time_until_retry = cooldown_seconds - (Time.current - state.opened_at).to_i
        raise CircuitOpenError, "Circuit breaker open for #{endpoint}. Retry in #{time_until_retry}s"
      end
    end
  end
end
