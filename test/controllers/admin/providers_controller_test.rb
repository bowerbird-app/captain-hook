# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Admin
    class ProvidersControllerTest < ActionDispatch::IntegrationTest
      include Engine.routes.url_helpers

      setup do
        @provider = CaptainHook::Provider.create!(
          name: "stripe",
          token: "test_token"
        )
      end

      test "should get index" do
        get "/captain_hook/admin/providers"
        assert_response :success
      end

      test "should show provider" do
        get "/captain_hook/admin/providers/#{@provider.id}"
        assert_response :success
      end

      test "should get new" do
        get "/captain_hook/admin/providers/new"
        assert_response :success
      end

      test "should get edit" do
        get "/captain_hook/admin/providers/#{@provider.id}/edit"
        assert_response :success
      end

      test "should create provider" do
        assert_difference("CaptainHook::Provider.count") do
          post "/captain_hook/admin/providers",
               params: {
                 provider: {
                   name: "paypal",
                   token: "paypal_token"
                 }
               }
        end
        assert_redirected_to admin_provider_path(CaptainHook::Provider.last)
      end

      test "should not create provider with invalid params" do
        assert_no_difference("CaptainHook::Provider.count") do
          post "/captain_hook/admin/providers",
               params: {
                 provider: {
                   name: ""
                 }
               }
        end
        assert_response :unprocessable_entity
      end

      test "should update provider" do
        patch "/captain_hook/admin/providers/#{@provider.id}",
              params: {
                provider: {
                  active: false
                }
              }
        assert_redirected_to admin_provider_path(@provider)
        @provider.reload
        assert_equal false, @provider.active
      end

      test "should not update provider with invalid params" do
        patch "/captain_hook/admin/providers/#{@provider.id}",
              params: {
                provider: {
                  name: ""
                }
              }
        assert_response :unprocessable_entity
      end

      test "should destroy provider without events" do
        provider_without_events = CaptainHook::Provider.create!(
          name: "test_delete",
          token: "test_delete_token"
        )

        assert_difference("CaptainHook::Provider.count", -1) do
          delete "/captain_hook/admin/providers/#{provider_without_events.id}"
        end
        assert_redirected_to admin_providers_url
      end

      test "should not destroy provider with events" do
        CaptainHook::IncomingEvent.create!(
          provider: @provider.name,
          external_id: "evt_test_123",
          event_type: "test.event",
          payload: { test: true }
        )

        assert_no_difference("CaptainHook::Provider.count") do
          delete "/captain_hook/admin/providers/#{@provider.id}"
        end
        assert_redirected_to admin_provider_path(@provider)
      end

      test "should show recent events on provider show page" do
        5.times do |i|
          CaptainHook::IncomingEvent.create!(
            provider: @provider.name,
            external_id: "ext_#{i}",
            event_type: "test.event.#{i}",
            payload: { index: i }
          )
        end

        get "/captain_hook/admin/providers/#{@provider.id}"
        assert_response :success
      end
    end
  end
end
