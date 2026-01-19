# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require_relative "../support/benchmark_helper"
require_relative "../support/fixtures"

# Rails environment already loaded by benchmark_helper
require "rails/test_help"

puts "\n🚀 End-to-End Benchmark"
puts "Testing complete webhook processing pipeline"

# Setup
provider = BenchmarkFixtures.create_test_provider

puts "\n📊 Full Webhook Processing Pipeline"
payload = BenchmarkFixtures.stripe_payload(size: :medium).to_json
headers = BenchmarkFixtures.stripe_headers

BenchmarkHelper.run_benchmark("Complete webhook reception flow") do
  # Simulate the full flow
  verifier = provider.verifier

  # 1. Signature verification
  verifier.verify_signature(payload: payload, headers: headers)

  # 2. Parse payload
  parsed = JSON.parse(payload)

  # 3. Extract event details
  external_id = verifier.extract_event_id(parsed)
  event_type = verifier.extract_event_type(parsed)

  # 4. Create event (idempotency check)
  CaptainHook::IncomingEvent.find_or_create_by_external!(
    provider: provider.name,
    external_id: external_id || SecureRandom.uuid,
    event_type: event_type,
    payload: parsed,
    headers: headers,
    status: :received,
    dedup_state: :unique
  )
end

puts "\n📊 Throughput Analysis"
puts "Simulating sustained load..."

start_time = Time.now
processed_count = 0
duration = 10 # seconds

while Time.now - start_time < duration
  BenchmarkFixtures.create_test_event(
    provider: provider.name,
    external_id: SecureRandom.uuid
  )
  processed_count += 1
end

elapsed = Time.now - start_time
throughput = processed_count / elapsed

puts "\nResults:"
puts "  Processed: #{processed_count} events"
puts "  Duration: #{elapsed.round(2)}s"
puts "  Throughput: #{throughput.round(2)} events/second"
puts "  Avg latency: #{(elapsed / processed_count * 1000).round(2)}ms per event"

# Cleanup
CaptainHook::IncomingEvent.where(provider: provider.name).delete_all
