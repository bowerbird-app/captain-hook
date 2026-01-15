# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe CaptainHook::Adapters::WebhookSite do
  let(:signing_secret) { "not_used_for_webhook_site" }
  let(:provider_config) do
    OpenStruct.new(
      signing_secret: signing_secret
    )
  end
  let(:adapter) { described_class.new(provider_config) }

  describe "#verify_signature" do
    let(:payload) do
      {
        test: "webhook",
        data: { message: "test payload" }
      }.to_json
    end

    it "always returns true (no verification for testing adapter)" do
      headers = {}
      expect(adapter.verify_signature(payload: payload, headers: headers)).to be true
    end

    it "returns true with any headers" do
      headers = {
        "X-Some-Header" => "value",
        "Content-Type" => "application/json"
      }
      expect(adapter.verify_signature(payload: payload, headers: headers)).to be true
    end

    it "returns true with empty payload" do
      expect(adapter.verify_signature(payload: "", headers: {})).to be true
    end
  end

  describe "#extract_event_id" do
    it "extracts event ID from id field" do
      payload = {
        "id" => "evt_webhook_site_123",
        "type" => "test.event"
      }
      expect(adapter.extract_event_id(payload)).to eq("evt_webhook_site_123")
    end

    it "falls back to id field when request_id and external_id are missing" do
      payload = {
        "id" => "evt_webhook_site_456",
        "type" => "test.event"
      }
      expect(adapter.extract_event_id(payload)).to eq("evt_webhook_site_456")
    end

    it "generates UUID when no ID fields present" do
      payload = { "type" => "test.event" }
      event_id = adapter.extract_event_id(payload)

      expect(event_id).to be_present
      expect(event_id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end
  end

  describe "#extract_event_type" do
    it "extracts event type from type field" do
      payload = {
        "id" => "evt_123",
        "type" => "webhook.test"
      }
      expect(adapter.extract_event_type(payload)).to eq("webhook.test")
    end

    it "falls back to event_type field" do
      payload = {
        "id" => "evt_123",
        "event_type" => "webhook.fallback"
      }
      expect(adapter.extract_event_type(payload)).to eq("webhook.fallback")
    end

    it "returns test.incoming when no type fields present" do
      payload = { "id" => "123" }
      expect(adapter.extract_event_type(payload)).to eq("test.incoming")
    end
  end

  describe "#extract_timestamp" do
    it "returns nil when no X-Webhook-Timestamp header" do
      timestamp = adapter.extract_timestamp({})
      expect(timestamp).to be_nil
    end

    it "returns timestamp from X-Webhook-Timestamp header if present" do
      headers = { "X-Webhook-Timestamp" => "1234567890" }
      timestamp = adapter.extract_timestamp(headers)
      expect(timestamp).to eq(1234567890)
    end
  end

  describe "usage in tests" do
    xit "is suitable for testing without signature verification" do
      # This adapter is designed for testing scenarios where you want to
      # receive webhooks without worrying about signature verification

      # Create a provider with webhook_site adapter
      provider = create(:captain_hook_provider, :webhook_site)

      # Any payload will be accepted
      payload = { test: "data", value: 123 }.to_json

      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:created)

      event = CaptainHook::IncomingEvent.last
      expect(event.provider).to eq(provider.name)
      expect(event.status).to eq("received")
    end
  end
end
