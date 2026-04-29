# frozen_string_literal: true

require "simplecov"
SimpleCov.start "rails"

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

# Suppress method redefinition warnings in test environment
# (Action files may be loaded multiple times during discovery)
$VERBOSE = nil

require_relative "boot_warnings"
BootWarnings.with_filtered_stderr do
  BootWarnings.suppress_known_deprecations!
  require_relative "dummy/config/environment"
  BootWarnings.restore_deprecations!
end

# The gem's db/migrate contains source migrations that get installed via rake task
# The dummy app's db/migrate contains the installed migrations that have been run
# We need to check only the dummy app's migrations and ignore the engine's migrations
ActiveRecord::Tasks::DatabaseTasks.migrations_paths = [Rails.root.join("db/migrate").to_s]

# Prevent Rails from checking the engine's migrations during test runs
# The engine migrations are installed into the dummy app, so we only need to track those
ActiveRecord::Migrator.migrations_paths = [Rails.root.join("db/migrate").to_s]

require "rails/test_help"
require "minitest/autorun"

module AssertionHelpers
  def assert_not(value, message = nil)
    refute value, message
  end

  def assert_not_nil(value, message = nil)
    refute_nil value, message
  end

  def assert_not_equal(expected, actual, message = nil)
    refute_equal expected, actual, message
  end

  def assert_not_same(expected, actual, message = nil)
    refute_same expected, actual, message
  end

  def assert_not_empty(value, message = nil)
    refute_empty value, message
  end
end

module Minitest
  class Test
    include AssertionHelpers
  end
end

# Filter out the dummy app from the backtrace
Minitest.backtrace_filter = Minitest::BacktraceFilter.new

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

# Enable transactional tests to automatically rollback database changes after each test
module ActiveSupport
  class TestCase
    self.use_transactional_tests = true
  end
end
