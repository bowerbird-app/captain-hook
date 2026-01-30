# frozen_string_literal: true

require "rails_helper"

RSpec.describe CaptainHook::IncomingController, type: :request do
  describe "POST /captain_hook/:provider/:token" do
    let!(:provider) { CaptainHook::Provider.find_or_create_by!(name: "stripe") { |p| p.token = SecureRandom.urlsafe_base64(32) } }
    let(:signing_secret) { "whsec_test_secret" }
    let(:payload) do
      {
        id: "evt_test_123",
        type: "payment_intent.succeeded",
        data: {
          object: {
            id: "pi_test_123",
            amount: 1000,
            currency: "usd"
          }
        }
      }
    end
    let(:raw_payload) { payload.to_json }

    before do
      # Register Stripe provider configuration with signing secret
      CaptainHook.configuration.register_provider(
        "stripe",
        token: provider.token,
        verifier_class: "CaptainHook::Verifiers::Stripe",
        signing_secret: signing_secret
      )
    end

    # Helper to generate Stripe signature
    def generate_stripe_signature(payload, secret, timestamp = Time.current.to_i)
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
      "t=#{timestamp},v1=#{signature}"
    end

    context "when webhook is successfully received" do
      it "creates a new incoming event" do
        timestamp = Time.current.to_i
        signature = generate_stripe_signature(raw_payload, signing_secret, timestamp)

        expect do
          post "/captain_hook/#{provider.name}/#{provider.token}",
               params: raw_payload,
               headers: {
                 "Content-Type" => "application/json",
                 "Stripe-Signature" => signature
               }
        end.to change(CaptainHook::IncomingEvent, :count).by(1)

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("received")
        expect(json["id"]).to be_present

        event = CaptainHook::IncomingEvent.last
        expect(event.provider).to eq(provider.name)
        expect(event.external_id).to eq("evt_test_123")
        expect(event.event_type).to eq("payment_intent.succeeded")
      end

      it "enqueues action jobs" do
        # Register an action
        CaptainHook.register_action(
          provider: provider.name,
          event_type: "payment_intent.succeeded",
          action_class: "TestAction",
          async: true
        )

        timestamp = Time.current.to_i
        signature = generate_stripe_signature(raw_payload, signing_secret, timestamp)

        expect do
          post "/captain_hook/#{provider.name}/#{provider.token}",
               params: raw_payload,
               headers: {
                 "Content-Type" => "application/json",
                 "Stripe-Signature" => signature
               }
        end.to have_enqueued_job(CaptainHook::IncomingActionJob)

        expect(response).to have_http_status(:created)
      end
    end

    context "with idempotency" do
      it "returns 200 OK for duplicate webhooks" do
        timestamp = Time.current.to_i
        signature = generate_stripe_signature(raw_payload, signing_secret, timestamp)

        headers = {
          "Content-Type" => "application/json",
          "Stripe-Signature" => signature
        }

        # First request - creates event
        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: raw_payload,
             headers: headers

        expect(response).to have_http_status(:created)
        first_event_id = JSON.parse(response.body)["id"]

        # Second request - duplicate
        expect do
          post "/captain_hook/#{provider.name}/#{provider.token}",
               params: raw_payload,
               headers: headers
        end.not_to change(CaptainHook::IncomingEvent, :count)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("duplicate")
        expect(json["id"]).to eq(first_event_id)

        event = CaptainHook::IncomingEvent.find(first_event_id)
        expect(event.dedup_state).to eq("duplicate")
      end
    end

    context "with authentication" do
      it "rejects requests with invalid token" do
        timestamp = Time.current.to_i
        signature = generate_stripe_signature(raw_payload, signing_secret, timestamp)

        post "/captain_hook/#{provider.name}/invalid_token",
             params: raw_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => signature
             }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Invalid token")
      end

      it "rejects requests for unknown provider" do
        post "/captain_hook/unknown_provider/some_token",
             params: raw_payload,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Unknown provider")
      end

      it "rejects requests for inactive provider" do
        provider.update!(active: false)
        timestamp = Time.current.to_i
        signature = generate_stripe_signature(raw_payload, signing_secret, timestamp)

        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: raw_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => signature
             }

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Provider is inactive")
      end
    end

    context "with signature verification" do
      it "rejects requests with invalid signature" do
        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: raw_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => "t=#{Time.current.to_i},v1=invalid_signature"
             }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Invalid signature")
      end

      it "rejects requests with missing signature" do
        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: raw_payload,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unauthorized)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Invalid signature")
      end

      xit "rejects requests with expired timestamp" do
        old_timestamp = 1.hour.ago.to_i
        signature = generate_stripe_signature(raw_payload, signing_secret, old_timestamp)

        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: raw_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => signature
             }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Timestamp outside tolerance window")
      end

      it "accepts requests with valid timestamp within tolerance" do
        timestamp = (Time.current - 4.minutes).to_i # Within 5 minute tolerance
        signature = generate_stripe_signature(raw_payload, signing_secret, timestamp)

        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: raw_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => signature
             }

        expect(response).to have_http_status(:created)
      end
    end

    context "with rate limiting" do
      let(:provider) { create(:captain_hook_provider, :stripe, :with_rate_limiting) }

      xit "rejects requests when rate limit is exceeded" do
        timestamp = Time.current.to_i
        signature = generate_stripe_signature(raw_payload, signing_secret, timestamp)

        headers = {
          "Content-Type" => "application/json",
          "Stripe-Signature" => signature
        }

        # Make requests up to the limit (10)
        provider.rate_limit_requests.times do |i|
          payload_with_unique_id = payload.merge(id: "evt_test_#{i}")
          raw = payload_with_unique_id.to_json
          sig = generate_stripe_signature(raw, signing_secret, timestamp)

          post "/captain_hook/#{provider.name}/#{provider.token}",
               params: raw,
               headers: headers.merge("Stripe-Signature" => sig)

          expect(response).to have_http_status(:created)
        end

        # Next request should be rate limited
        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: raw_payload,
             headers: headers

        expect(response).to have_http_status(:too_many_requests)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Rate limit exceeded")
      end
    end

    context "with payload size limits" do
      before do
        # Register provider config with payload size limit
        CaptainHook.configuration.register_provider(
          provider.name,
          token: provider.token,
          verifier_class: "CaptainHook::Verifiers::Stripe",
          signing_secret: signing_secret,
          max_payload_size_bytes: 1024
        )
      end

      xit "rejects payloads that exceed size limit" do
        large_payload = { data: "x" * 2000 }.to_json
        timestamp = Time.current.to_i
        signature = generate_stripe_signature(large_payload, signing_secret, timestamp)

        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: large_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => signature
             }

        expect(response).to have_http_status(:content_too_large)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Payload too large")
      end

      xit "accepts payloads within size limit" do
        small_payload = { data: "small" }.to_json
        timestamp = Time.current.to_i
        signature = generate_stripe_signature(small_payload, signing_secret, timestamp)

        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: small_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => signature
             }

        expect(response).to have_http_status(:created)
      end
    end

    context "with invalid JSON" do
      xit "rejects requests with malformed JSON" do
        timestamp = Time.current.to_i
        invalid_payload = "{ invalid json"
        signature = generate_stripe_signature(invalid_payload, signing_secret, timestamp)

        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: invalid_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => signature
             }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("Invalid JSON")
      end
    end

    context "with multiple providers" do
      let(:stripe_provider) { create(:captain_hook_provider, :stripe, name: "stripe_account_a") }
      let(:square_provider) { create(:captain_hook_provider, :square, name: "square_account_b") }

      xit "handles webhooks from different providers independently" do
        # Stripe webhook
        stripe_payload = {
          id: "evt_stripe_123",
          type: "payment_intent.succeeded",
          data: { object: { id: "pi_123" } }
        }.to_json

        stripe_timestamp = Time.current.to_i
        stripe_signature = generate_stripe_signature(stripe_payload, stripe_provider.signing_secret, stripe_timestamp)

        post "/captain_hook/#{stripe_provider.name}/#{stripe_provider.token}",
             params: stripe_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => stripe_signature
             }

        expect(response).to have_http_status(:created)
        stripe_event = CaptainHook::IncomingEvent.find_by(provider: stripe_provider.name)
        expect(stripe_event).to be_present
        expect(stripe_event.external_id).to eq("evt_stripe_123")

        # Square webhook
        square_payload = {
          merchant_id: "merchant_123",
          type: "bank_account.created",
          event_id: "evt_square_456",
          data: { object: { id: "bank_123" } }
        }.to_json

        notification_url = "https://example.com/captain_hook/#{square_provider.name}/#{square_provider.token}"
        square_signature = OpenSSL::HMAC.base64digest("SHA256", square_provider.signing_secret,
                                                      notification_url + square_payload)

        post "/captain_hook/#{square_provider.name}/#{square_provider.token}",
             params: square_payload,
             headers: {
               "Content-Type" => "application/json",
               "X-Square-Hmacsha256-Signature" => square_signature
             }

        expect(response).to have_http_status(:created)
        square_event = CaptainHook::IncomingEvent.find_by(provider: square_provider.name)
        expect(square_event).to be_present
        expect(square_event.external_id).to eq("evt_square_456")
      end
    end
  end
end
