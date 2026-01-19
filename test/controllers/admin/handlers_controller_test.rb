# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Admin
    class HandlersControllerTest < ActionDispatch::IntegrationTest
      include Engine.routes.url_helpers

      setup do
        @provider = CaptainHook::Provider.create!(
          name: "stripe",
          verifier_class: "CaptainHook::Verifiers::Stripe",
          token: "test_token",
          signing_secret: "test_secret"
        )
        @handler = CaptainHook::Handler.create!(
          provider: "stripe",
          event_type: "charge.succeeded",
          handler_class: "TestHandler",
          priority: 100,
          async: true,
          max_attempts: 3,
          retry_delays: [60, 300, 3600]
        )
      end

      test "should get index" do
        get "/captain_hook/admin/providers/#{@provider.id}/handlers"
        assert_response :success
      end

      test "should get edit" do
        get "/captain_hook/admin/providers/#{@provider.id}/handlers/#{@handler.id}/edit"
        assert_response :success
      end

      test "should update handler" do
        patch "/captain_hook/admin/providers/#{@provider.id}/handlers/#{@handler.id}",
              params: { handler: { priority: 200 } }
        assert_redirected_to admin_provider_handlers_path(@provider)
        @handler.reload
        assert_equal 200, @handler.priority
      end

      test "should update handler with JSON retry_delays" do
        patch "/captain_hook/admin/providers/#{@provider.id}/handlers/#{@handler.id}",
              params: { handler: { retry_delays: "[10, 20, 30]" } }
        assert_redirected_to admin_provider_handlers_path(@provider)
        @handler.reload
        assert_equal [10, 20, 30], @handler.retry_delays
      end

      test "should update handler with comma-separated retry_delays" do
        patch "/captain_hook/admin/providers/#{@provider.id}/handlers/#{@handler.id}",
              params: { handler: { retry_delays: "10, 20, 30" } }
        assert_redirected_to admin_provider_handlers_path(@provider)
        @handler.reload
        assert_equal [10, 20, 30], @handler.retry_delays
      end

      test "should handle invalid JSON in retry_delays gracefully" do
        patch "/captain_hook/admin/providers/#{@provider.id}/handlers/#{@handler.id}",
              params: { handler: { retry_delays: "not-json" } }
        assert_response :unprocessable_entity
      end

      test "should soft delete handler" do
        delete "/captain_hook/admin/providers/#{@provider.id}/handlers/#{@handler.id}"
        assert_redirected_to admin_provider_handlers_path(@provider)
        @handler.reload
        assert @handler.deleted_at.present?
      end

      test "should get handlers from registry" do
        # Register a test handler
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "test.event",
          handler_class: "TestHandler"
        )

        get "/captain_hook/admin/providers/#{@provider.id}/handlers"
        assert_response :success
      end
    end
  end
end
