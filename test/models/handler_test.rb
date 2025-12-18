# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class HandlerTest < ActiveSupport::TestCase
    setup do
      @handler = Handler.new(
        provider: "stripe",
        event_type: "payment.succeeded",
        handler_class: "PaymentHandler",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60, 300]
      )
    end

    teardown do
      Handler.destroy_all
    end

    test "valid handler" do
      assert @handler.valid?
    end

    test "requires provider" do
      @handler.provider = nil
      assert_not @handler.valid?
      assert_includes @handler.errors[:provider], "can't be blank"
    end

    test "requires event_type" do
      @handler.event_type = nil
      assert_not @handler.valid?
      assert_includes @handler.errors[:event_type], "can't be blank"
    end

    test "requires handler_class" do
      @handler.handler_class = nil
      assert_not @handler.valid?
      assert_includes @handler.errors[:handler_class], "can't be blank"
    end

    test "requires priority" do
      @handler.priority = nil
      assert_not @handler.valid?
      assert_includes @handler.errors[:priority], "can't be blank"
    end

    test "priority must be an integer" do
      @handler.priority = "not a number"
      assert_not @handler.valid?
      assert_includes @handler.errors[:priority], "is not a number"
    end

    test "requires max_attempts" do
      @handler.max_attempts = nil
      assert_not @handler.valid?
      assert_includes @handler.errors[:max_attempts], "can't be blank"
    end

    test "max_attempts must be greater than 0" do
      @handler.max_attempts = 0
      assert_not @handler.valid?
      assert_includes @handler.errors[:max_attempts], "must be greater than 0"
    end

    test "requires retry_delays" do
      @handler.retry_delays = nil
      assert_not @handler.valid?
      assert_includes @handler.errors[:retry_delays], "can't be blank"
    end

    test "retry_delays must be an array of positive integers" do
      @handler.retry_delays = [30, 60, -10]
      assert_not @handler.valid?
      assert_includes @handler.errors[:retry_delays], "must be an array of positive integers"
    end

    test "retry_delays must be integers not strings" do
      @handler.retry_delays = ["30", "60"]
      assert_not @handler.valid?
      assert_includes @handler.errors[:retry_delays], "must be an array of positive integers"
    end

    test "soft_delete! sets deleted_at" do
      @handler.save!
      assert_nil @handler.deleted_at

      @handler.soft_delete!
      assert_not_nil @handler.deleted_at
      assert @handler.deleted?
    end

    test "restore! clears deleted_at" do
      @handler.save!
      @handler.soft_delete!
      assert @handler.deleted?

      @handler.restore!
      assert_nil @handler.deleted_at
      assert_not @handler.deleted?
    end

    test "active scope excludes deleted handlers" do
      @handler.save!
      deleted_handler = Handler.create!(
        provider: "square",
        event_type: "payment.succeeded",
        handler_class: "SquareHandler",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60]
      )
      deleted_handler.soft_delete!

      active_handlers = Handler.active
      assert_includes active_handlers, @handler
      assert_not_includes active_handlers, deleted_handler
    end

    test "deleted scope includes only deleted handlers" do
      @handler.save!
      deleted_handler = Handler.create!(
        provider: "square",
        event_type: "payment.succeeded",
        handler_class: "SquareHandler",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60]
      )
      deleted_handler.soft_delete!

      deleted_handlers = Handler.deleted
      assert_not_includes deleted_handlers, @handler
      assert_includes deleted_handlers, deleted_handler
    end

    test "for_provider scope filters by provider" do
      @handler.save!
      square_handler = Handler.create!(
        provider: "square",
        event_type: "payment.succeeded",
        handler_class: "SquareHandler",
        async: true,
        max_attempts: 5,
        priority: 100,
        retry_delays: [30, 60]
      )

      stripe_handlers = Handler.for_provider("stripe")
      assert_includes stripe_handlers, @handler
      assert_not_includes stripe_handlers, square_handler
    end

    test "registry_key returns formatted key" do
      @handler.save!
      assert_equal "stripe:payment.succeeded", @handler.registry_key
    end
  end
end
