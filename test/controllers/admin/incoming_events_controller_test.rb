# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Admin
    class IncomingEventsControllerTest < ActionDispatch::IntegrationTest
      include Engine.routes.url_helpers

      setup do
        @provider = CaptainHook::Provider.create!(
          name: "stripe",
          verifier_class: "CaptainHook::Verifiers::Stripe",
          token: "test_token",
          signing_secret: "test_secret"
        )
        @event1 = CaptainHook::IncomingEvent.create!(
          provider: @provider,
          event_type: "charge.succeeded",
          external_id: "evt_1",
          status: "processed",
          payload: { id: "evt_1" }
        )
        @event2 = CaptainHook::IncomingEvent.create!(
          provider: @provider,
          event_type: "charge.failed",
          external_id: "evt_2",
          status: "failed",
          payload: { id: "evt_2" }
        )
      end

      test "should get index" do
        get "/captain_hook/admin/incoming_events"
        assert_response :success
      end

      test "should filter by provider" do
        get "/captain_hook/admin/incoming_events", params: { provider: "stripe" }
        assert_response :success
      end

      test "should filter by event_type" do
        get "/captain_hook/admin/incoming_events", params: { event_type: "charge.succeeded" }
        assert_response :success
      end

      test "should filter by status" do
        get "/captain_hook/admin/incoming_events", params: { status: "completed" }
        assert_response :success
      end

      test "should show event" do
        get "/captain_hook/admin/incoming_events/#{@event1.id}"
        assert_response :success
      end

      test "should include event actions in show" do
        CaptainHook::IncomingEventAction.create!(
          incoming_event: @event1,
          action_class: ".*Action",
          status: "processed"
        )
        get "/captain_hook/admin/incoming_events/#{@event1.id}"
        assert_response :success
      end
    end
  end
end
