# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require_relative "../support/benchmark_helper"
require_relative "../support/fixtures"

# Load Rails environment in test mode
ENV["RAILS_ENV"] = "test"
require File.expand_path("../../test/dummy/config/environment", __dir__)
require "rails/test_help"

puts "\n🧠 Memory Profiling Benchmark"
puts "Analyzing memory allocation and retention"

# Setup
provider = BenchmarkFixtures.create_test_provider

puts "\n📊 Webhook Processing Memory Usage"
BenchmarkHelper.memory_benchmark("Complete webhook processing") do
  100.times do
    BenchmarkFixtures.create_test_event(
      provider: provider.name,
      external_id: SecureRandom.uuid
    )
  end
end

puts "\n📊 Signature Verification Memory Usage"
stripe_provider = BenchmarkFixtures.create_test_provider(
  name: "memory_test_stripe",
  adapter: "CaptainHook::Adapters::Stripe"
)
stripe_adapter = stripe_provider.adapter
payload = BenchmarkFixtures.stripe_payload(size: :large).to_json
timestamp = Time.now.to_i
signature = "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest('SHA256', stripe_provider.signing_secret,
                                                         "#{timestamp}.#{payload}")}"

BenchmarkHelper.memory_benchmark("Signature verification (1000x)") do
  1000.times do
    stripe_adapter.verify_signature(
      payload: payload,
      headers: { "Stripe-Signature" => signature }
    )
  end
end

stripe_provider.destroy

puts "\n📊 Handler Registry Memory Usage"
BenchmarkHelper.memory_benchmark("Handler registration (100x)") do
  100.times do |i|
    CaptainHook.register_handler(
      provider: "memory_test_#{i}",
      event_type: "test.event",
      handler_class: "TestHandler",
      priority: 100,
      async: true
    )
  end
end

# Cleanup
CaptainHook::IncomingEvent.where(provider: provider.name).delete_all
