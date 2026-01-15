# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ApplicationControllerTest < ActionDispatch::IntegrationTest
    class TestController < ApplicationController
      def test_action
        render plain: "OK"
      end
    end

    test "uses application layout" do
      assert_equal "application", TestController._layout
    end

    test "inherits from ActionController::Base" do
      assert ApplicationController < ActionController::Base
    end

    test "has forgery protection configured" do
      assert_includes ApplicationController._process_action_callbacks.map(&:filter), :verify_authenticity_token
    end
  end
end
