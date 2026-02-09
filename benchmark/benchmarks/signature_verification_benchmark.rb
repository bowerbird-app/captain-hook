# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require_relative "../support/benchmark_helper"
require_relative "../support/fixtures"

# Rails environment already loaded by benchmark_helper
require "rails/test_help"

puts "\n🔐 Signature Verification Benchmark"
puts "Testing verifier performance with Stripe provider"

# Prepare test data
payload_small = BenchmarkFixtures.stripe_payload(size: :small).to_json
payload_medium = BenchmarkFixtures.stripe_payload(size: :medium).to_json
payload_large = BenchmarkFixtures.stripe_payload(size: :large).to_json

secret = "whsec_test_secret_for_benchmarking_12345678"
timestamp = Time.now.to_i

# Use the existing stripe flatpack provider
stripe_provider = BenchmarkFixtures.create_test_provider(name: "stripe")

# Get provider config (includes verifier class from YAML)
provider_config = CaptainHook.configuration.provider("stripe")

# Create test config with known secret for benchmarking
test_config = CaptainHook::ProviderConfig.new(
  name: "stripe",
  signing_secret: secret,
  timestamp_tolerance_seconds: 300,
  verifier_class: provider_config&.verifier_class || "StripeVerifier"
)

# Instantiate the verifier
stripe_verifier = test_config.verifier_class.constantize.new

# Stripe verifier benchmark
puts "\n📊 Stripe Verifier - Different Payload Sizes"
stripe_sig = "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{payload_medium}")}"

BenchmarkHelper.compare_benchmarks("Stripe Signature Verification", {
                                     "Small payload (#{payload_small.bytesize} bytes)" => lambda {
                                       stripe_verifier.verify_signature(
                                         payload: payload_small,
                                         headers: { "Stripe-Signature" => stripe_sig },
                                         provider_config: test_config
                                       )
                                     },
                                     "Medium payload (#{payload_medium.bytesize} bytes)" => lambda {
                                       stripe_verifier.verify_signature(
                                         payload: payload_medium,
                                         headers: { "Stripe-Signature" => stripe_sig },
                                         provider_config: test_config
                                       )
                                     },
                                     "Large payload (#{payload_large.bytesize} bytes)" => lambda {
                                       stripe_verifier.verify_signature(
                                         payload: payload_large,
                                         headers: { "Stripe-Signature" => stripe_sig },
                                         provider_config: test_config
                                       )
                                     }
                                   })
