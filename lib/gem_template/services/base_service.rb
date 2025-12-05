# frozen_string_literal: true

module GemTemplate
  module Services
    # Base class for service objects following the Command pattern.
    #
    # Services encapsulate business logic and provide a consistent interface
    # with `.call` class method and a Result object for success/failure handling.
    #
    # @example Basic usage
    #   result = MyService.call(param1: "value")
    #   if result.success?
    #     puts result.value
    #   else
    #     puts result.error
    #   end
    #
    # @example With block for error handling
    #   MyService.call(param1: "value") do |result|
    #     result.on_success { |value| puts "Success: #{value}" }
    #     result.on_failure { |error| puts "Error: #{error}" }
    #   end
    #
    class BaseService
      # Result object returned by all services
      class Result
        attr_reader :value, :error, :errors

        def initialize(success:, value: nil, error: nil, errors: [])
          @success = success
          @value = value
          @error = error
          @errors = errors
        end

        def success?
          @success
        end

        def failure?
          !@success
        end

        def on_success
          yield(value) if success? && block_given?
          self
        end

        def on_failure
          yield(error, errors) if failure? && block_given?
          self
        end

        # Unwrap the value or raise an error
        def value!
          raise error if failure?

          value
        end
      end

      class << self
        # Main entry point for calling the service
        #
        # @param args [Hash] Arguments passed to the service
        # @yield [Result] Optional block for handling the result
        # @return [Result] The result of the service call
        def call(*, **, &)
          new(*, **).call(&)
        end
      end

      # Execute the service logic
      #
      # @yield [Result] Optional block for handling the result
      # @return [Result] The result of the service call
      def call
        result = perform
        yield(result) if block_given?
        result
      end

      private

      # Override this method in subclasses to implement service logic
      #
      # @return [Result] The result of the operation
      def perform
        raise NotImplementedError, "#{self.class}#perform must be implemented"
      end

      # Helper to return a success result
      #
      # @param value [Object] The successful value
      # @return [Result] A success result
      def success(value = nil)
        Result.new(success: true, value: value)
      end

      # Helper to return a failure result
      #
      # @param error [String, StandardError] The error message or exception
      # @param errors [Array] Additional error details
      # @return [Result] A failure result
      def failure(error, errors: [])
        error_message = error.is_a?(Exception) ? error.message : error
        Result.new(success: false, error: error_message, errors: errors)
      end
    end
  end
end
