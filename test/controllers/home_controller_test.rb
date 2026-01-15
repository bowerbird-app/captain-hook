# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class HomeControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    test "should get index" do
      get "/captain_hook"
      assert_response :redirect
      assert_redirected_to "/captain_hook/admin"
    end
  end
end
