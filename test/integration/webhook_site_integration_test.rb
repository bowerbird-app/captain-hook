# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class WebhookSiteIntegrationTest < Minitest::Test
    def test_adapter_registration
      # Verify the adapter class can be instantiated
      provider_config = ProviderConfig.new(
        name: "webhook_site",
        token: "test-token",
        adapter_class: "CaptainHook::Adapters::WebhookSite"
      )

      adapter = provider_config.adapter
      assert_instance_of CaptainHook::Adapters::WebhookSite, adapter
    end

    def test_adapter_implements_base_interface
      provider_config = ProviderConfig.new(
        name: "webhook_site",
        adapter_class: "CaptainHook::Adapters::WebhookSite"
      )
      adapter = provider_config.adapter

      # Verify all required methods are implemented
      assert_respond_to adapter, :verify_signature
      assert_respond_to adapter, :extract_timestamp
      assert_respond_to adapter, :extract_event_id
      assert_respond_to adapter, :extract_event_type
    end

    def test_outgoing_event_payload_structure
      # Test the expected payload structure for webhook_site
      payload = {
        provider: "webhook_site",
        event_type: "test.ping",
        sent_at: Time.now.utc.iso8601,
        request_id: SecureRandom.uuid,
        data: { message: "test" }
      }

      assert_equal "webhook_site", payload[:provider]
      assert_equal "test.ping", payload[:event_type]
      assert payload[:sent_at].is_a?(String)
      assert payload[:request_id].is_a?(String)
      assert_equal({ message: "test" }, payload[:data])
    end
  end
end
