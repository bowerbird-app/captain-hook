# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Admin
    class SandboxControllerTest < ActionDispatch::IntegrationTest
      include Engine.routes.url_helpers

      setup do
        @provider = CaptainHook::Provider.create!(
          name: "stripe",
          verifier_class: "CaptainHook::Verifiers::Stripe",
          token: "test_token",
          signing_secret: "test_secret"
        )
      end

      test "should get index" do
        get "/captain_hook/admin/sandbox"
        assert_response :success
      end

      test "should test webhook with valid payload" do
        CaptainHook.register_action(
          provider: "stripe",
          event_type: "charge.succeeded",
          action_class: "TestAction"
        )

        payload = {
          id: "evt_test",
          type: "charge.succeeded",
          data: { object: { id: "ch_test" } }
        }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: @provider.id, payload: payload }

        assert_response :success
        json = JSON.parse(response.body)
        assert json["success"]
        assert json["dry_run"]
        assert_equal "stripe", json["provider"]["name"]
        assert_equal "charge.succeeded", json["extracted"]["event_type"]
      end

      test "should handle invalid JSON in payload" do
        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: @provider.id, payload: "not-json" }

        assert_response :bad_request
        json = JSON.parse(response.body)
        assert_not json["success"]
        assert_includes json["error"], "Invalid JSON"
      end

      test "should show message when no handlers found" do
        payload = {
          id: "evt_test",
          type: "no.handler.event",
          data: { object: { id: "ch_test" } }
        }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: @provider.id, payload: payload }

        assert_response :success
        json = JSON.parse(response.body)
        assert json["success"]
        assert_not json["would_process"]
        assert_includes json["message"], "No handlers registered"
      end

      test "should show message when handlers found" do
        CaptainHook.register_action(
          provider: "stripe",
          event_type: "charge.succeeded",
          action_class: "TestAction"
        )

        payload = {
          id: "evt_test",
          type: "charge.succeeded",
          data: { object: { id: "ch_test" } }
        }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: @provider.id, payload: payload }

        assert_response :success
        json = JSON.parse(response.body)
        assert json["success"]
        assert json["would_process"]
        assert_includes json["message"], "Would trigger"
      end

      test "should include handler details in response" do
        CaptainHook.handler_registry.clear!

        CaptainHook.register_action(
          provider: "stripe",
          event_type: "charge.succeeded",
          action_class: "TestAction",
          async: true,
          priority: 100
        )

        payload = {
          id: "evt_test",
          type: "charge.succeeded",
          data: { object: { id: "ch_test" } }
        }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: @provider.id, payload: payload }

        assert_response :success
        json = JSON.parse(response.body)
        assert json["handlers"].is_a?(Array)
        assert json["handlers"].any?
        handler = json["handlers"].first
        assert_equal "TestAction", handler["class"]
        assert_equal 100, handler["priority"]
        assert handler["async"]
      end

      test "should handle exceptions gracefully" do
        # Create a provider with invalid verifier_class to trigger error
        bad_provider = CaptainHook::Provider.create!(
          name: "bad",
          verifier_class: "NonExistentVerifier",
          token: "bad_test_token"
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        assert_response :internal_server_error
        json = JSON.parse(response.body)
        assert_not json["success"]
        assert json["error"].present?
      end
    end
  end
end
