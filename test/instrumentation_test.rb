# frozen_string_literal: true

require "test_helper"
require "ostruct"

module CaptainHook
  class InstrumentationTest < ActiveSupport::TestCase
    setup do
      @events = []
      @subscription = ActiveSupport::Notifications.subscribe(/captain_hook/) do |*args|
        @events << ActiveSupport::Notifications::Event.new(*args)
      end
    end

    teardown do
      ActiveSupport::Notifications.unsubscribe(@subscription)
    end

    test "incoming_received instruments with correct data" do
      event = OpenStruct.new(id: 123, external_id: "evt_123")

      Instrumentation.incoming_received(event, provider: "stripe", event_type: "payment.success")

      assert_equal 1, @events.size
      notification = @events.first

      assert_equal Instrumentation::INCOMING_RECEIVED, notification.name
      assert_equal 123, notification.payload[:event_id]
      assert_equal "stripe", notification.payload[:provider]
      assert_equal "payment.success", notification.payload[:event_type]
      assert_equal "evt_123", notification.payload[:external_id]
    end

    test "incoming_processing instruments with correct data" do
      event = OpenStruct.new(id: 456, provider: "square", event_type: "order.created")

      Instrumentation.incoming_processing(event)

      notification = @events.first
      assert_equal Instrumentation::INCOMING_PROCESSING, notification.name
      assert_equal 456, notification.payload[:event_id]
      assert_equal "square", notification.payload[:provider]
      assert_equal "order.created", notification.payload[:event_type]
    end

    test "incoming_processed instruments with correct data" do
      handlers = [OpenStruct.new, OpenStruct.new]
      event = OpenStruct.new(
        id: 789,
        provider: "paypal",
        event_type: "payment.completed",
        incoming_event_actions: handlers
      )

      Instrumentation.incoming_processed(event, duration: 150.5)

      notification = @events.first
      assert_equal Instrumentation::INCOMING_PROCESSED, notification.name
      assert_equal 789, notification.payload[:event_id]
      assert_equal "paypal", notification.payload[:provider]
      assert_equal "payment.completed", notification.payload[:event_type]
      assert_equal 150.5, notification.payload[:duration]
      assert_equal 2, notification.payload[:handlers_count]
    end

    test "incoming_failed instruments with error information" do
      event = OpenStruct.new(id: 101, provider: "stripe", event_type: "charge.failed")
      error = StandardError.new("Something went wrong")

      Instrumentation.incoming_failed(event, error: error)

      notification = @events.first
      assert_equal Instrumentation::INCOMING_FAILED, notification.name
      assert_equal 101, notification.payload[:event_id]
      assert_equal "StandardError", notification.payload[:error]
      assert_equal "Something went wrong", notification.payload[:error_message]
    end

    test "handler_started instruments with correct data" do
      event = OpenStruct.new(id: 202, provider: "webhook_site")
      handler = OpenStruct.new(
        id: 303,
        action_class: "TestHandler",
        attempt_count: 2
      )

      Instrumentation.handler_started(handler, event: event)

      notification = @events.first
      assert_equal Instrumentation::HANDLER_STARTED, notification.name
      assert_equal 303, notification.payload[:handler_id]
      assert_equal "TestHandler", notification.payload[:action_class]
      assert_equal 202, notification.payload[:event_id]
      assert_equal "webhook_site", notification.payload[:provider]
      assert_equal 3, notification.payload[:attempt] # attempt_count + 1
    end

    test "handler_completed instruments with duration" do
      handler = OpenStruct.new(
        id: 404,
        action_class: "CompleteHandler"
      )

      Instrumentation.handler_completed(handler, duration: 25.3)

      notification = @events.first
      assert_equal Instrumentation::HANDLER_COMPLETED, notification.name
      assert_equal 404, notification.payload[:handler_id]
      assert_equal "CompleteHandler", notification.payload[:action_class]
      assert_equal 25.3, notification.payload[:duration]
    end

    test "handler_failed instruments with error information" do
      handler = OpenStruct.new(
        id: 505,
        action_class: "FailingHandler",
        attempt_count: 1
      )
      error = ArgumentError.new("Invalid argument")

      Instrumentation.handler_failed(handler, error: error)

      notification = @events.first
      assert_equal Instrumentation::HANDLER_FAILED, notification.name
      assert_equal 505, notification.payload[:handler_id]
      assert_equal "FailingHandler", notification.payload[:action_class]
      assert_equal "ArgumentError", notification.payload[:error]
      assert_equal "Invalid argument", notification.payload[:error_message]
      assert_equal 1, notification.payload[:attempt]
    end

    test "rate_limit_exceeded instruments with rate limit data" do
      Instrumentation.rate_limit_exceeded(
        provider: "stripe",
        current_count: 105,
        limit: 100
      )

      notification = @events.first
      assert_equal Instrumentation::RATE_LIMIT_EXCEEDED, notification.name
      assert_equal "stripe", notification.payload[:provider]
      assert_equal 105, notification.payload[:current_count]
      assert_equal 100, notification.payload[:limit]
    end

    test "signature_verified instruments with provider" do
      Instrumentation.signature_verified(provider: "square")

      notification = @events.first
      assert_equal Instrumentation::SIGNATURE_VERIFIED, notification.name
      assert_equal "square", notification.payload[:provider]
    end

    test "signature_failed instruments with provider and reason" do
      Instrumentation.signature_failed(
        provider: "paypal",
        reason: "Invalid timestamp"
      )

      notification = @events.first
      assert_equal Instrumentation::SIGNATURE_FAILED, notification.name
      assert_equal "paypal", notification.payload[:provider]
      assert_equal "Invalid timestamp", notification.payload[:reason]
    end

    test "event names are correctly defined" do
      assert_equal "incoming_event.received.captain_hook", Instrumentation::INCOMING_RECEIVED
      assert_equal "incoming_event.processing.captain_hook", Instrumentation::INCOMING_PROCESSING
      assert_equal "incoming_event.processed.captain_hook", Instrumentation::INCOMING_PROCESSED
      assert_equal "incoming_event.failed.captain_hook", Instrumentation::INCOMING_FAILED
      assert_equal "handler.started.captain_hook", Instrumentation::HANDLER_STARTED
      assert_equal "handler.completed.captain_hook", Instrumentation::HANDLER_COMPLETED
      assert_equal "handler.failed.captain_hook", Instrumentation::HANDLER_FAILED
      assert_equal "rate_limit.exceeded.captain_hook", Instrumentation::RATE_LIMIT_EXCEEDED
      assert_equal "signature.verified.captain_hook", Instrumentation::SIGNATURE_VERIFIED
      assert_equal "signature.failed.captain_hook", Instrumentation::SIGNATURE_FAILED
    end

    test "multiple events can be tracked in sequence" do
      event1 = OpenStruct.new(id: 1, external_id: "evt_1")
      event2 = OpenStruct.new(id: 2, external_id: "evt_2")

      Instrumentation.incoming_received(event1, provider: "stripe", event_type: "test.one")
      Instrumentation.incoming_received(event2, provider: "square", event_type: "test.two")

      assert_equal 2, @events.size
      assert_equal 1, @events[0].payload[:event_id]
      assert_equal 2, @events[1].payload[:event_id]
    end
  end
end
