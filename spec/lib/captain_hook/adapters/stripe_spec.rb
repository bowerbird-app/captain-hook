# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe CaptainHook::Adapters::Stripe do
  let(:signing_secret) { "whsec_test_secret_#{SecureRandom.hex(16)}" }
  let(:provider_config) do
    OpenStruct.new(
      signing_secret: signing_secret,
      timestamp_validation_enabled?: true,
      timestamp_tolerance_seconds: 300
    )
  end
  let(:adapter) { described_class.new(provider_config) }

  describe "#verify_signature" do
    let(:payload) do
      {
        id: "evt_test_123",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_123" } }
      }.to_json
    end

    def generate_signature(payload, secret, timestamp = Time.current.to_i)
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
      "t=#{timestamp},v1=#{signature}"
    end

    context "with valid signature" do
      it "returns true" do
        timestamp = Time.current.to_i
        signature_header = generate_signature(payload, signing_secret, timestamp)
        headers = { "Stripe-Signature" => signature_header }

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be true
      end

      it "accepts v0 signature format" do
        timestamp = Time.current.to_i
        signed_payload = "#{timestamp}.#{payload}"
        signature = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, signed_payload)
        signature_header = "t=#{timestamp},v0=#{signature}"
        headers = { "Stripe-Signature" => signature_header }

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be true
      end

      it "accepts multiple signature versions" do
        timestamp = Time.current.to_i
        signed_payload = "#{timestamp}.#{payload}"
        v1_sig = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, signed_payload)
        v0_sig = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, signed_payload)
        signature_header = "t=#{timestamp},v1=#{v1_sig},v0=#{v0_sig}"
        headers = { "Stripe-Signature" => signature_header }

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be true
      end
    end

    context "with invalid signature" do
      it "returns false for wrong secret" do
        timestamp = Time.current.to_i
        signature_header = generate_signature(payload, "wrong_secret", timestamp)
        headers = { "Stripe-Signature" => signature_header }

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be false
      end

      it "returns false for tampered payload" do
        timestamp = Time.current.to_i
        signature_header = generate_signature(payload, signing_secret, timestamp)
        tampered_payload = payload.gsub("123", "456")
        headers = { "Stripe-Signature" => signature_header }

        expect(adapter.verify_signature(payload: tampered_payload, headers: headers)).to be false
      end

      it "returns false for missing signature header" do
        expect(adapter.verify_signature(payload: payload, headers: {})).to be false
      end

      it "returns false for malformed signature header" do
        headers = { "Stripe-Signature" => "invalid" }
        expect(adapter.verify_signature(payload: payload, headers: headers)).to be false
      end
    end

    context "with timestamp validation" do
      let(:provider_config) do
        instance_double(
          "CaptainHook::ProviderConfig",
          signing_secret: signing_secret,
          timestamp_validation_enabled?: true,
          timestamp_tolerance_seconds: 300
        )
      end

      before do
        allow(adapter).to receive(:provider_config).and_return(provider_config)
      end

      it "rejects expired timestamps" do
        old_timestamp = 1.hour.ago.to_i
        signature_header = generate_signature(payload, signing_secret, old_timestamp)
        headers = { "Stripe-Signature" => signature_header }

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be false
      end

      it "accepts recent timestamps within tolerance" do
        recent_timestamp = 4.minutes.ago.to_i
        signature_header = generate_signature(payload, signing_secret, recent_timestamp)
        headers = { "Stripe-Signature" => signature_header }

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be true
      end

      it "accepts future timestamps within tolerance" do
        future_timestamp = 2.minutes.from_now.to_i
        signature_header = generate_signature(payload, signing_secret, future_timestamp)
        headers = { "Stripe-Signature" => signature_header }

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be true
      end
    end
  end

  describe "#extract_event_id" do
    it "extracts event ID from payload" do
      payload = { "id" => "evt_test_123", "type" => "payment_intent.succeeded" }
      expect(adapter.extract_event_id(payload)).to eq("evt_test_123")
    end

    it "returns nil for missing ID" do
      payload = { "type" => "payment_intent.succeeded" }
      expect(adapter.extract_event_id(payload)).to be_nil
    end
  end

  describe "#extract_event_type" do
    it "extracts event type from payload" do
      payload = { "id" => "evt_test_123", "type" => "payment_intent.succeeded" }
      expect(adapter.extract_event_type(payload)).to eq("payment_intent.succeeded")
    end

    it "returns nil for missing type" do
      payload = { "id" => "evt_test_123" }
      expect(adapter.extract_event_type(payload)).to be_nil
    end
  end

  describe "#extract_timestamp" do
    it "extracts timestamp from signature header" do
      timestamp = Time.current.to_i
      signature_header = "t=#{timestamp},v1=sig123"
      headers = { "Stripe-Signature" => signature_header }

      expect(adapter.extract_timestamp(headers)).to eq(timestamp)
    end

    it "returns nil for missing signature header" do
      expect(adapter.extract_timestamp({})).to be_nil
    end

    it "returns nil for malformed signature header" do
      headers = { "Stripe-Signature" => "invalid" }
      expect(adapter.extract_timestamp(headers)).to be_nil
    end
  end
end
