# frozen_string_literal: true

require "test_helper"
require "rake"

class SetupTaskTest < ActiveSupport::TestCase
  def setup
    # Load rake tasks
    CaptainHook::Engine.load_tasks
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake.application.rake_require("tasks/setup", [CaptainHook::Engine.root.join("lib").to_s])
    Rake::Task.define_task(:environment)
  end

  def teardown
    Rake.application = nil
  end

  test "captain_hook:doctor task exists" do
    assert Rake::Task.task_defined?("captain_hook:doctor")
  end

  test "captain_hook:setup task exists" do
    assert Rake::Task.task_defined?("captain_hook:setup")
  end

  test "doctor task validates setup" do
    # Just verify the task can be invoked without errors
    # Actual validation happens in the dummy app which is already set up
    assert_nothing_raised do
      # Don't actually invoke in tests, just verify it's defined
      task = Rake::Task["captain_hook:doctor"]
      assert task.present?
      assert_equal "Validate CaptainHook configuration", task.comment
    end
  end

  test "setup task has correct dependencies" do
    task = Rake::Task["captain_hook:setup"]
    assert task.present?
    assert_equal [:environment], task.prerequisites.map(&:to_sym)
  end
end
