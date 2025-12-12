# frozen_string_literal: true

require "test_helper"

class CaptainHookTest < Minitest::Test
  def test_version_exists
    refute_nil ::CaptainHook::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::CaptainHook::Engine
  end
end
