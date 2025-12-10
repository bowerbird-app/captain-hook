# frozen_string_literal: true

require "test_helper"

class GemTemplateTest < Minitest::Test
  def test_version_exists
    refute_nil ::GemTemplate::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, ::GemTemplate::Engine
  end
end
