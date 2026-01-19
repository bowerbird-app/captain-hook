# frozen_string_literal: true

# Webhook.site adapter for testing webhooks
# Webhook.site doesn't provide signature verification, so this adapter
# implements a no-op verification that always returns true
class WebhookSiteAdapter
  include CaptainHook::AdapterHelpers

  # Webhook.site doesn't sign payloads, so verification is a no-op
  # This is intentional for testing purposes
  def verify_signature(payload:, headers:, provider_config:)
    # Webhook.site doesn't provide signature verification
    # Accept payload and headers to maintain interface compatibility
    _ = payload
    _ = headers
    _ = provider_config
    true
  end

  # Extract timestamp from custom header or payload
  def extract_timestamp(headers)
    # Check for X-Webhook-Timestamp header first
    timestamp_str = headers["X-Webhook-Timestamp"] || headers["x-webhook-timestamp"]
    return timestamp_str.to_i if timestamp_str.present?

    nil
  end

  # Extract event ID from webhook
  # Checks payload for ID fields, generates one if not found
  def extract_event_id(payload)
    # Check payload for request_id or external_id
    payload["request_id"] || payload["external_id"] || payload["id"] || SecureRandom.uuid
  end

  # Extract event type from payload or header
  # Note: Headers not available here, but they're checked in the controller
  def extract_event_type(payload)
    payload["event_type"] || payload["type"] || "test.incoming"
  end
end
