# frozen_string_literal: true

require "simplecov"

SimpleCov.start "rails" do
  # Enable branch coverage (critical for catching untested conditional paths)
  enable_coverage :branch
  
  # Set minimum coverage thresholds (CI fails if below these)
  minimum_coverage line: 90, branch: 80
  
  # Refuse to merge coverage drops (CI fails if coverage decreases)
  refuse_coverage_drop :line, :branch
  
  # Exclude non-application code
  add_filter "/test/"
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/benchmark/"
  
  # Group coverage reports for better organization
  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Jobs", "app/jobs"
  add_group "Services", "lib/captain_hook/services"
  add_group "Verifiers", "lib/captain_hook/verifiers"
  add_group "Core", "lib/captain_hook"
end

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

# Set up encryption keys for test environment
ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] = "m9zZmUjUUXMdeQnp5HeIAFQ3DdPImKAd"
ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] = "zMGZzfBbHG8t38g1M2RKD5AsnSzva90q"
ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] = "yBlRa4HF0NLzhKDXSpk1ruiDhccvRkM2"

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
