# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class TimeWindowValidatorAdditionalTest < Minitest::Test
    def test_valid_within_window_exact_boundary
      validator = TimeWindowValidator.new(tolerance_seconds: 300)
      timestamp = Time.now.to_i

      # Exactly at the edge of the window
      assert validator.valid?(timestamp)
    end

    def test_valid_at_negative_window_boundary
      validator = TimeWindowValidator.new(tolerance_seconds: 300)
      timestamp = (Time.now - 300).to_i

      assert validator.valid?(timestamp)
    end

    def test_valid_at_positive_window_boundary
      validator = TimeWindowValidator.new(tolerance_seconds: 300)
      timestamp = (Time.now + 300).to_i

      assert validator.valid?(timestamp)
    end

    def test_invalid_just_outside_negative_boundary
      validator = TimeWindowValidator.new(tolerance_seconds: 300)
      timestamp = (Time.now - 301).to_i

      refute validator.valid?(timestamp)
    end

    def test_invalid_just_outside_positive_boundary
      validator = TimeWindowValidator.new(tolerance_seconds: 300)
      timestamp = (Time.now + 301).to_i

      refute validator.valid?(timestamp)
    end

    def test_valid_with_tolerance_override
      validator = TimeWindowValidator.new(tolerance_seconds: 300)
      timestamp = (Time.now - 400).to_i

      # Should be invalid with default tolerance
      refute validator.valid?(timestamp)

      # But valid with overridden tolerance
      assert validator.valid?(timestamp, tolerance: 500)
    end

    def test_invalid_with_tolerance_override
      validator = TimeWindowValidator.new(tolerance_seconds: 300)
      timestamp = (Time.now - 100).to_i

      # Should be valid with default tolerance
      assert validator.valid?(timestamp)

      # But invalid with overridden stricter tolerance
      refute validator.valid?(timestamp, tolerance: 50)
    end

    def test_with_zero_tolerance
      validator = TimeWindowValidator.new(tolerance_seconds: 0)
      timestamp = Time.now.to_i

      # With 0 tolerance, only exact match is valid
      assert validator.valid?(timestamp)
    end

    def test_with_large_tolerance
      validator = TimeWindowValidator.new(tolerance_seconds: 86400) # 1 day
      timestamp = (Time.now - 43200).to_i # 12 hours ago

      assert validator.valid?(timestamp)
    end

    def test_with_string_timestamp_converts_to_integer
      validator = TimeWindowValidator.new(tolerance_seconds: 300)
      timestamp = Time.now.to_i

      assert validator.valid?(timestamp.to_i)
    end
  end
end
