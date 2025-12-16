# frozen_string_literal: true

# Example: Inter-Gem Communication Setup
# This file demonstrates how to set up webhook communication between gems
# using CaptainHook as the orchestrator in the main application.

# =============================================================================
# STEP 1: Subscribe to Gem Notifications and Send Webhooks
# =============================================================================
# When a gem emits an ActiveSupport::Notifications event, the main app
# subscribes and sends a webhook to an external service.

ActiveSupport::Notifications.subscribe("search_gem.search.requested") do |_name, _start, _finish, _id, payload|
  Rails.logger.info "Main App: Received search.requested notification"
  
  # Only send webhook if endpoint is configured
  next unless CaptainHook::GemIntegration.webhook_configured?("lookup_service")
  
  # Send webhook to external lookup service
  CaptainHook::GemIntegration.send_webhook(
    provider: "search_gem",
    event_type: "search.requested",
    endpoint: "lookup_service",
    payload: CaptainHook::GemIntegration.build_webhook_payload(
      data: {
        search_request_id: payload[:search_request_id],
        query: payload[:query],
        requested_at: payload[:requested_at]
      }
    ),
    metadata: CaptainHook::GemIntegration.build_webhook_metadata(
      source: "search_gem",
      version: "1.0.0",
      additional: {
        environment: Rails.env,
        # Include callback URL so external service knows where to respond
        callback_url: "#{ENV['APP_URL']}/captain_hook/lookup_service/#{ENV['LOOKUP_SERVICE_TOKEN']}"
      }
    )
  )
  
  Rails.logger.info "Main App: Webhook sent to lookup_service"
rescue StandardError => e
  Rails.logger.error "Main App: Failed to send webhook: #{e.message}"
end

# =============================================================================
# STEP 2: Register Handlers for Incoming Webhooks
# =============================================================================
# When CaptainHook receives an incoming webhook from the external service,
# it routes the webhook to registered handlers.

ActiveSupport.on_load(:captain_hook_configured) do
  Rails.logger.info "Main App: Registering webhook handlers"
  
  # Register handler for search lookup responses
  CaptainHook::GemIntegration.register_webhook_handler(
    provider: "lookup_service",
    event_type: "search.completed",
    handler_class: "SearchResponseHandler",
    async: true,           # Process asynchronously via ActiveJob
    priority: 50,          # Medium priority (lower = higher priority)
    retry_delays: [30, 60, 300, 900],  # Retry delays in seconds
    max_attempts: 4
  )
  
  Rails.logger.info "Main App: Webhook handlers registered"
end

# =============================================================================
# FLOW SUMMARY
# =============================================================================
# 1. User creates SearchRequest → Model emits "search_gem.search.requested"
# 2. Main app subscribes to notification → Sends webhook to lookup_service
# 3. External service receives webhook → Processes search query
# 4. External service responds → POST to /captain_hook/lookup_service/{token}
# 5. CaptainHook receives incoming webhook → Routes to SearchResponseHandler
# 6. SearchResponseHandler updates SearchRequest → Search is completed
# 7. User sees completed search with results

# =============================================================================
# ALTERNATIVE: Use listen_to_notification helper
# =============================================================================
# Instead of manually subscribing, you can use the helper method:
#
# CaptainHook::GemIntegration.listen_to_notification(
#   "search_gem.search.requested",
#   provider: "search_gem",
#   endpoint: "lookup_service",
#   event_type_proc: ->(name) { name.gsub("_gem.", ".") },
#   payload_proc: ->(payload) {
#     CaptainHook::GemIntegration.build_webhook_payload(
#       data: payload.slice(:search_request_id, :query, :requested_at)
#     )
#   }
# )
