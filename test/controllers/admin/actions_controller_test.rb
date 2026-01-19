# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Admin
    class ActionsControllerTest < ActionDispatch::IntegrationTest
      include Engine.routes.url_helpers

      setup do
        @provider = CaptainHook::Provider.create!(
          name: "stripe",
          verifier_class: "CaptainHook::Verifiers::Stripe",
          token: "test_token",
          signing_secret: "test_secret"
        )
        @action = CaptainHook::Action.create!(
          provider: "stripe",
          event_type: "charge.succeeded",
          action_class: "TestHandler",
          priority: 100,
          async: true,
          max_attempts: 3,
          retry_delays: [60, 300, 3600]
        )
      end

      test "should get index" do
        get "/captain_hook/admin/providers/#{@provider.id}/actions"
        assert_response :success
      end

      test "should get edit" do
        get "/captain_hook/admin/providers/#{@provider.id}/actions/#{@action.id}/edit"
        assert_response :success
      end

      test "should update handler" do
        patch "/captain_hook/admin/providers/#{@provider.id}/actions/#{@action.id}",
              params: { handler: { priority: 200 } }
        assert_redirected_to admin_provider_actions_path(@provider)
        @action.reload
        assert_equal 200, @action.priority
      end

      test "should update handler with JSON retry_delays" do
        patch "/captain_hook/admin/providers/#{@provider.id}/actions/#{@action.id}",
              params: { handler: { retry_delays: "[10, 20, 30]" } }
        assert_redirected_to admin_provider_actions_path(@provider)
        @action.reload
        assert_equal [10, 20, 30], @action.retry_delays
      end

      test "should update handler with comma-separated retry_delays" do
        patch "/captain_hook/admin/providers/#{@provider.id}/actions/#{@action.id}",
              params: { handler: { retry_delays: "10, 20, 30" } }
        assert_redirected_to admin_provider_actions_path(@provider)
        @action.reload
        assert_equal [10, 20, 30], @action.retry_delays
      end

      test "should handle invalid JSON in retry_delays gracefully" do
        patch "/captain_hook/admin/providers/#{@provider.id}/actions/#{@action.id}",
              params: { handler: { retry_delays: "not-json" } }
        assert_response :unprocessable_entity
      end

      test "should soft delete handler" do
        delete "/captain_hook/admin/providers/#{@provider.id}/actions/#{@action.id}"
        assert_redirected_to admin_provider_actions_path(@provider)
        @action.reload
        assert @action.deleted_at.present?
      end

      test "should get handlers from registry" do
        # Register a test handler
        CaptainHook.register_action(
          provider: "stripe",
          event_type: "test.event",
          action_class: "TestHandler"
        )

        get "/captain_hook/admin/providers/#{@provider.id}/actions"
        assert_response :success
      end
    end
  end
end
