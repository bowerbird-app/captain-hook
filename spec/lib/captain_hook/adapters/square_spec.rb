# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe CaptainHook::Adapters::Square do
  let(:signing_secret) { "test_secret_#{SecureRandom.hex(16)}" }
  let(:provider_config) do
    OpenStruct.new(
      signing_secret: signing_secret,
      token: "test_token_123"
    )
  end
  let(:adapter) { described_class.new(provider_config) }

  describe "#verify_signature" do
    let(:payload) do
      {
        merchant_id: "merchant_123",
        type: "bank_account.created",
        event_id: "evt_square_123",
        data: { object: { id: "bank_123" } }
      }.to_json
    end

    def generate_signature(notification_url, payload, secret)
      OpenSSL::HMAC.base64digest("SHA256", secret, notification_url + payload)
    end

    context "with valid signature" do
      it "returns true when signature matches" do
        # Square webhook verification requires notification URL + payload
        notification_url = "https://example.com/captain_hook/square/token123"
        signature = generate_signature(notification_url, payload, signing_secret)

        headers = {
          "X-Square-Hmacsha256-Signature" => signature
        }

        # Mock the notification URL building
        allow(adapter).to receive(:build_notification_url).and_return(notification_url)

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be true
      end
    end

    context "with invalid signature" do
      it "returns false for wrong secret" do
        notification_url = "https://example.com/captain_hook/square/token123"
        signature = generate_signature(notification_url, payload, "wrong_secret")

        headers = {
          "X-Square-Hmacsha256-Signature" => signature
        }

        allow(adapter).to receive(:build_notification_url).and_return(notification_url)

        expect(adapter.verify_signature(payload: payload, headers: headers)).to be false
      end

      it "returns false for tampered payload" do
        notification_url = "https://example.com/captain_hook/square/token123"
        signature = generate_signature(notification_url, payload, signing_secret)
        tampered_payload = payload.gsub("123", "456")

        headers = {
          "X-Square-Hmacsha256-Signature" => signature
        }

        allow(adapter).to receive(:build_notification_url).and_return(notification_url)

        expect(adapter.verify_signature(payload: tampered_payload, headers: headers)).to be false
      end

      it "returns false for missing signature header" do
        expect(adapter.verify_signature(payload: payload, headers: {})).to be false
      end
    end
  end

  describe "#extract_event_id" do
    it "extracts event ID from payload" do
      payload = {
        "merchant_id" => "merchant_123",
        "type" => "bank_account.created",
        "event_id" => "evt_square_123"
      }
      expect(adapter.extract_event_id(payload)).to eq("evt_square_123")
    end

    it "returns nil for missing event_id" do
      payload = { "type" => "bank_account.created" }
      expect(adapter.extract_event_id(payload)).to be_nil
    end
  end

  describe "#extract_event_type" do
    it "extracts event type from payload" do
      payload = {
        "merchant_id" => "merchant_123",
        "type" => "bank_account.created",
        "event_id" => "evt_square_123"
      }
      expect(adapter.extract_event_type(payload)).to eq("bank_account.created")
    end

    it "returns nil for missing type" do
      payload = { "event_id" => "evt_square_123" }
      expect(adapter.extract_event_type(payload)).to be_nil
    end
  end
end
