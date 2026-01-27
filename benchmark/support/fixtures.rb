# frozen_string_literal: true

module BenchmarkFixtures
  # Sample webhook payloads for testing
  def self.stripe_payload(size: :small)
    case size
    when :small
      { id: "evt_test123", type: "payment_intent.succeeded", data: { object: { id: "pi_123" } } }
    when :medium
      {
        id: "evt_test123",
        type: "payment_intent.succeeded",
        created: Time.now.to_i,
        data: {
          object: {
            id: "pi_123",
            amount: 1000,
            currency: "usd",
            customer: "cus_123",
            metadata: { order_id: "order_123" }
          }
        }
      }
    when :large
      {
        id: "evt_test123",
        type: "payment_intent.succeeded",
        created: Time.now.to_i,
        data: {
          object: {
            id: "pi_123",
            amount: 1000,
            currency: "usd",
            customer: "cus_123",
            payment_method: "pm_123",
            metadata: { order_id: "order_123", items: (1..10).map { |i| "item_#{i}" } },
            charges: {
              data: (1..5).map do |i|
                {
                  id: "ch_#{i}",
                  amount: 1000,
                  created: Time.now.to_i,
                  status: "succeeded"
                }
              end
            }
          }
        },
        pending_webhooks: 1,
        request: { id: "req_123", idempotency_key: "key_123" }
      }
    end
  end

  def self.stripe_headers
    {
      "Stripe-Signature" => "t=#{Time.now.to_i},v1=abc123def456"
    }
  end

  # Create a test provider
  def self.create_test_provider(name: "benchmark_stripe", verifier: "CaptainHook::Verifiers::Stripe")
    CaptainHook::Provider.find_or_create_by!(name: name) do |p|
      p.verifier_class = verifier
      p.signing_secret = "whsec_test_secret_123"
      p.active = true
    end
  end

  # Create test event
  def self.create_test_event(provider: "benchmark_stripe", external_id: nil)
    CaptainHook::IncomingEvent.create!(
      provider: provider,
      external_id: external_id || SecureRandom.uuid,
      event_type: "test.event",
      payload: stripe_payload,
      headers: stripe_headers,
      status: :received,
      dedup_state: :unique
    )
  end
end
