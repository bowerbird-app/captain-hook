# frozen_string_literal: true

# Action for webhook.site test events
# Creates a WebhookLog record to track incoming webhooks
module WebhookSite
  class TestAction
    def self.details
      {
        description: "Handles webhook.site test events",
        event_type: "test",
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def self.call(event:, payload:, metadata:)
      new.call(event: event, payload: payload, metadata: metadata)
    end

    def call(event:, payload:, metadata:)
      Rails.logger.info "=" * 80
      Rails.logger.info "🎣 WebhookSiteTestAction called!"
      Rails.logger.info "Event: #{event.inspect}"
      Rails.logger.info "Provider: #{event.provider}"
      Rails.logger.info "Event Type: #{event.event_type}"
      Rails.logger.info "External ID: #{event.external_id}"
      Rails.logger.info "Payload Keys: #{payload.keys.inspect}"
      Rails.logger.info "Metadata: #{metadata.inspect}"
      Rails.logger.info "=" * 80

      # Create a webhook log record
      log = WebhookLog.create!(
        provider: event.provider,
        event_type: event.event_type,
        external_id: event.external_id,
        payload: payload,
        processed_at: Time.current
      )

      Rails.logger.info "✅ Created WebhookLog with ID: #{log.id}"

      # Return success
      { success: true, webhook_log_id: log.id }
    rescue => e
      Rails.logger.error "❌ Error in WebhookSiteTestAction: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end
end
