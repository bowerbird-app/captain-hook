# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ActionTest < ActiveSupport::TestCase
    setup do
      @action = Action.new(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "PaymentAction",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60, 300]
      )
    end

    teardown do
      Action.destroy_all
    end

    test "valid action" do
      assert @action.valid?
    end

    test "requires provider" do
      @action.provider = nil
      assert_not @action.valid?
      assert_includes @action.errors[:provider], "can't be blank"
    end

    test "requires event_type" do
      @action.event_type = nil
      assert_not @action.valid?
      assert_includes @action.errors[:event_type], "can't be blank"
    end

    test "requires action_class" do
      @action.action_class = nil
      assert_not @action.valid?
      assert_includes @action.errors[:action_class], "can't be blank"
    end

    test "requires priority" do
      @action.priority = nil
      assert_not @action.valid?
      assert_includes @action.errors[:priority], "can't be blank"
    end

    test "priority must be an integer" do
      @action.priority = "not a number"
      assert_not @action.valid?
      assert_includes @action.errors[:priority], "is not a number"
    end

    test "requires max_attempts" do
      @action.max_attempts = nil
      assert_not @action.valid?
      assert_includes @action.errors[:max_attempts], "can't be blank"
    end

    test "max_attempts must be greater than 0" do
      @action.max_attempts = 0
      assert_not @action.valid?
      assert_includes @action.errors[:max_attempts], "must be greater than 0"
    end

    test "requires retry_delays" do
      @action.retry_delays = nil
      assert_not @action.valid?
      assert_includes @action.errors[:retry_delays], "can't be blank"
    end

    test "retry_delays must be an array of positive integers" do
      @action.retry_delays = [30, 60, -10]
      assert_not @action.valid?
      assert_includes @action.errors[:retry_delays], "must be an array of positive integers"
    end

    test "retry_delays must be integers not strings" do
      @action.retry_delays = %w[30 60]
      assert_not @action.valid?
      assert_includes @action.errors[:retry_delays], "must be an array of positive integers"
    end

    test "soft_delete! sets deleted_at" do
      @action.save!
      assert_nil @action.deleted_at

      @action.soft_delete!
      assert_not_nil @action.deleted_at
      assert @action.deleted?
    end

    test "restore! clears deleted_at" do
      @action.save!
      @action.soft_delete!
      assert @action.deleted?

      @action.restore!
      assert_nil @action.deleted_at
      assert_not @action.deleted?
    end

    test "active scope excludes deleted actions" do
      @action.save!
      deleted_action = Action.create!(
        provider: "custom_provider",
        event_type: "payment.succeeded",
        action_class: "CustomAction",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60]
      )
      deleted_action.soft_delete!

      active_actions = Action.active
      assert_includes active_actions, @action
      assert_not_includes active_actions, deleted_action
    end

    test "deleted scope includes only deleted actions" do
      @action.save!
      deleted_action = Action.create!(
        provider: "custom_provider",
        event_type: "payment.succeeded",
        action_class: "CustomAction",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60]
      )
      deleted_action.soft_delete!

      deleted_actions = Action.deleted
      assert_not_includes deleted_actions, @action
      assert_includes deleted_actions, deleted_action
    end

    test "for_provider scope filters by provider" do
      @action.save!
      custom_action = Action.create!(
        provider: "custom_provider",
        event_type: "payment.succeeded",
        action_class: "CustomAction",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60]
      )

      stripe_actions = Action.for_provider("stripe")
      assert_includes stripe_actions, @action
      assert_not_includes stripe_actions, custom_action
    end

    test "registry_key returns formatted key" do
      @action.save!
      assert_equal "stripe:payment.succeeded", @action.registry_key
    end

    test "provider_record returns associated Provider" do
      provider = CaptainHook::Provider.find_or_create_by!(name: "stripe") do |p|
        p.active = true
      end
      @action.save!

      provider_record = @action.provider_record

      assert_equal provider.id, provider_record.id
      assert_equal "stripe", provider_record.name
    end

    test "provider_record returns nil when provider not found" do
      @action.provider = "nonexistent"
      @action.save!

      assert_nil @action.provider_record
    end

    test "by_priority scope orders by priority ascending" do
      # Clean up any existing actions to ensure isolation
      Action.destroy_all

      @action.priority = 200
      @action.save!

      action2 = Action.create!(
        provider: "custom_provider",
        event_type: "payment.succeeded",
        action_class: "Action2",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60]
      )

      action3 = Action.create!(
        provider: "another_provider",
        event_type: "payment.succeeded",
        action_class: "Action3",
        async: true,
        max_attempts: 5,
        priority: 150,
        retry_delays: [30, 60]
      )

      ordered = Action.by_priority
      assert_equal [action2.id, action3.id, @action.id], ordered.pluck(:id)
    end

    test "for_event_type scope filters by event type" do
      @action.save!

      action2 = Action.create!(
        provider: "stripe",
        event_type: "payment.failed",
        action_class: "FailureAction",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60]
      )

      succeeded_actions = Action.for_event_type("payment.succeeded")
      failed_actions = Action.for_event_type("payment.failed")

      assert_includes succeeded_actions, @action
      assert_not_includes succeeded_actions, action2
      assert_includes failed_actions, action2
      assert_not_includes failed_actions, @action
    end

    test "retry_delays cannot be empty array" do
      @action.retry_delays = []
      assert_not @action.valid?
      assert_includes @action.errors[:retry_delays], "can't be blank"
    end

    test "retry_delays cannot contain zero" do
      @action.retry_delays = [30, 0, 60]
      assert_not @action.valid?
      assert_includes @action.errors[:retry_delays], "must be an array of positive integers"
    end

    test "retry_delays cannot contain negative numbers" do
      @action.retry_delays = [30, -60, 90]
      assert_not @action.valid?
      assert_includes @action.errors[:retry_delays], "must be an array of positive integers"
    end
  end
end
