# frozen_string_literal: true

require "simplecov"
SimpleCov.start "rails"

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

# Suppress method redefinition warnings in test environment
# (Action files may be loaded multiple times during discovery)
$VERBOSE = nil

require_relative "dummy/config/environment"
require "rails/test_help"
require "minitest/autorun"

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
