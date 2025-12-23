# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class EngineTest < ActiveSupport::TestCase
    test "engine is a Rails::Engine" do
      assert Engine < ::Rails::Engine
    end

    test "engine has isolated namespace" do
      assert_equal CaptainHook, Engine.railtie_namespace
    end

    test "engine initializers are registered" do
      initializer_names = Engine.initializers.map(&:name).map(&:to_s)
      
      assert_includes initializer_names, "captain_hook.before_initialize"
      assert_includes initializer_names, "captain_hook.load_config"
      assert_includes initializer_names, "captain_hook.after_initialize"
      assert_includes initializer_names, "captain_hook.apply_model_extensions"
    end

    test "engine routes are defined" do
      assert_not_nil CaptainHook::Engine.routes
    end
  end
end
