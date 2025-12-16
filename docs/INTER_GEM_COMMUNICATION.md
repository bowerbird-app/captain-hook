# Inter-Gem Communication with CaptainHook

This guide explains how to use CaptainHook to enable inter-gem communication via webhooks. The pattern keeps gems decoupled by routing all communication through the main application.

## Table of Contents

- [Overview](#overview)
- [Architecture Pattern](#architecture-pattern)
- [Setup](#setup)
- [Sending Webhooks (Outgoing)](#sending-webhooks-outgoing)
- [Receiving Webhooks (Incoming)](#receiving-webhooks-incoming)
- [Complete Example](#complete-example)
- [Best Practices](#best-practices)
- [Testing](#testing)

## Overview

The inter-gem communication pattern allows gems to communicate with each other through webhooks without direct dependencies. All communication flows through the main application:

1. **Gem A** emits an `ActiveSupport::Notifications` event
2. **Main App** subscribes to this notification and sends a webhook via CaptainHook
3. **External Service** (or another app instance) receives the webhook and responds
4. **CaptainHook** receives the incoming webhook and routes it to registered handlers
5. **Gem B** (handler) processes the webhook data and updates its own tables

## Architecture Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                        Main Application                       │
│                                                               │
│  ┌──────────┐         ┌─────────────┐         ┌──────────┐  │
│  │  Gem A   │         │ CaptainHook │         │  Gem B   │  │
│  │          │         │             │         │          │  │
│  │ 1. Emit  │────────▶│ 2. Send     │         │ 5. Handle│  │
│  │ AS::N    │         │ Webhook     │◀────────│ Webhook  │  │
│  │          │         │             │         │          │  │
│  └──────────┘         └─────────────┘         └──────────┘  │
│                              │                                │
└──────────────────────────────┼────────────────────────────────┘
                               │
                               │ 3. HTTP POST
                               ▼
                        ┌─────────────┐
                        │  External   │
                        │  Service    │
                        │             │
                        │ 4. Response │
                        └─────────────┘
```

## Setup

### 1. Configure CaptainHook in Main App

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  # Configure outgoing endpoint (where webhooks are sent TO)
  config.register_outgoing_endpoint(
    "external_service",
    base_url: ENV["EXTERNAL_SERVICE_WEBHOOK_URL"],
    signing_secret: ENV["EXTERNAL_SERVICE_SECRET"],
    default_headers: {
      "Content-Type" => "application/json",
      "X-App-Name" => "MyApp"
    }
  )

  # Configure incoming provider (where webhooks are received FROM)
  config.register_provider(
    "external_service",
    token: ENV["EXTERNAL_SERVICE_TOKEN"],
    signing_secret: ENV["EXTERNAL_SERVICE_SECRET"],
    adapter_class: "CaptainHook::Adapters::Base",
    timestamp_tolerance_seconds: 300
  )
end
```

### 2. Mount CaptainHook Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount CaptainHook::Engine => "/captain_hook"
  
  # Your webhook will be accessible at:
  # POST /captain_hook/external_service/{token}
end
```

## Sending Webhooks (Outgoing)

### Method 1: Using ActiveSupport::Notifications (Recommended)

This pattern keeps your gem completely decoupled from CaptainHook.

**In Your Gem:**

```ruby
# lib/search_gem/models/search.rb
module SearchGem
  class Search < ApplicationRecord
    after_commit :notify_search_completed, on: :create

    private

    def notify_search_completed
      ActiveSupport::Notifications.instrument(
        "search.completed",
        search_id: id,
        query: query,
        results_count: results_count,
        completed_at: completed_at
      )
    end
  end
end
```

**In Main App:**

```ruby
# config/initializers/search_gem_webhooks.rb

# Subscribe to the gem's notifications
ActiveSupport::Notifications.subscribe("search.completed") do |_name, _start, _finish, _id, payload|
  # Send webhook via CaptainHook
  CaptainHook::GemIntegration.send_webhook(
    provider: "search_service",
    event_type: "search.completed",
    endpoint: "external_service",
    payload: CaptainHook::GemIntegration.build_webhook_payload(
      data: {
        search_id: payload[:search_id],
        query: payload[:query],
        results_count: payload[:results_count]
      }
    ),
    metadata: CaptainHook::GemIntegration.build_webhook_metadata(
      source: "search_gem",
      version: SearchGem::VERSION
    )
  )
end
```

### Method 2: Using GemIntegration Module Directly

If your gem wants to directly integrate with CaptainHook (creating a dependency):

**In Your Gem:**

```ruby
# lib/search_gem/services/webhook_notifier.rb
module SearchGem
  module Services
    class WebhookNotifier
      include CaptainHook::GemIntegration

      def notify_search_completed(search)
        # Check if webhook is configured before sending
        return unless webhook_configured?("external_service")

        send_webhook(
          provider: "search_service",
          event_type: "search.completed",
          endpoint: "external_service",
          payload: build_webhook_payload(
            data: {
              search_id: search.id,
              query: search.query,
              results_count: search.results_count
            }
          ),
          metadata: build_webhook_metadata(
            source: "search_gem",
            version: SearchGem::VERSION
          )
        )
      end
    end
  end
end
```

**Use in Model:**

```ruby
# lib/search_gem/models/search.rb
module SearchGem
  class Search < ApplicationRecord
    after_commit :send_webhook_notification, on: :create

    private

    def send_webhook_notification
      SearchGem::Services::WebhookNotifier.new.notify_search_completed(self)
    end
  end
end
```

### Method 3: Using listen_to_notification Helper

Simplify notification subscription in main app:

```ruby
# config/initializers/search_gem_webhooks.rb
CaptainHook::GemIntegration.listen_to_notification(
  "search.completed",
  provider: "search_service",
  endpoint: "external_service",
  event_type_proc: ->(name) { name }, # Transform notification name to event type
  payload_proc: ->(payload) {         # Transform notification payload
    CaptainHook::GemIntegration.build_webhook_payload(
      data: payload.slice(:search_id, :query, :results_count)
    )
  }
)
```

## Receiving Webhooks (Incoming)

### 1. Create Handler Class in Your Gem

```ruby
# lib/search_gem/handlers/data_updated_handler.rb
module SearchGem
  module Handlers
    class DataUpdatedHandler
      # Handler must implement `handle` method
      # Receives: event (IncomingEvent record), payload (Hash), metadata (Hash)
      def handle(event:, payload:, metadata:)
        Rails.logger.info "Processing webhook for search data update"
        
        # Extract data from payload
        search_id = payload.dig("data", "search_id")
        updated_data = payload.dig("data", "updated_results")
        
        # Update your gem's tables
        search = SearchGem::Search.find_by(id: search_id)
        return unless search

        search.update!(
          external_data: updated_data,
          last_sync_at: Time.current
        )

        # Optionally log metadata
        Rails.logger.info "Updated by: #{metadata[:source]} v#{metadata[:version]}"
      end
    end
  end
end
```

### 2. Register Handler in Main App

**Option A: In Initializer (Recommended)**

```ruby
# config/initializers/search_gem_webhooks.rb

# Register the handler after CaptainHook is configured
ActiveSupport.on_load(:captain_hook_configured) do
  CaptainHook::GemIntegration.register_webhook_handler(
    provider: "external_service",
    event_type: "data.updated",
    handler_class: "SearchGem::Handlers::DataUpdatedHandler",
    async: true,
    priority: 50,
    retry_delays: [30, 60, 300],
    max_attempts: 3
  )
end
```

**Option B: In Your Gem's Engine**

```ruby
# lib/search_gem/engine.rb
module SearchGem
  class Engine < ::Rails::Engine
    isolate_namespace SearchGem

    initializer "search_gem.register_webhook_handlers" do
      ActiveSupport.on_load(:captain_hook_configured) do
        CaptainHook::GemIntegration.register_webhook_handler(
          provider: "external_service",
          event_type: "data.updated",
          handler_class: "SearchGem::Handlers::DataUpdatedHandler",
          async: true,
          priority: 50
        )
      end
    end
  end
end
```

### 3. Handler Options

```ruby
CaptainHook::GemIntegration.register_webhook_handler(
  provider: "external_service",       # Provider name (must match incoming webhook)
  event_type: "data.updated",         # Event type to handle
  handler_class: "MyGem::Handler",    # Handler class name or class object
  async: true,                        # Process asynchronously (default: true)
  priority: 50,                       # Lower = higher priority (default: 100)
  retry_delays: [30, 60, 300],        # Retry delays in seconds
  max_attempts: 3                     # Max retry attempts (default: 5)
)
```

## Complete Example

Let's walk through a complete example with a search gem communicating with an external lookup service.

### Scenario

1. User searches in SearchGem
2. SearchGem emits notification
3. Main app sends webhook to external lookup service
4. External service processes and sends back enriched data
5. CaptainHook receives response and routes to handler
6. SearchGem handler updates search results with enriched data

### 1. SearchGem - Emit Event

```ruby
# lib/search_gem/models/search.rb
module SearchGem
  class Search < ApplicationRecord
    after_commit :emit_search_event, on: :create

    private

    def emit_search_event
      # Use after_commit to ensure transaction is complete
      ActiveSupport::Notifications.instrument(
        "search_gem.search.created",
        search_id: id,
        query: query,
        user_id: user_id
      )
    end
  end
end
```

### 2. Main App - Subscribe and Send Webhook

```ruby
# config/initializers/search_gem_webhooks.rb

# Configure CaptainHook endpoints
CaptainHook.configure do |config|
  # Outgoing: where we send webhooks TO
  config.register_outgoing_endpoint(
    "lookup_service",
    base_url: ENV["LOOKUP_SERVICE_URL"],
    signing_secret: ENV["LOOKUP_SERVICE_SECRET"]
  )

  # Incoming: where we receive webhooks FROM
  config.register_provider(
    "lookup_service",
    token: ENV["LOOKUP_SERVICE_TOKEN"],
    signing_secret: ENV["LOOKUP_SERVICE_SECRET"],
    adapter_class: "CaptainHook::Adapters::Base"
  )
end

# Subscribe to SearchGem notifications
ActiveSupport::Notifications.subscribe("search_gem.search.created") do |_name, _start, _finish, _id, payload|
  CaptainHook::GemIntegration.send_webhook(
    provider: "search_gem",
    event_type: "search.created",
    endpoint: "lookup_service",
    payload: {
      id: SecureRandom.uuid,
      timestamp: Time.current.iso8601,
      data: {
        search_id: payload[:search_id],
        query: payload[:query]
      }
    },
    metadata: {
      source: "search_gem",
      callback_url: "#{ENV['APP_URL']}/captain_hook/lookup_service/#{ENV['LOOKUP_SERVICE_TOKEN']}"
    }
  )
end
```

### 3. External Service - Process and Respond

The external service receives the webhook at the configured URL, processes it, and sends back a webhook:

```ruby
# External service code (not in your app)
# POST to: https://your-app.com/captain_hook/lookup_service/{token}

{
  "id": "evt_response_123",
  "timestamp": "2025-01-01T12:00:00Z",
  "type": "lookup.completed",
  "data": {
    "search_id": 123,
    "enriched_results": [
      { "title": "Result 1", "score": 0.95 },
      { "title": "Result 2", "score": 0.87 }
    ]
  }
}
```

### 4. SearchGem - Create Handler

```ruby
# lib/search_gem/handlers/lookup_completed_handler.rb
module SearchGem
  module Handlers
    class LookupCompletedHandler
      def handle(event:, payload:, metadata:)
        search_id = payload.dig("data", "search_id")
        enriched_results = payload.dig("data", "enriched_results")

        search = SearchGem::Search.find_by(id: search_id)
        return unless search

        # Update search with enriched results
        search.update!(
          enriched_results: enriched_results,
          enriched_at: Time.current,
          status: "completed"
        )

        Rails.logger.info "Search #{search_id} enriched with #{enriched_results.size} results"
      end
    end
  end
end
```

### 5. Main App - Register Handler

```ruby
# config/initializers/search_gem_webhooks.rb (continued)

ActiveSupport.on_load(:captain_hook_configured) do
  CaptainHook::GemIntegration.register_webhook_handler(
    provider: "lookup_service",
    event_type: "lookup.completed",
    handler_class: "SearchGem::Handlers::LookupCompletedHandler",
    async: true,
    priority: 50
  )
end
```

### 6. Flow Summary

```
1. User creates search
   → SearchGem::Search.create(query: "ruby")
   
2. Model triggers after_commit
   → emit_search_event
   
3. ActiveSupport::Notifications emitted
   → "search_gem.search.created"
   
4. Main app subscriber receives notification
   → CaptainHook::GemIntegration.send_webhook
   
5. CaptainHook creates OutgoingEvent
   → Enqueues OutgoingJob
   
6. OutgoingJob sends HTTP POST
   → to ENV["LOOKUP_SERVICE_URL"]
   
7. External service receives webhook
   → Processes search query
   → Sends response back to /captain_hook/lookup_service/{token}
   
8. CaptainHook receives incoming webhook
   → Verifies signature
   → Creates IncomingEvent
   → Routes to SearchGem::Handlers::LookupCompletedHandler
   
9. Handler updates SearchGem tables
   → search.update!(enriched_results: ...)
   
10. Search UI can now display enriched results
```

## Best Practices

### 1. Use after_commit, Not after_save

Always use `after_commit` instead of `after_save` to ensure the database transaction is complete:

```ruby
# ✅ GOOD - Transaction is committed
after_commit :emit_event, on: :create

# ❌ BAD - May send webhook before transaction commits
after_save :emit_event
```

### 2. Keep Gems Decoupled

**Recommended Pattern:** Use ActiveSupport::Notifications in gems, subscribe in main app

```ruby
# In Gem: No dependency on CaptainHook
ActiveSupport::Notifications.instrument("my_gem.event", data)

# In Main App: Handles webhook integration
ActiveSupport::Notifications.subscribe("my_gem.event") do |_, _, _, _, payload|
  CaptainHook::GemIntegration.send_webhook(...)
end
```

### 3. Include Idempotency Keys

Always include unique IDs in webhooks for idempotency:

```ruby
payload: {
  id: SecureRandom.uuid,  # Unique event ID
  timestamp: Time.current.iso8601,
  data: { ... }
}
```

### 4. Handle Errors Gracefully

Handlers should handle errors without raising exceptions:

```ruby
def handle(event:, payload:, metadata:)
  search = SearchGem::Search.find_by(id: payload.dig("data", "search_id"))
  
  unless search
    Rails.logger.warn "Search not found: #{payload.dig('data', 'search_id')}"
    return # Exit gracefully, don't raise
  end
  
  search.update!(data: payload["data"])
rescue ActiveRecord::RecordInvalid => e
  Rails.logger.error "Failed to update search: #{e.message}"
  # Don't re-raise - let CaptainHook handle retries
end
```

### 5. Use Metadata for Tracking

Include source and version information:

```ruby
metadata: CaptainHook::GemIntegration.build_webhook_metadata(
  source: "search_gem",
  version: SearchGem::VERSION,
  additional: {
    environment: Rails.env,
    user_id: current_user&.id
  }
)
```

### 6. Configure Both Outgoing and Incoming

For bidirectional communication, configure both endpoints:

```ruby
CaptainHook.configure do |config|
  # Send webhooks TO this service
  config.register_outgoing_endpoint(
    "external_service",
    base_url: ENV["EXTERNAL_SERVICE_URL"],
    signing_secret: ENV["SHARED_SECRET"]
  )

  # Receive webhooks FROM this service
  config.register_provider(
    "external_service",
    token: ENV["WEBHOOK_TOKEN"],
    signing_secret: ENV["SHARED_SECRET"],  # Same secret for both directions
    adapter_class: "CaptainHook::Adapters::Base"
  )
end
```

### 7. Test Webhook Flow

Test the complete flow in your test suite:

```ruby
test "search triggers webhook and handles response" do
  # Setup: Subscribe to notifications
  events = []
  ActiveSupport::Notifications.subscribe("search_gem.search.created") do |_, _, _, _, payload|
    events << payload
  end

  # Act: Create search
  search = SearchGem::Search.create!(query: "ruby")

  # Assert: Notification emitted
  assert_equal 1, events.size
  assert_equal search.id, events.first[:search_id]

  # Simulate incoming webhook
  post captain_hook_incoming_url(
    provider: "lookup_service",
    token: ENV["LOOKUP_SERVICE_TOKEN"]
  ), params: {
    id: "evt_123",
    type: "lookup.completed",
    data: {
      search_id: search.id,
      enriched_results: [{ title: "Result" }]
    }
  }

  # Assert: Handler updated search
  search.reload
  assert_equal "completed", search.status
  assert_equal 1, search.enriched_results.size
end
```

## Testing

### Test Sending Webhooks

```ruby
# test/services/webhook_notifier_test.rb
class WebhookNotifierTest < ActiveSupport::TestCase
  include CaptainHook::GemIntegration

  test "sends webhook when search completed" do
    search = searches(:one)

    assert_difference "CaptainHook::OutgoingEvent.count", 1 do
      send_webhook(
        provider: "search_gem",
        event_type: "search.completed",
        endpoint: "lookup_service",
        payload: { search_id: search.id }
      )
    end

    event = CaptainHook::OutgoingEvent.last
    assert_equal "search_gem", event.provider
    assert_equal "search.completed", event.event_type
    assert_equal search.id, event.payload["search_id"]
  end
end
```

### Test Receiving Webhooks

```ruby
# test/handlers/lookup_completed_handler_test.rb
class LookupCompletedHandlerTest < ActiveSupport::TestCase
  test "handles incoming webhook" do
    search = searches(:one)
    
    handler = SearchGem::Handlers::LookupCompletedHandler.new
    
    event = captain_hook_incoming_events(:one)
    payload = {
      "data" => {
        "search_id" => search.id,
        "enriched_results" => [{ "title" => "Result 1" }]
      }
    }
    
    handler.handle(event: event, payload: payload, metadata: {})
    
    search.reload
    assert_equal "completed", search.status
    assert_equal 1, search.enriched_results.size
  end
end
```

### Test Notification Subscription

```ruby
# test/initializers/search_gem_webhooks_test.rb
class SearchGemWebhooksTest < ActiveSupport::TestCase
  test "subscribes to search created notifications" do
    assert_difference "CaptainHook::OutgoingEvent.count", 1 do
      ActiveSupport::Notifications.instrument(
        "search_gem.search.created",
        search_id: 1,
        query: "ruby"
      )
    end
  end
end
```

## Troubleshooting

### Webhooks Not Being Sent

1. Check endpoint configuration:
   ```ruby
   CaptainHook.configuration.outgoing_endpoint("my_endpoint")
   # Should return an OutgoingEndpoint object
   ```

2. Check if OutgoingEvent was created:
   ```ruby
   CaptainHook::OutgoingEvent.last
   ```

3. Check job queue:
   ```ruby
   # If using Sidekiq
   Sidekiq::Queue.new("default").size
   ```

### Webhooks Not Being Received

1. Check provider configuration:
   ```ruby
   CaptainHook.configuration.provider("my_provider")
   # Should return a ProviderConfig object
   ```

2. Check IncomingEvent was created:
   ```ruby
   CaptainHook::IncomingEvent.last
   ```

3. Check handler registration:
   ```ruby
   CaptainHook.handler_registry.handlers_for(
     provider: "my_provider",
     event_type: "my.event"
   )
   # Should return array of handler configs
   ```

### Handler Not Executing

1. Verify handler is registered:
   ```ruby
   CaptainHook.handler_registry.handlers_registered?(
     provider: "my_provider",
     event_type: "my.event"
   )
   ```

2. Check IncomingEventHandler records:
   ```ruby
   CaptainHook::IncomingEventHandler
     .where(handler_class: "MyGem::Handler")
     .order(created_at: :desc)
     .first
   ```

3. Check logs for errors:
   ```bash
   tail -f log/development.log | grep "CaptainHook"
   ```

## Advanced Usage

### Multiple Handlers for Same Event

You can register multiple handlers for the same event type with different priorities:

```ruby
# High priority - runs first
CaptainHook::GemIntegration.register_webhook_handler(
  provider: "external_service",
  event_type: "data.updated",
  handler_class: "SearchGem::Handlers::LoggingHandler",
  priority: 1
)

# Medium priority - runs second
CaptainHook::GemIntegration.register_webhook_handler(
  provider: "external_service",
  event_type: "data.updated",
  handler_class: "SearchGem::Handlers::DataUpdateHandler",
  priority: 50
)

# Low priority - runs last
CaptainHook::GemIntegration.register_webhook_handler(
  provider: "external_service",
  event_type: "data.updated",
  handler_class: "SearchGem::Handlers::NotificationHandler",
  priority: 100
)
```

### Conditional Webhook Sending

Only send webhooks when certain conditions are met:

```ruby
def emit_search_event
  return unless should_send_webhook?
  
  ActiveSupport::Notifications.instrument("search_gem.search.created", ...)
end

def should_send_webhook?
  # Check if feature is enabled
  return false unless SearchGem.configuration.webhooks_enabled
  
  # Check if endpoint is configured
  CaptainHook::GemIntegration.webhook_configured?("lookup_service")
end
```

### Dynamic Endpoint Selection

Select endpoint based on environment or other criteria:

```ruby
def notify_search_completed(search)
  endpoint = if Rails.env.production?
               "production_endpoint"
             else
               "staging_endpoint"
             end
  
  CaptainHook::GemIntegration.send_webhook(
    provider: "search_gem",
    event_type: "search.completed",
    endpoint: endpoint,
    payload: search_payload(search)
  )
end
```

## Support

For issues or questions:
- Check the [main README](../README.md)
- Review the [integration guide](integration_from_other_gems.md)
- Open an issue on GitHub
- Review the test suite for examples
