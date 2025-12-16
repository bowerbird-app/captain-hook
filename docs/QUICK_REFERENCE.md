# Inter-Gem Communication Quick Reference

Quick reference for setting up inter-gem communication with CaptainHook.

## Quick Setup (5 Steps)

### 1. Configure CaptainHook

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  # Outgoing: where webhooks are sent TO
  config.register_outgoing_endpoint(
    "external_service",
    base_url: ENV["EXTERNAL_SERVICE_URL"],
    signing_secret: ENV["SHARED_SECRET"]
  )

  # Incoming: where webhooks are received FROM
  config.register_provider(
    "external_service",
    token: ENV["WEBHOOK_TOKEN"],
    signing_secret: ENV["SHARED_SECRET"],
    adapter_class: "CaptainHook::Adapters::Base"
  )
end
```

### 2. Emit Event in Your Gem

```ruby
# lib/my_gem/models/resource.rb
after_commit :emit_event, on: :create

def emit_event
  ActiveSupport::Notifications.instrument(
    "my_gem.resource.created",
    resource_id: id,
    data: attributes
  )
end
```

### 3. Subscribe and Send Webhook

```ruby
# config/initializers/my_gem_webhooks.rb
ActiveSupport::Notifications.subscribe("my_gem.resource.created") do |_, _, _, _, payload|
  CaptainHook::GemIntegration.send_webhook(
    provider: "my_gem",
    event_type: "resource.created",
    endpoint: "external_service",
    payload: { data: payload }
  )
end
```

### 4. Create Handler

```ruby
# lib/my_gem/handlers/response_handler.rb
module MyGem
  module Handlers
    class ResponseHandler
      def handle(event:, payload:, metadata:)
        resource_id = payload.dig("data", "resource_id")
        resource = MyGem::Resource.find_by(id: resource_id)
        resource&.update!(status: "processed")
      end
    end
  end
end
```

### 5. Register Handler

```ruby
# config/initializers/my_gem_webhooks.rb
ActiveSupport.on_load(:captain_hook_configured) do
  CaptainHook::GemIntegration.register_webhook_handler(
    provider: "external_service",
    event_type: "response.received",
    handler_class: "MyGem::Handlers::ResponseHandler"
  )
end
```

## Common Methods

### Send Webhook

```ruby
CaptainHook::GemIntegration.send_webhook(
  provider: "my_gem",              # Provider name
  event_type: "resource.created",  # Event type
  endpoint: "external_service",    # Endpoint name (from config)
  payload: { data: { ... } },      # Webhook payload
  headers: {},                     # Optional custom headers
  metadata: {},                    # Optional metadata
  async: true                      # Send asynchronously (default)
)
```

### Register Handler

```ruby
CaptainHook::GemIntegration.register_webhook_handler(
  provider: "external_service",         # Provider name
  event_type: "response.received",      # Event type to handle
  handler_class: "MyGem::Handler",      # Handler class
  async: true,                          # Process async (default)
  priority: 50,                         # Lower = higher priority
  retry_delays: [30, 60, 300],         # Retry delays in seconds
  max_attempts: 3                       # Max retry attempts
)
```

### Build Webhook Payload

```ruby
CaptainHook::GemIntegration.build_webhook_payload(
  data: { resource_id: 1, action: "created" },
  event_id: "evt_123",                    # Optional
  timestamp: Time.current                  # Optional
)
# Returns:
# {
#   id: "evt_123",
#   timestamp: "2025-01-01T00:00:00Z",
#   data: { resource_id: 1, action: "created" }
# }
```

### Build Webhook Metadata

```ruby
CaptainHook::GemIntegration.build_webhook_metadata(
  source: "my_gem",
  version: MyGem::VERSION,
  additional: { environment: "production" }
)
# Returns:
# {
#   source: "my_gem",
#   version: "1.0.0",
#   triggered_at: "2025-01-01T00:00:00Z",
#   environment: "production"
# }
```

### Check If Webhook Configured

```ruby
if CaptainHook::GemIntegration.webhook_configured?("external_service")
  # Send webhook
end
```

### Get Webhook URL

```ruby
url = CaptainHook::GemIntegration.webhook_url("my_provider")
# Returns: "/captain_hook/my_provider/token123"
```

### Listen to Notification

```ruby
CaptainHook::GemIntegration.listen_to_notification(
  "my_gem.event",
  provider: "my_gem",
  endpoint: "external_service",
  event_type_proc: ->(name) { name.gsub("_", ".") },
  payload_proc: ->(payload) { payload.slice(:id, :type) }
)
```

## Handler Template

```ruby
module MyGem
  module Handlers
    class MyHandler
      # Required method signature
      def handle(event:, payload:, metadata:)
        # Extract data
        resource_id = payload.dig("data", "resource_id")
        
        # Find record
        resource = MyGem::Resource.find_by(id: resource_id)
        return unless resource
        
        # Update record
        resource.update!(
          status: "processed",
          processed_at: Time.current
        )
        
        # Log
        Rails.logger.info "Processed webhook for resource #{resource_id}"
      end
    end
  end
end
```

## Configuration Examples

### Bidirectional Communication

```ruby
# Same service sends and receives webhooks
CaptainHook.configure do |config|
  # Outgoing
  config.register_outgoing_endpoint(
    "partner_service",
    base_url: "https://partner.com/webhooks",
    signing_secret: ENV["SHARED_SECRET"]
  )

  # Incoming
  config.register_provider(
    "partner_service",
    token: ENV["WEBHOOK_TOKEN"],
    signing_secret: ENV["SHARED_SECRET"],  # Same secret
    adapter_class: "CaptainHook::Adapters::Base"
  )
end

