# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require_relative "../support/benchmark_helper"
require_relative "../support/fixtures"

# Rails environment already loaded by benchmark_helper
require "rails/test_help"

puts "\n💾 Database Operations Benchmark"
puts "Testing event creation and idempotency checks"

# Setup
provider = BenchmarkFixtures.create_test_provider

# Benchmark event creation
puts "\n📊 Event Creation Performance"
BenchmarkHelper.compare_benchmarks("Event Creation", {
                                     "New event creation" => lambda {
                                       CaptainHook::IncomingEvent.create!(
                                         provider: provider.name,
                                         external_id: SecureRandom.uuid,
                                         event_type: "test.event",
                                         payload: BenchmarkFixtures.stripe_payload,
                                         headers: BenchmarkFixtures.stripe_headers,
                                         status: :received,
                                         dedup_state: :unique
                                       )
                                     },
                                     "Idempotency check (duplicate)" => lambda {
                                       CaptainHook::IncomingEvent.find_or_create_by_external!(
                                         provider: provider.name,
                                         external_id: "duplicate_event_id",
                                         event_type: "test.event",
                                         payload: BenchmarkFixtures.stripe_payload,
                                         headers: BenchmarkFixtures.stripe_headers,
                                         status: :received,
                                         dedup_state: :unique
                                       )
                                     }
                                   })

# Benchmark queries
puts "\n📊 Event Query Performance"
# Create some test data
10.times { BenchmarkFixtures.create_test_event(provider: provider.name) }

BenchmarkHelper.compare_benchmarks("Event Queries", {
                                     "Find by provider" => lambda {
                                       CaptainHook::IncomingEvent.by_provider(provider.name).limit(10).to_a
                                     },
                                     "Find by provider + event_type" => lambda {
                                       CaptainHook::IncomingEvent.by_provider(provider.name)
                                                                  .by_event_type("test.event")
                                                                  .limit(10).to_a
                                     },
                                     "Recent events" => lambda {
                                       CaptainHook::IncomingEvent.recent.limit(10).to_a
                                     }
                                   })

# Cleanup
CaptainHook::IncomingEvent.where(provider: provider.name).delete_all
