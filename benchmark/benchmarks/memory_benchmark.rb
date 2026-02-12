# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require_relative "../support/benchmark_helper"
require_relative "../support/fixtures"

# Rails environment already loaded by benchmark_helper
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
stripe_provider = BenchmarkFixtures.create_test_provider(name: "stripe")

# Get provider config (includes verifier class from YAML)
provider_config = CaptainHook.configuration.provider("stripe")

secret = "whsec_test_secret_for_benchmarking_12345678"
test_config = CaptainHook::ProviderConfig.new(
  name: "stripe",
  signing_secret: secret,
  timestamp_tolerance_seconds: 300,
  verifier_class: provider_config&.verifier_class || "StripeVerifier"
)

# Instantiate the verifier
stripe_verifier = test_config.verifier_class.constantize.new

payload = BenchmarkFixtures.stripe_payload(size: :large).to_json
timestamp = Time.now.to_i
signature = "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{payload}")}"

BenchmarkHelper.memory_benchmark("Signature verification (1000x)") do
  1000.times do
    stripe_verifier.verify_signature(
      payload: payload,
      headers: { "Stripe-Signature" => signature },
      provider_config: test_config
    )
  end
end

puts "\n📊 Action Registry Memory Usage"
BenchmarkHelper.memory_benchmark("Action registration (100x)") do
  100.times do |i|
    CaptainHook.register_action(
      provider: "memory_test_#{i}",
      event_type: "test.event",
      action_class: "TestAction",
      priority: 100,
      async: true
    )
  end
end

# Cleanup
CaptainHook::IncomingEvent.where(provider: provider.name).delete_all
