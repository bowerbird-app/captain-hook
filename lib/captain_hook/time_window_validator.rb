# frozen_string_literal: true

module CaptainHook
  # Validates timestamps to prevent replay attacks
  # Ensures webhook events are within an acceptable time window
  class TimeWindowValidator
    attr_reader :tolerance_seconds

    def initialize(tolerance_seconds: 300)
      @tolerance_seconds = tolerance_seconds
    end

    # Validate that timestamp is within tolerance window
    # @param timestamp [Integer] Unix timestamp
    # @return [Boolean] true if within tolerance
    def valid?(timestamp)
      return false if timestamp.blank?

      current_time = Time.current.to_i
      age = (current_time - timestamp.to_i).abs

      age <= tolerance_seconds
    end

    # Check if timestamp is too old
    def too_old?(timestamp)
      return false if timestamp.blank?

      current_time = Time.current.to_i
      (current_time - timestamp.to_i) > tolerance_seconds
    end

    # Check if timestamp is too new (in the future)
    def too_new?(timestamp)
      return false if timestamp.blank?

      current_time = Time.current.to_i
      (timestamp.to_i - current_time) > tolerance_seconds
    end

    # Get age of timestamp in seconds
    def age(timestamp)
      return nil if timestamp.blank?

      current_time = Time.current.to_i
      current_time - timestamp.to_i
    end
  end
end
