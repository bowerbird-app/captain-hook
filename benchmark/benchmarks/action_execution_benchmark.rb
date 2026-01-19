# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require_relative "../support/benchmark_helper"
require_relative "../support/fixtures"

# Rails environment already loaded by benchmark_helper
require "rails/test_help"

puts "\n⚡ Action Execution Benchmark"
puts "Testing action registration and lookup performance"

# Setup
provider = BenchmarkFixtures.create_test_provider

# Register test actions
Rails.application.config.after_initialize do
  5.times do |i|
    CaptainHook.register_action(
      provider: provider.name,
      event_type: "test.event.#{i}",
      action_class: "TestAction#{i}",
      priority: i * 10,
      async: true
    )
  end
end

puts "\n📊 Action Registry Performance"
BenchmarkHelper.compare_benchmarks("Action Lookup", {
                                     "Single action lookup" => lambda {
                                       CaptainHook.action_registry.actions_for(
                                         provider: provider.name,
                                         event_type: "test.event.0"
                                       )
                                     },
                                     "Multiple actions lookup" => lambda {
                                       5.times do |i|
                                         CaptainHook.action_registry.actions_for(
                                           provider: provider.name,
                                           event_type: "test.event.#{i}"
                                         )
                                       end
                                     },
                                     "Check if actions registered" => lambda {
                                       CaptainHook.action_registry.actions_registered?(
                                         provider: provider.name,
                                         event_type: "test.event.0"
                                       )
                                     }
                                   })

puts "\n📊 Action Record Creation"
event = BenchmarkFixtures.create_test_event(provider: provider.name)

BenchmarkHelper.run_benchmark("Create action records") do
  action_config = CaptainHook.action_registry.actions_for(
    provider: provider.name,
    event_type: "test.event.0"
  ).first

  if action_config
    CaptainHook::IncomingEventAction.create!(
      incoming_event: event,
      action_class: action_config.action_class,
      priority: action_config.priority,
      status: :pending
    )
  end
end

# Cleanup
event.destroy
