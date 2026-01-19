# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require_relative "../support/benchmark_helper"
require_relative "../support/fixtures"

# Rails environment already loaded by benchmark_helper
require "rails/test_help"

puts "\n🔐 Signature Verification Benchmark"
puts "Testing verifier performance across different providers"

# Prepare test data
payload_small = BenchmarkFixtures.stripe_payload(size: :small).to_json
payload_medium = BenchmarkFixtures.stripe_payload(size: :medium).to_json
payload_large = BenchmarkFixtures.stripe_payload(size: :large).to_json

secret = "whsec_test_secret_for_benchmarking_12345678"
timestamp = Time.now.to_i

# Create providers with proper config
stripe_provider = BenchmarkFixtures.create_test_provider(
  name: "benchmark_stripe",
  verifier: "CaptainHook::Verifiers::Stripe"
)
stripe_provider.update!(signing_secret: secret)

square_provider = BenchmarkFixtures.create_test_provider(
  name: "benchmark_square",
  verifier: "CaptainHook::Verifiers::Square"
)
square_provider.update!(signing_secret: secret)

# Stripe verifier benchmark
puts "\n📊 Stripe Verifier - Different Payload Sizes"
stripe_verifier = stripe_provider.verifier
stripe_sig = "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{payload_medium}")}"

BenchmarkHelper.compare_benchmarks("Stripe Signature Verification", {
                                     "Small payload (#{payload_small.bytesize} bytes)" => lambda {
                                       stripe_verifier.verify_signature(
                                         payload: payload_small,
                                         headers: { "Stripe-Signature" => stripe_sig }
                                       )
                                     },
                                     "Medium payload (#{payload_medium.bytesize} bytes)" => lambda {
                                       stripe_verifier.verify_signature(
                                         payload: payload_medium,
                                         headers: { "Stripe-Signature" => stripe_sig }
                                       )
                                     },
                                     "Large payload (#{payload_large.bytesize} bytes)" => lambda {
                                       stripe_verifier.verify_signature(
                                         payload: payload_large,
                                         headers: { "Stripe-Signature" => stripe_sig }
                                       )
                                     }
                                   })

# Compare verifiers
puts "\n📊 Verifier Comparison (Medium Payload)"
square_verifier = square_provider.verifier
square_sig = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, "https://connect.squareup.com/webhooks#{payload_medium}"))

webhook_site_provider = BenchmarkFixtures.create_test_provider(
  name: "benchmark_webhooksite",
  verifier: "CaptainHook::Verifiers::WebhookSite"
)
webhook_site_verifier = webhook_site_provider.verifier

BenchmarkHelper.compare_benchmarks("Verifier Performance", {
                                     "Stripe" => lambda {
                                       stripe_verifier.verify_signature(
                                         payload: payload_medium,
                                         headers: { "Stripe-Signature" => stripe_sig }
                                       )
                                     },
                                     "Square" => lambda {
                                       square_verifier.verify_signature(
                                         payload: payload_medium,
                                         headers: { "X-Square-Hmacsha256-Signature" => square_sig }
                                       )
                                     },
                                     "WebhookSite (no verification)" => lambda {
                                       webhook_site_verifier.verify_signature(
                                         payload: payload_medium,
                                         headers: {}
                                       )
                                     }
                                   })

# Cleanup
[stripe_provider, square_provider, webhook_site_provider].each(&:destroy)
