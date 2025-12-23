# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class RateLimiterTest < ActiveSupport::TestCase
      setup do
        @limiter = RateLimiter.new
        @provider = "test_provider"
      end

      teardown do
        @limiter.clear!
      end

      test "allows requests within rate limit" do
        assert @limiter.allowed?(provider: @provider, limit: 5, period: 60)
      end

      test "records requests successfully" do
        assert_nothing_raised do
          @limiter.record!(provider: @provider, limit: 5, period: 60)
        end

        assert_equal 1, @limiter.current_count(provider: @provider, period: 60)
      end

      test "blocks requests when rate limit is exceeded" do
        # Record up to the limit
        3.times { @limiter.record!(provider: @provider, limit: 3, period: 60) }

        # Next request should raise
        error = assert_raises(RateLimiter::RateLimitExceeded) do
          @limiter.record!(provider: @provider, limit: 3, period: 60)
        end

        assert_includes error.message, "Rate limit exceeded"
        assert_includes error.message, @provider
      end

      test "allowed? returns false when limit exceeded" do
        3.times { @limiter.record!(provider: @provider, limit: 3, period: 60) }

        refute @limiter.allowed?(provider: @provider, limit: 3, period: 60)
      end

      test "tracks different providers independently" do
        provider1 = "provider1"
        provider2 = "provider2"

        @limiter.record!(provider: provider1, limit: 2, period: 60)
        @limiter.record!(provider: provider2, limit: 2, period: 60)

        assert_equal 1, @limiter.current_count(provider: provider1, period: 60)
        assert_equal 1, @limiter.current_count(provider: provider2, period: 60)
      end

      test "cleans up old requests outside the time window" do
        # Freeze time and record a request
        travel_to 2.minutes.ago do
          @limiter.record!(provider: @provider, limit: 5, period: 60)
        end

        # Current count should be 0 since request is outside 60 second window
        assert_equal 0, @limiter.current_count(provider: @provider, period: 60)
      end

      test "counts only requests within the time window" do
        # Record request 2 minutes ago (outside window)
        travel_to 2.minutes.ago do
          @limiter.record!(provider: @provider, limit: 5, period: 60)
        end

        # Record request now (within window)
        @limiter.record!(provider: @provider, limit: 5, period: 60)

        # Should only count the recent one
        assert_equal 1, @limiter.current_count(provider: @provider, period: 60)
      end

      test "remaining returns correct count" do
        limit = 5
        2.times { @limiter.record!(provider: @provider, limit: limit, period: 60) }

        remaining = @limiter.remaining(provider: @provider, limit: limit, period: 60)
        assert_equal 3, remaining
      end

      test "remaining returns 0 when limit exceeded" do
        limit = 3
        3.times { @limiter.record!(provider: @provider, limit: limit, period: 60) }

        remaining = @limiter.remaining(provider: @provider, limit: limit, period: 60)
        assert_equal 0, remaining
      end

      test "reset! clears requests for specific provider" do
        @limiter.record!(provider: @provider, limit: 5, period: 60)
        @limiter.record!(provider: "other_provider", limit: 5, period: 60)

        @limiter.reset!(@provider)

        assert_equal 0, @limiter.current_count(provider: @provider, period: 60)
        assert_equal 1, @limiter.current_count(provider: "other_provider", period: 60)
      end

      test "clear! removes all requests" do
        @limiter.record!(provider: @provider, limit: 5, period: 60)
        @limiter.record!(provider: "other_provider", limit: 5, period: 60)

        @limiter.clear!

        assert_equal 0, @limiter.current_count(provider: @provider, period: 60)
        assert_equal 0, @limiter.current_count(provider: "other_provider", period: 60)
      end

      test "stats returns correct information" do
        oldest_time = nil
        newest_time = nil

        travel_to 30.seconds.ago do
          @limiter.record!(provider: @provider, limit: 5, period: 60)
          oldest_time = Time.current
        end

        @limiter.record!(provider: @provider, limit: 5, period: 60)
        newest_time = Time.current

        stats = @limiter.stats(provider: @provider, period: 60)

        assert_equal 2, stats[:count]
        assert_in_delta oldest_time.to_f, stats[:oldest].to_f, 1
        assert_in_delta newest_time.to_f, stats[:newest].to_f, 1
      end

      test "stats returns empty data for provider with no requests" do
        stats = @limiter.stats(provider: @provider, period: 60)

        assert_equal 0, stats[:count]
        assert_nil stats[:oldest]
        assert_nil stats[:newest]
      end

      test "stats excludes old requests outside time window" do
        travel_to 2.minutes.ago do
          @limiter.record!(provider: @provider, limit: 5, period: 60)
        end

        stats = @limiter.stats(provider: @provider, period: 60)

        assert_equal 0, stats[:count]
      end

      test "thread safety - concurrent requests don't corrupt state" do
        threads = []
        limit = 10
        thread_count = 5

        thread_count.times do
          threads << Thread.new do
            2.times { @limiter.record!(provider: @provider, limit: limit, period: 60) }
          end
        end

        threads.each(&:join)

        assert_equal thread_count * 2, @limiter.current_count(provider: @provider, period: 60)
      end
    end
  end
end
