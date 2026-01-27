# frozen_string_literal: true

require "rails_helper"

RSpec.describe CaptainHook::ActionRegistry do
  let(:registry) { described_class.new }

  describe "#register" do
    it "registers a action with required parameters" do
      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        action_class: "PaymentIntentAction",
        priority: 100,
        async: true
      )

      actions = registry.actions_for(provider: "stripe", event_type: "payment_intent.succeeded")
      expect(actions.size).to eq(1)
      expect(actions.first.provider).to eq("stripe")
      expect(actions.first.event_type).to eq("payment_intent.succeeded")
      expect(actions.first.action_class).to eq("PaymentIntentAction")
    end

    it "registers multiple actions for the same event" do
      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        action_class: "Action1",
        priority: 100
      )

      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        action_class: "Action2",
        priority: 200
      )

      actions = registry.actions_for(provider: "stripe", event_type: "payment_intent.succeeded")
      expect(actions.size).to eq(2)
      expect(actions.map(&:action_class)).to contain_exactly("Action1", "Action2")
    end

    it "sets default values for optional parameters" do
      registry.register(
        provider: "stripe",
        event_type: "test.event",
        action_class: "TestAction"
      )

      action = registry.actions_for(provider: "stripe", event_type: "test.event").first
      expect(action.async).to be true
      expect(action.priority).to eq(100)
      expect(action.max_attempts).to eq(5)
      expect(action.retry_delays).to eq([30, 60, 300, 900, 3600])
    end
  end

  describe "#actions_for" do
    before do
      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        action_class: "Action1",
        priority: 100
      )

      registry.register(
        provider: "stripe",
        event_type: "payment_intent.failed",
        action_class: "Action2",
        priority: 200
      )

      registry.register(
        provider: "custom_provider",
        event_type: "payment.created",
        action_class: "Action3",
        priority: 100
      )
    end

    it "returns actions for specific provider and event type" do
      actions = registry.actions_for(provider: "stripe", event_type: "payment_intent.succeeded")
      expect(actions.size).to eq(1)
      expect(actions.first.action_class).to eq("Action1")
    end

    it "returns empty array when no actions match" do
      actions = registry.actions_for(provider: "unknown", event_type: "test.event")
      expect(actions).to be_empty
    end

    it "returns actions in priority order" do
      registry.register(
        provider: "stripe",
        event_type: "test.event",
        action_class: "HighPriority",
        priority: 10
      )

      registry.register(
        provider: "stripe",
        event_type: "test.event",
        action_class: "LowPriority",
        priority: 1000
      )

      actions = registry.actions_for(provider: "stripe", event_type: "test.event")
      expect(actions.map(&:action_class)).to eq(%w[HighPriority LowPriority])
    end
  end

  describe "#actions_for with wildcards" do
    before do
      registry.register(
        provider: "stripe",
        event_type: "payment_intent.*",
        action_class: "WildcardAction",
        priority: 100
      )

      registry.register(
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        action_class: "SpecificAction",
        priority: 200
      )
    end

    # Wildcard matching is not yet implemented
    xit "matches wildcard actions" do
      actions = registry.actions_for(provider: "stripe", event_type: "payment_intent.created")
      expect(actions.map(&:action_class)).to include("WildcardAction")
    end

    xit "matches both wildcard and specific actions" do
      actions = registry.actions_for(provider: "stripe", event_type: "payment_intent.succeeded")
      expect(actions.map(&:action_class)).to contain_exactly("WildcardAction", "SpecificAction")
    end

    it "does not match unrelated events" do
      actions = registry.actions_for(provider: "stripe", event_type: "charge.succeeded")
      expect(actions).to be_empty
    end
  end

  describe "#all_actions" do
    before do
      registry.register(provider: "stripe", event_type: "test.event1", action_class: "Action1")
      registry.register(provider: "stripe", event_type: "test.event2", action_class: "Action2")
      registry.register(provider: "custom_provider", event_type: "test.event3", action_class: "Action3")
    end

    it "returns all registered actions" do
      all_actions = registry.all_actions
      expect(all_actions.size).to eq(3)
      expect(all_actions.map(&:action_class)).to contain_exactly("Action1", "Action2", "Action3")
    end
  end

  describe "#actions_for_provider" do
    before do
      registry.register(provider: "stripe", event_type: "event1", action_class: "Action1")
      registry.register(provider: "stripe", event_type: "event2", action_class: "Action2")
      registry.register(provider: "custom_provider", event_type: "event3", action_class: "Action3")
    end

    it "returns all actions for a specific provider" do
      actions = registry.actions_for_provider("stripe")
      expect(actions.size).to eq(2)
      expect(actions.map(&:action_class)).to contain_exactly("Action1", "Action2")
    end

    it "returns empty array for unknown provider" do
      actions = registry.actions_for_provider("unknown")
      expect(actions).to be_empty
    end
  end

  describe "#clear!" do
    before do
      registry.register(provider: "stripe", event_type: "test.event", action_class: "Action1")
      registry.register(provider: "custom_provider", event_type: "test.event", action_class: "Action2")
    end

    it "removes all registered actions" do
      expect(registry.all_actions).not_to be_empty
      registry.clear!
      expect(registry.all_actions).to be_empty
    end
  end

  describe "thread safety" do
    it "safely handles concurrent registrations" do
      threads = 10.times.map do |i|
        Thread.new do
          registry.register(
            provider: "stripe",
            event_type: "test.event",
            action_class: "Action#{i}",
            priority: 100
          )
        end
      end

      threads.each(&:join)

      actions = registry.actions_for(provider: "stripe", event_type: "test.event")
      expect(actions.size).to eq(10)
    end
  end

  describe "integration with CaptainHook module" do
    it "uses the global action registry" do
      CaptainHook.register_action(
        provider: "stripe",
        event_type: "test.global",
        action_class: "GlobalAction"
      )

      actions = CaptainHook.action_registry.actions_for(
        provider: "stripe",
        event_type: "test.global"
      )

      expect(actions.size).to eq(1)
      expect(actions.first.action_class).to eq("GlobalAction")
    end
  end
end
