# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class VersionTest < ActiveSupport::TestCase
    test "has a version number" do
      assert_not_nil CaptainHook::VERSION
    end

    test "version is a string" do
      assert_kind_of String, CaptainHook::VERSION
    end

    test "version follows semantic versioning format" do
      assert_match(/\A\d+\.\d+\.\d+/, CaptainHook::VERSION)
    end
  end
end
