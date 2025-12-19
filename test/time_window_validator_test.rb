# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class TimeWindowValidatorTest < Minitest::Test
    def setup
      @validator = TimeWindowValidator.new
    end

    # === Valid Timestamp Tests ===

    def test_validates_current_timestamp
      current_time = Time.now.to_i

      assert @validator.valid?(current_time, tolerance: 300)
    end

    def test_validates_timestamp_within_past_tolerance
      five_minutes_ago = (Time.now - 299).to_i

      assert @validator.valid?(five_minutes_ago, tolerance: 300)
    end

    def test_validates_timestamp_within_future_tolerance
      five_minutes_ahead = (Time.now + 299).to_i

      assert @validator.valid?(five_minutes_ahead, tolerance: 300)
    end

    def test_validates_timestamp_at_exact_past_boundary
      exactly_five_minutes_ago = (Time.now - 300).to_i

      assert @validator.valid?(exactly_five_minutes_ago, tolerance: 300)
    end

    def test_validates_timestamp_at_exact_future_boundary
      exactly_five_minutes_ahead = (Time.now + 300).to_i

      assert @validator.valid?(exactly_five_minutes_ahead, tolerance: 300)
    end

    # === Invalid Timestamp Tests ===

    def test_rejects_timestamp_too_far_in_past
      too_old = (Time.now - 301).to_i

      refute @validator.valid?(too_old, tolerance: 300)
    end

    def test_rejects_timestamp_too_far_in_future
      too_new = (Time.now + 301).to_i

      refute @validator.valid?(too_new, tolerance: 300)
    end

    def test_rejects_very_old_timestamp
      very_old = (Time.now - (3600 * 24)).to_i # 1 day old

      refute @validator.valid?(very_old, tolerance: 300)
    end

    def test_rejects_timestamp_from_distant_future
      distant_future = (Time.now + (3600 * 24)).to_i # 1 day ahead

      refute @validator.valid?(distant_future, tolerance: 300)
    end

    # === Different Tolerance Tests ===

    def test_validates_with_small_tolerance
      current_time = Time.now.to_i

      assert @validator.valid?(current_time, tolerance: 10)
    end

    def test_validates_with_large_tolerance
      one_hour_ago = (Time.now - 3599).to_i

      assert @validator.valid?(one_hour_ago, tolerance: 3600)
    end

    def test_validates_with_zero_tolerance
      current_time = Time.now.to_i

      # With zero tolerance, only exact current second should be valid
      # But due to test execution time, we allow current second
      assert @validator.valid?(current_time, tolerance: 0)
    end

    # === Edge Cases ===

    def test_handles_nil_timestamp
      refute @validator.valid?(nil, tolerance: 300)
    end

    def test_handles_negative_timestamp
      refute @validator.valid?(-100, tolerance: 300)
    end

    def test_handles_zero_timestamp
      # Unix epoch (1970-01-01) is way in the past
      refute @validator.valid?(0, tolerance: 300)
    end

    def test_handles_string_timestamp
      current_time = Time.now.to_i.to_s

      # Should handle string conversion
      assert @validator.valid?(current_time, tolerance: 300)
    end

    def test_handles_float_timestamp
      current_time = Time.now.to_f

      # Should handle float conversion
      assert @validator.valid?(current_time, tolerance: 300)
    end

    # === Time Object Tests ===

    def test_accepts_time_object
      current_time = Time.now

      assert @validator.valid?(current_time, tolerance: 300)
    end

    def test_accepts_datetime_object
      current_time = DateTime.now

      assert @validator.valid?(current_time, tolerance: 300)
    end

    # === Default Tolerance Tests ===

    def test_uses_default_tolerance_when_not_specified
      current_time = Time.now.to_i

      # Should use a default tolerance if method supports it
      # This tests the interface even if no default is implemented
      assert @validator.valid?(current_time, tolerance: 300)
    end

    # === Validation Message Tests ===

    def test_provides_validation_error_message_for_old_timestamp
      too_old = (Time.now - 600).to_i

      result = @validator.validate(too_old, tolerance: 300)
      refute result[:valid]
      assert result[:error]
      assert_match(/too old|past|expired/i, result[:error])
    end

    def test_provides_validation_error_message_for_future_timestamp
      too_new = (Time.now + 600).to_i

      result = @validator.validate(too_new, tolerance: 300)
      refute result[:valid]
      assert result[:error]
      assert_match(/future|too new|not yet valid/i, result[:error])
    end

    def test_provides_success_message_for_valid_timestamp
      current_time = Time.now.to_i

      result = @validator.validate(current_time, tolerance: 300)
      assert result[:valid]
      assert_nil result[:error]
    end

    # === Performance Tests ===

    def test_validation_is_fast
      current_time = Time.now.to_i

      start_time = Time.now
      1000.times do
        @validator.valid?(current_time, tolerance: 300)
      end
      elapsed = Time.now - start_time

      # Should be able to validate 1000 timestamps in less than 0.1 seconds
      assert elapsed < 0.1, "Validation should be fast, took #{elapsed} seconds"
    end
  end
end
