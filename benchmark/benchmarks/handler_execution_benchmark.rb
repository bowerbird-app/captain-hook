# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require_relative "../support/benchmark_helper"
require_relative "../support/fixtures"

# Load Rails environment in test mode
ENV["RAILS_ENV"] = "test"
require File.expand_path("../../test/dummy/config/environment", __dir__)
require "rails/test_help"

puts "\n⚡ Handler Execution Benchmark"
puts "Testing handler registration and lookup performance"

# Setup
provider = BenchmarkFixtures.create_test_provider

# Register test handlers
Rails.application.config.after_initialize do
  5.times do |i|
    CaptainHook.register_handler(
      provider: provider.name,
      event_type: "test.event.#{i}",
      handler_class: "TestHandler#{i}",
      priority: i * 10,
      async: true
    )
  end
end

puts "\n📊 Handler Registry Performance"
BenchmarkHelper.compare_benchmarks("Handler Lookup", {
                                     "Single handler lookup" => lambda {
                                       CaptainHook.handler_registry.handlers_for(
                                         provider: provider.name,
                                         event_type: "test.event.0"
                                       )
                                     },
                                     "Multiple handlers lookup" => lambda {
                                       5.times do |i|
                                         CaptainHook.handler_registry.handlers_for(
                                           provider: provider.name,
                                           event_type: "test.event.#{i}"
                                         )
                                       end
                                     },
                                     "Check if handlers registered" => lambda {
                                       CaptainHook.handler_registry.handlers_registered?(
                                         provider: provider.name,
                                         event_type: "test.event.0"
                                       )
                                     }
                                   })

puts "\n📊 Handler Record Creation"
event = BenchmarkFixtures.create_test_event(provider: provider.name)

BenchmarkHelper.run_benchmark("Create handler records") do
  handler_config = CaptainHook.handler_registry.handlers_for(
    provider: provider.name,
    event_type: "test.event.0"
  ).first

  if handler_config
    CaptainHook::IncomingEventHandler.create!(
      incoming_event: event,
      handler_class: handler_config.handler_class,
      priority: handler_config.priority,
      status: :pending,
      max_attempts: handler_config.max_attempts
    )
  end
end

# Cleanup
event.destroy
