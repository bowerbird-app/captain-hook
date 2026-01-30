# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Admin
    class SandboxControllerTest < ActionDispatch::IntegrationTest
      include Engine.routes.url_helpers

      setup do
        @provider = CaptainHook::Provider.find_or_create_by!(name: "stripe") do |p|
          p.token = "test_token"
        end
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

      test "should show message when no actions found" do
        payload = {
          id: "evt_test",
          type: "no.action.event",
          data: { object: { id: "ch_test" } }
        }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: @provider.id, payload: payload }

        assert_response :success
        json = JSON.parse(response.body)
        assert json["success"]
        assert_not json["would_process"]
        assert_includes json["message"], "No actions registered"
      end

      test "should show message when actions found" do
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

      test "should include action details in response" do
        CaptainHook.action_registry.clear!

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
        assert json["actions"].is_a?(Array)
        assert json["actions"].any?
        action_item = json["actions"].first
        assert_equal "TestAction", action_item["class"]
        assert_equal 100, action_item["priority"]
        assert action_item["async"]
      end

      test "should handle exceptions gracefully" do
        # Create a provider - verifier comes from registry now, not DB
        bad_provider = CaptainHook::Provider.create!(
          name: "bad",
          token: "bad_test_token"
        )

        # Register a bad verifier class in the configuration
        CaptainHook.configuration.register_provider(
          "bad",
          token: "bad_test_token",
          verifier_class: "NonExistent::InvalidVerifier"
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        # Security validation catches non-existent verifier classes and returns 400
        assert_response :bad_request
        json = JSON.parse(response.body)
        assert_not json["success"]
        assert_includes json["error"], "Verifier class not found"
      end

      # === Security Tests ===

      test "should reject dangerous verifier class name - Kernel" do
        bad_provider = CaptainHook::Provider.create!(
          name: "bad_kernel",
          token: "bad_test_token"
        )

        CaptainHook.configuration.register_provider(
          "bad_kernel",
          token: "bad_test_token",
          verifier_class: "Kernel"
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        assert_response :bad_request
        json = JSON.parse(response.body)
        assert_not json["success"]
        assert_equal "Invalid verifier class", json["error"]
      end

      test "should reject dangerous verifier class name - Object" do
        bad_provider = CaptainHook::Provider.create!(
          name: "bad_object",
          token: "bad_test_token"
        )

        CaptainHook.configuration.register_provider(
          "bad_object",
          token: "bad_test_token",
          verifier_class: "Object"
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        assert_response :bad_request
        json = JSON.parse(response.body)
        assert_equal "Invalid verifier class", json["error"]
      end

      test "should reject dangerous verifier class name - File" do
        bad_provider = CaptainHook::Provider.create!(
          name: "bad_file",
          token: "bad_test_token"
        )

        CaptainHook.configuration.register_provider(
          "bad_file",
          token: "bad_test_token",
          verifier_class: "File::Read"
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        assert_response :bad_request
        json = JSON.parse(response.body)
        assert_equal "Invalid verifier class", json["error"]
      end

      test "should reject dangerous verifier class name - IO" do
        bad_provider = CaptainHook::Provider.create!(
          name: "bad_io",
          token: "bad_test_token"
        )

        CaptainHook.configuration.register_provider(
          "bad_io",
          token: "bad_test_token",
          verifier_class: "IO"
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        assert_response :bad_request
        json = JSON.parse(response.body)
        assert_equal "Invalid verifier class", json["error"]
      end

      test "should reject verifier class name with Eval" do
        bad_provider = CaptainHook::Provider.create!(
          name: "bad_eval",
          token: "bad_test_token"
        )

        CaptainHook.configuration.register_provider(
          "bad_eval",
          token: "bad_test_token",
          verifier_class: "EvalHelper"
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        assert_response :bad_request
        json = JSON.parse(response.body)
        assert_equal "Invalid verifier class", json["error"]
      end

      test "should reject verifier class name with directory traversal" do
        bad_provider = CaptainHook::Provider.create!(
          name: "bad_traversal",
          token: "bad_test_token"
        )

        CaptainHook.configuration.register_provider(
          "bad_traversal",
          token: "bad_test_token",
          verifier_class: "../../BadClass"
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        assert_response :bad_request
        json = JSON.parse(response.body)
        assert_equal "Invalid verifier class", json["error"]
      end

      test "should use base verifier for blank verifier class name" do
        bad_provider = CaptainHook::Provider.create!(
          name: "bad_blank",
          token: "bad_test_token"
        )

        CaptainHook.configuration.register_provider(
          "bad_blank",
          token: "bad_test_token",
          verifier_class: ""
        )

        payload = { id: "test" }.to_json

        post "/captain_hook/admin/sandbox/test",
             params: { provider_id: bad_provider.id, payload: payload }

        # Blank verifier class falls back to Base verifier, which is valid
        assert_response :success
        json = JSON.parse(response.body)
        assert json["success"]
        # Verify it used the base verifier
        assert_equal "CaptainHook::Verifiers::Base", json["provider"]["verifier"]
      end
    end
  end
end