# Webhook URL: https://your-app.com/captain_hook/partner_service/{token}
```

### Multiple Environments

```ruby
# Development/Staging
config.register_outgoing_endpoint(
  "staging_service",
  base_url: "https://staging.partner.com/webhooks",
  signing_secret: ENV["STAGING_SECRET"]
)

# Production
config.register_outgoing_endpoint(
  "production_service",
  base_url: "https://api.partner.com/webhooks",
  signing_secret: ENV["PRODUCTION_SECRET"]
)
```

## Model Callback Best Practices

### ✅ Correct - Use after_commit

```ruby
# Ensures database transaction is committed before webhook
after_commit :emit_event, on: :create

def emit_event
  ActiveSupport::Notifications.instrument("my_gem.created", ...)
end
```

### ❌ Incorrect - Don't use after_save

```ruby
# May send webhook before transaction commits
after_save :emit_event

def emit_event
  ActiveSupport::Notifications.instrument("my_gem.created", ...)
end
```

### ✅ Conditional Emission

```ruby
after_commit :emit_event, on: :create, if: :should_emit?

def should_emit?
  status == "active" && webhook_enabled?
end
```

## Error Handling

### In Handlers

```ruby
def handle(event:, payload:, metadata:)
  resource = MyGem::Resource.find_by(id: payload.dig("data", "id"))
  
  unless resource
    Rails.logger.warn "Resource not found"
    return  # Exit gracefully
  end
  
  resource.update!(status: "processed")
rescue ActiveRecord::RecordInvalid => e
  Rails.logger.error "Update failed: #{e.message}"
  # Don't re-raise - CaptainHook handles retries
end
```

### In Webhook Sending

```ruby
def send_notification
  return unless webhook_configured?("external_service")
  
  CaptainHook::GemIntegration.send_webhook(...)
rescue StandardError => e
  Rails.logger.error "Webhook failed: #{e.message}"
  # Handle error appropriately
end
```

## Testing

### Test Webhook Sending

```ruby
test "sends webhook on create" do
  assert_difference "CaptainHook::OutgoingEvent.count", 1 do
    MyGem::Resource.create!(name: "Test")
  end
  
  event = CaptainHook::OutgoingEvent.last
  assert_equal "my_gem", event.provider
  assert_equal "resource.created", event.event_type
end
```

### Test Handler

```ruby
test "handler processes webhook" do
  resource = resources(:one)
  
  handler = MyGem::Handlers::MyHandler.new
  event = captain_hook_incoming_events(:one)
  payload = { "data" => { "resource_id" => resource.id } }
  
  handler.handle(event: event, payload: payload, metadata: {})
  
  resource.reload
  assert_equal "processed", resource.status
end
```

### Test Notification

```ruby
test "notification triggers webhook" do
  assert_difference "CaptainHook::OutgoingEvent.count", 1 do
    ActiveSupport::Notifications.instrument(
      "my_gem.event",
      resource_id: 1
    )
  end
end
```

## Debugging

### Check Endpoint Configuration

```ruby
CaptainHook.configuration.outgoing_endpoint("my_endpoint")
# => #<CaptainHook::OutgoingEndpoint ...>
```

### Check Provider Configuration

```ruby
CaptainHook.configuration.provider("my_provider")
# => #<CaptainHook::ProviderConfig ...>
```

### Check Handler Registration

```ruby
CaptainHook.handler_registry.handlers_for(
  provider: "my_provider",
  event_type: "my.event"
)
# => [#<CaptainHook::HandlerRegistry::HandlerConfig ...>]
```

### Check Recent Events

```ruby
# Outgoing
CaptainHook::OutgoingEvent.recent.limit(10)

# Incoming
CaptainHook::IncomingEvent.recent.limit(10)
```

### Check Handler Executions

```ruby
CaptainHook::IncomingEventHandler
  .where(handler_class: "MyGem::Handler")
  .order(created_at: :desc)
  .limit(10)
```

## Common Issues

### Issue: Webhook Not Sent

**Check:**
1. Is endpoint configured? `webhook_configured?("endpoint")`
2. Was OutgoingEvent created? `OutgoingEvent.last`
3. Is job queue running? Check background job system

### Issue: Webhook Not Received

**Check:**
1. Is provider configured? `configuration.provider("provider")`
2. Is token correct in webhook URL?
3. Is signature verification passing? Check adapter

### Issue: Handler Not Executing

**Check:**
1. Is handler registered? `handler_registry.handlers_registered?(...)`
2. Does handler class exist? `"MyGem::Handler".constantize`
3. Does handle method exist? Check method signature

## Environment Variables

```bash
# Outgoing webhook configuration
EXTERNAL_SERVICE_URL=https://api.example.com/webhooks
EXTERNAL_SERVICE_SECRET=your-signing-secret

# Incoming webhook configuration
WEBHOOK_TOKEN=your-unique-token
SHARED_SECRET=your-signing-secret  # Can be same for bidirectional

# Optional: App URL for callbacks
APP_URL=https://your-app.com
```

## File Locations

```
config/
  initializers/
    captain_hook.rb              # CaptainHook configuration
    my_gem_webhooks.rb           # Gem webhook subscriptions

lib/
  my_gem/
    models/
      resource.rb                # Emit notifications
    handlers/
      my_handler.rb             # Webhook handlers
    services/
      webhook_notifier.rb       # Optional: webhook service
```

## Next Steps

- Read full guide: [INTER_GEM_COMMUNICATION.md](INTER_GEM_COMMUNICATION.md)
- Review examples in test/dummy app
- Check [integration_from_other_gems.md](integration_from_other_gems.md)
- See [README.md](../README.md) for general CaptainHook usage

## Support

For issues or questions:
- Open an issue on GitHub
- Check existing documentation
- Review the test suite for examples
