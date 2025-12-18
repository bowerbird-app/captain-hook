# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class HandlerDiscoveryTest < ActiveSupport::TestCase
      setup do
        @discovery = HandlerDiscovery.new
        # Clear the registry before each test
        CaptainHook.handler_registry.clear!
      end

      test "discovers handlers from registry" do
        # Register a test handler
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment.succeeded",
          handler_class: "TestHandler",
          priority: 100,
          async: true,
          max_attempts: 5,
          retry_delays: [30, 60, 300]
        )

        handlers = @discovery.call

        assert_equal 1, handlers.size
        handler = handlers.first
        assert_equal "stripe", handler["provider"]
        assert_equal "payment.succeeded", handler["event_type"]
        assert_equal "TestHandler", handler["handler_class"]
        assert_equal 100, handler["priority"]
        assert_equal true, handler["async"]
        assert_equal 5, handler["max_attempts"]
        assert_equal [30, 60, 300], handler["retry_delays"]
      end

      test "discovers multiple handlers for same provider" do
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment.succeeded",
          handler_class: "PaymentHandler"
        )

        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment.failed",
          handler_class: "FailureHandler"
        )

        handlers = @discovery.call

        assert_equal 2, handlers.size
        provider_names = handlers.map { |h| h["provider"] }
        assert provider_names.all? { |p| p == "stripe" }
      end

      test "discovers handlers for specific provider" do
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment.succeeded",
          handler_class: "StripeHandler"
        )

        CaptainHook.register_handler(
          provider: "square",
          event_type: "payment.succeeded",
          handler_class: "SquareHandler"
        )

        stripe_handlers = HandlerDiscovery.for_provider("stripe")
        square_handlers = HandlerDiscovery.for_provider("square")

        assert_equal 1, stripe_handlers.size
        assert_equal 1, square_handlers.size
        assert_equal "StripeHandler", stripe_handlers.first["handler_class"]
        assert_equal "SquareHandler", square_handlers.first["handler_class"]
      end

      test "returns empty array when no handlers registered" do
        handlers = @discovery.call
        assert_equal [], handlers
      end

      test "for_provider returns empty array for unknown provider" do
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment.succeeded",
          handler_class: "TestHandler"
        )

        handlers = HandlerDiscovery.for_provider("unknown_provider")
        assert_equal [], handlers
      end
    end
  end
end
