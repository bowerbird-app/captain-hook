# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class HandlerSyncTest < ActiveSupport::TestCase
      setup do
        @handler_definitions = [
          {
            "provider" => "stripe",
            "event_type" => "payment.succeeded",
            "handler_class" => "PaymentHandler",
            "async" => true,
            "max_attempts" => 5,
            "priority" => 100,
            "retry_delays" => [30, 60, 300]
          }
        ]
      end

      teardown do
        CaptainHook::Handler.destroy_all
      end

      test "creates new handler from definition" do
        sync = HandlerSync.new(@handler_definitions)
        results = sync.call

        assert_equal 1, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 0, results[:errors].size

        handler = results[:created].first
        assert_equal "stripe", handler.provider
        assert_equal "payment.succeeded", handler.event_type
        assert_equal "PaymentHandler", handler.handler_class
        assert_equal true, handler.async
        assert_equal 5, handler.max_attempts
        assert_equal 100, handler.priority
        assert_equal [30, 60, 300], handler.retry_delays
      end

      test "updates existing handler" do
        # Create initial handler
        handler = CaptainHook::Handler.create!(
          provider: "stripe",
          event_type: "payment.succeeded",
          handler_class: "PaymentHandler",
          async: false,
          max_attempts: 3,
          priority: 200,
          retry_delays: [60, 120]
        )

        sync = HandlerSync.new(@handler_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 1, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 0, results[:errors].size

        handler.reload
        assert_equal true, handler.async
        assert_equal 5, handler.max_attempts
        assert_equal 100, handler.priority
        assert_equal [30, 60, 300], handler.retry_delays
      end

      test "skips deleted handlers" do
        # Create and soft-delete a handler
        handler = CaptainHook::Handler.create!(
          provider: "stripe",
          event_type: "payment.succeeded",
          handler_class: "PaymentHandler",
          async: true,
          max_attempts: 5,
          priority: 100,
          retry_delays: [30, 60]
        )
        handler.soft_delete!

        sync = HandlerSync.new(@handler_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 1, results[:skipped].size
        assert_equal 0, results[:errors].size

        # Verify handler is still deleted
        handler.reload
        assert handler.deleted?
      end

      test "handles multiple handlers" do
        definitions = [
          {
            "provider" => "stripe",
            "event_type" => "payment.succeeded",
            "handler_class" => "PaymentHandler",
            "async" => true,
            "max_attempts" => 5,
            "priority" => 100,
            "retry_delays" => [30, 60]
          },
          {
            "provider" => "stripe",
            "event_type" => "payment.failed",
            "handler_class" => "FailureHandler",
            "async" => true,
            "max_attempts" => 3,
            "priority" => 50,
            "retry_delays" => [60, 120]
          }
        ]

        sync = HandlerSync.new(definitions)
        results = sync.call

        assert_equal 2, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 0, results[:errors].size
      end

      test "handles invalid handler definition" do
        invalid_definitions = [
          {
            "provider" => "stripe",
            "event_type" => "payment.succeeded"
            # Missing handler_class
          }
        ]

        sync = HandlerSync.new(invalid_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 1, results[:errors].size
      end

      test "handles validation errors" do
        invalid_definitions = [
          {
            "provider" => "stripe",
            "event_type" => "payment.succeeded",
            "handler_class" => "PaymentHandler",
            "async" => true,
            "max_attempts" => 0, # Invalid - must be > 0
            "priority" => 100,
            "retry_delays" => [30]
          }
        ]

        sync = HandlerSync.new(invalid_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:skipped].size
        assert_equal 1, results[:errors].size
      end
    end
  end
end
