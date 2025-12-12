# frozen_string_literal: true

module CaptainHook
  module Services
    # Rate limiter service for incoming webhooks
    # Tracks request counts per provider within a time window
    class RateLimiter
      class RateLimitExceeded < StandardError; end

      def initialize
        @mutex = Mutex.new
        @requests = Hash.new { |h, k| h[k] = [] }
      end

      # Check if rate limit allows request
      # @param provider [String] Provider name
      # @param limit [Integer] Max requests allowed
      # @param period [Integer] Time period in seconds
      # @return [Boolean] true if allowed, false if rate limited
      def allowed?(provider:, limit:, period:)
        @mutex.synchronize do
          cleanup_old_requests(provider, period)
          
          current_count = @requests[provider].size
          current_count < limit
        end
      end

      # Record a request
      # @param provider [String] Provider name
      # @param limit [Integer] Max requests allowed
      # @param period [Integer] Time period in seconds
      # @raise [RateLimitExceeded] if rate limit is exceeded
      def record!(provider:, limit:, period:)
        @mutex.synchronize do
          cleanup_old_requests(provider, period)
          
          current_count = @requests[provider].size
          
          if current_count >= limit
            raise RateLimitExceeded, "Rate limit exceeded for provider #{provider}: #{current_count}/#{limit} requests in #{period}s"
          end
          
          @requests[provider] << Time.current
        end
      end

      # Get current request count for provider
      # @param provider [String] Provider name
      # @param period [Integer] Time period in seconds
      # @return [Integer] Current request count
      def current_count(provider:, period:)
        @mutex.synchronize do
          cleanup_old_requests(provider, period)
          @requests[provider].size
        end
      end

      # Get remaining requests for provider
      # @param provider [String] Provider name
      # @param limit [Integer] Max requests allowed
      # @param period [Integer] Time period in seconds
      # @return [Integer] Remaining request count
      def remaining(provider:, limit:, period:)
        current = current_count(provider: provider, period: period)
        [limit - current, 0].max
      end

      # Reset rate limit for provider
      def reset!(provider)
        @mutex.synchronize do
          @requests.delete(provider)
        end
      end

      # Clear all rate limits
      def clear!
        @mutex.synchronize do
          @requests.clear
        end
      end

      # Get statistics for a provider
      def stats(provider:, period:)
        @mutex.synchronize do
          cleanup_old_requests(provider, period)
          
          requests = @requests[provider]
          return { count: 0, oldest: nil, newest: nil } if requests.empty?

          {
            count: requests.size,
            oldest: requests.first,
            newest: requests.last
          }
        end
      end

      private

      # Remove requests older than the period
      def cleanup_old_requests(provider, period)
        cutoff = Time.current - period.seconds
        @requests[provider].reject! { |timestamp| timestamp < cutoff }
      end
    end
  end
end
