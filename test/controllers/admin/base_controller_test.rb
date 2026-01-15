# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Admin
    class BaseControllerTest < ActionDispatch::IntegrationTest
      test "uses admin layout" do
        assert_equal "captain_hook/admin", BaseController._layout
      end

      test "inherits from ApplicationController" do
        assert BaseController < ApplicationController
      end

      test "status_color returns correct color for pending" do
        controller = BaseController.new
        assert_equal "warning", controller.send(:status_color, "pending")
      end

      test "status_color returns correct color for processing" do
        controller = BaseController.new
        assert_equal "info", controller.send(:status_color, "processing")
      end

      test "status_color returns correct color for completed" do
        controller = BaseController.new
        assert_equal "success", controller.send(:status_color, "completed")
      end

      test "status_color returns correct color for sent" do
        controller = BaseController.new
        assert_equal "success", controller.send(:status_color, "sent")
      end

      test "status_color returns correct color for failed" do
        controller = BaseController.new
        assert_equal "danger", controller.send(:status_color, "failed")
      end

      test "status_color returns secondary for unknown status" do
        controller = BaseController.new
        assert_equal "secondary", controller.send(:status_color, "unknown")
      end

      test "status_color returns secondary for nil status" do
        controller = BaseController.new
        assert_equal "secondary", controller.send(:status_color, nil)
      end

      test "response_code_color returns success for 2xx codes" do
        controller = BaseController.new
        assert_equal "success", controller.send(:response_code_color, 200)
        assert_equal "success", controller.send(:response_code_color, 204)
      end

      test "response_code_color returns info for 3xx codes" do
        controller = BaseController.new
        assert_equal "info", controller.send(:response_code_color, 301)
        assert_equal "info", controller.send(:response_code_color, 302)
      end

      test "response_code_color returns warning for 4xx codes" do
        controller = BaseController.new
        assert_equal "warning", controller.send(:response_code_color, 400)
        assert_equal "warning", controller.send(:response_code_color, 404)
      end

      test "response_code_color returns danger for 5xx codes" do
        controller = BaseController.new
        assert_equal "danger", controller.send(:response_code_color, 500)
        assert_equal "danger", controller.send(:response_code_color, 503)
      end

      test "response_code_color returns secondary for unknown codes" do
        controller = BaseController.new
        assert_equal "secondary", controller.send(:response_code_color, 600)
      end

      test "response_code_color returns secondary for nil code" do
        controller = BaseController.new
        assert_equal "secondary", controller.send(:response_code_color, nil)
      end
    end
  end
end
