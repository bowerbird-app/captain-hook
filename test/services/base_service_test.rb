# frozen_string_literal: true

require "test_helper"

module GemTemplate
  module Services
    class BaseServiceTest < Minitest::Test
      # Test subclass for testing BaseService
      class TestService < BaseService
        def initialize(should_succeed:, value: nil, error: nil)
          @should_succeed = should_succeed
          @value = value
          @error = error
        end

        private

        def perform
          if @should_succeed
            success(@value)
          else
            failure(@error)
          end
        end
      end

      # Test subclass that doesn't implement perform
      class IncompleteService < BaseService
      end

      def test_call_class_method_delegates_to_instance
        result = TestService.call(should_succeed: true, value: "hello")
        assert result.success?
        assert_equal "hello", result.value
      end

      def test_success_result
        result = TestService.call(should_succeed: true, value: { data: 123 })

        assert result.success?
        refute result.failure?
        assert_equal({ data: 123 }, result.value)
        assert_nil result.error
      end

      def test_failure_result
        result = TestService.call(should_succeed: false, error: "Something went wrong")

        refute result.success?
        assert result.failure?
        assert_nil result.value
        assert_equal "Something went wrong", result.error
      end

      def test_on_success_callback
        called = false
        received_value = nil

        TestService.call(should_succeed: true, value: "test") do |result|
          result.on_success do |value|
            called = true
            received_value = value
          end
        end

        assert called, "on_success should have been called"
        assert_equal "test", received_value
      end

      def test_on_failure_callback
        called = false
        received_error = nil

        TestService.call(should_succeed: false, error: "oops") do |result|
          result.on_failure do |error, _errors|
            called = true
            received_error = error
          end
        end

        assert called, "on_failure should have been called"
        assert_equal "oops", received_error
      end

      def test_on_success_not_called_on_failure
        called = false

        TestService.call(should_succeed: false, error: "fail") do |result|
          result.on_success { called = true }
        end

        refute called, "on_success should not be called on failure"
      end

      def test_on_failure_not_called_on_success
        called = false

        TestService.call(should_succeed: true, value: "ok") do |result|
          result.on_failure { called = true }
        end

        refute called, "on_failure should not be called on success"
      end

      def test_value_bang_returns_value_on_success
        result = TestService.call(should_succeed: true, value: "unwrapped")
        assert_equal "unwrapped", result.value!
      end

      def test_value_bang_raises_on_failure
        result = TestService.call(should_succeed: false, error: "error message")
        assert_raises(RuntimeError) { result.value! }
      end

      def test_chaining_callbacks
        success_called = false
        failure_called = false

        result = TestService.call(should_succeed: true, value: "chain")
        result
          .on_success { success_called = true }
          .on_failure { failure_called = true }

        assert success_called
        refute failure_called
      end

      def test_perform_not_implemented_raises
        assert_raises(NotImplementedError) { IncompleteService.call }
      end

      def test_result_errors_array
        result = BaseService::Result.new(
          success: false,
          error: "Main error",
          errors: ["Detail 1", "Detail 2"]
        )

        assert_equal ["Detail 1", "Detail 2"], result.errors
      end
    end
  end
end
