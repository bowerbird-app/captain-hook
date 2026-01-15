# frozen_string_literal: true

require "rails_helper"

RSpec.describe CaptainHook::HandlerRegistry do
  let(:registry) { described_class.new }

  describe "#register" do
    it "registers a handler with required parameters" do
      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        handler_class: "PaymentIntentHandler",
        priority: 100,
        async: true
      )

      handlers = registry.handlers_for(provider: "stripe", event_type: "payment_intent.succeeded")
      expect(handlers.size).to eq(1)
      expect(handlers.first.provider).to eq("stripe")
      expect(handlers.first.event_type).to eq("payment_intent.succeeded")
      expect(handlers.first.handler_class).to eq("PaymentIntentHandler")
    end

    it "registers multiple handlers for the same event" do
      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        handler_class: "Handler1",
        priority: 100
      )

      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        handler_class: "Handler2",
        priority: 200
      )

      handlers = registry.handlers_for(provider: "stripe", event_type: "payment_intent.succeeded")
      expect(handlers.size).to eq(2)
      expect(handlers.map(&:handler_class)).to contain_exactly("Handler1", "Handler2")
    end

    it "sets default values for optional parameters" do
      registry.register(
        provider: "stripe",
        event_type: "test.event",
        handler_class: "TestHandler"
      )

      handler = registry.handlers_for(provider: "stripe", event_type: "test.event").first
      expect(handler.async).to be true
      expect(handler.priority).to eq(100)
      expect(handler.max_attempts).to eq(5)
      expect(handler.retry_delays).to eq([30, 60, 300, 900, 3600])
    end
  end

  describe "#handlers_for" do
    before do
      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        handler_class: "Handler1",
        priority: 100
      )

      registry.register(
        provider: "stripe",
        event_type: "payment_intent.failed",
        handler_class: "Handler2",
        priority: 200
      )

      registry.register(
        provider: "square",
        event_type: "payment.created",
        handler_class: "Handler3",
        priority: 100
      )
    end

    it "returns handlers for specific provider and event type" do
      handlers = registry.handlers_for(provider: "stripe", event_type: "payment_intent.succeeded")
      expect(handlers.size).to eq(1)
      expect(handlers.first.handler_class).to eq("Handler1")
    end

    it "returns empty array when no handlers match" do
      handlers = registry.handlers_for(provider: "unknown", event_type: "test.event")
      expect(handlers).to be_empty
    end

    it "returns handlers in priority order" do
      registry.register(
        provider: "stripe",
        event_type: "test.event",
        handler_class: "HighPriority",
        priority: 10
      )

      registry.register(
        provider: "stripe",
        event_type: "test.event",
        handler_class: "LowPriority",
        priority: 1000
      )

      handlers = registry.handlers_for(provider: "stripe", event_type: "test.event")
      expect(handlers.map(&:handler_class)).to eq(%w[HighPriority LowPriority])
    end
  end

  describe "#handlers_for with wildcards" do
    before do
      registry.register(
        provider: "stripe",
        event_type: "payment_intent.*",
        handler_class: "WildcardHandler",
        priority: 100
      )

      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        handler_class: "SpecificHandler",
        priority: 200
      )
    end

    # Wildcard matching is not yet implemented
    xit "matches wildcard handlers" do
      handlers = registry.handlers_for(provider: "stripe", event_type: "payment_intent.created")
      expect(handlers.map(&:handler_class)).to include("WildcardHandler")
    end

    xit "matches both wildcard and specific handlers" do
      handlers = registry.handlers_for(provider: "stripe", event_type: "payment_intent.succeeded")
      expect(handlers.map(&:handler_class)).to contain_exactly("WildcardHandler", "SpecificHandler")
    end

    it "does not match unrelated events" do
      handlers = registry.handlers_for(provider: "stripe", event_type: "charge.succeeded")
      expect(handlers).to be_empty
    end
  end

  describe "#all_handlers" do
    before do
      registry.register(provider: "stripe", event_type: "test.event1", handler_class: "Handler1")
      registry.register(provider: "stripe", event_type: "test.event2", handler_class: "Handler2")
      registry.register(provider: "square", event_type: "test.event3", handler_class: "Handler3")
    end

    it "returns all registered handlers" do
      all_handlers = registry.all_handlers
      expect(all_handlers.size).to eq(3)
      expect(all_handlers.map(&:handler_class)).to contain_exactly("Handler1", "Handler2", "Handler3")
    end
  end

  describe "#handlers_for_provider" do
    before do
      registry.register(provider: "stripe", event_type: "event1", handler_class: "Handler1")
      registry.register(provider: "stripe", event_type: "event2", handler_class: "Handler2")
      registry.register(provider: "square", event_type: "event3", handler_class: "Handler3")
    end

    it "returns all handlers for a specific provider" do
      handlers = registry.handlers_for_provider("stripe")
      expect(handlers.size).to eq(2)
      expect(handlers.map(&:handler_class)).to contain_exactly("Handler1", "Handler2")
    end

    it "returns empty array for unknown provider" do
      handlers = registry.handlers_for_provider("unknown")
      expect(handlers).to be_empty
    end
  end

  describe "#clear!" do
    before do
      registry.register(provider: "stripe", event_type: "test.event", handler_class: "Handler1")
      registry.register(provider: "square", event_type: "test.event", handler_class: "Handler2")
    end

    it "removes all registered handlers" do
      expect(registry.all_handlers).not_to be_empty
      registry.clear!
      expect(registry.all_handlers).to be_empty
    end
  end

  describe "thread safety" do
    it "safely handles concurrent registrations" do
      threads = 10.times.map do |i|
        Thread.new do
          registry.register(
            provider: "stripe",
            event_type: "test.event",
            handler_class: "Handler#{i}",
            priority: 100
          )
        end
      end

      threads.each(&:join)

      handlers = registry.handlers_for(provider: "stripe", event_type: "test.event")
      expect(handlers.size).to eq(10)
    end
  end

  describe "integration with CaptainHook module" do
    it "uses the global handler registry" do
      CaptainHook.register_handler(
        provider: "stripe",
        event_type: "test.global",
        handler_class: "GlobalHandler"
      )

      handlers = CaptainHook.handler_registry.handlers_for(
        provider: "stripe",
        event_type: "test.global"
      )

      expect(handlers.size).to eq(1)
      expect(handlers.first.handler_class).to eq("GlobalHandler")
    end
  end
end
