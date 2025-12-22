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
    # @param tolerance [Integer, nil] Override tolerance (optional)
    # @return [Boolean] true if within tolerance
    def valid?(timestamp, tolerance: nil)
      return false if timestamp.blank?

      tolerance_to_use = tolerance || tolerance_seconds
      current_time = Time.current.to_i
      age = (current_time - timestamp.to_i).abs

      age <= tolerance_to_use
    end

    # Validate with detailed result
    # @param timestamp [Integer] Unix timestamp
    # @param tolerance [Integer, nil] Override tolerance (optional)
    # @return [Hash] Hash with :valid and :error keys
    def validate(timestamp, tolerance: nil)
      return { valid: false, error: "Timestamp is missing" } if timestamp.blank?

      tolerance_to_use = tolerance || tolerance_seconds
      current_time = Time.current.to_i
      timestamp_int = timestamp.to_i
      age = current_time - timestamp_int

      if age > tolerance_to_use
        { valid: false, error: "Timestamp is too old (expired)" }
      elsif age < -tolerance_to_use
        { valid: false, error: "Timestamp is too far in the future (not yet valid)" }
      else
        { valid: true, error: nil }
      end
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
