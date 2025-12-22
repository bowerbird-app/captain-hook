# frozen_string_literal: true

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
