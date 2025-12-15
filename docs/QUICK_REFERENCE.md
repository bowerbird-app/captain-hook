# Captain Hook - Quick Reference for Inter-Gem Communication

This quick reference provides essential code snippets for using Captain Hook to enable webhook communication between Rails gems.

---

## For Gem Authors: Sending Webhooks (Outgoing)

### 1. Include the Helper Module

```ruby
# lib/your_gem/services/webhook_notifier.rb
module YourGem
  module Services
    class WebhookNotifier
      include CaptainHook::GemIntegration

      def notify_resource_created(resource)
        send_webhook(
          provider: "your_gem_webhooks",
          event_type: "resource.created",
          payload: build_webhook_payload(resource)
        )
      end
    end
  end
end
```

### 2. Trigger from Model Callbacks

```ruby
# app/models/your_gem/resource.rb
module YourGem
  class Resource < ApplicationRecord
    after_commit :send_webhook_notification, on: :create

    private

    def send_webhook_notification
      YourGem::Services::WebhookNotifier.new.notify_resource_created(self)
    rescue StandardError => e
      Rails.logger.error "Webhook failed: #{e.message}"
    end
  end
end
```

### 3. Configure in Host Application

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  config.register_outgoing_endpoint(
    "your_gem_webhooks",
    base_url: ENV["YOUR_GEM_WEBHOOK_URL"],
    signing_secret: ENV["YOUR_GEM_WEBHOOK_SECRET"],
    signing_header: "X-YourGem-Signature",
    timestamp_header: "X-YourGem-Timestamp"
  )
end
```

---

## For Gem Authors: Receiving Webhooks (Incoming)

### 1. Create a Handler

```ruby
# lib/your_gem/handlers/resource_updated_handler.rb
module YourGem
  module Handlers
    class ResourceUpdatedHandler
      def handle(event:, payload:, metadata:)
        resource_id = payload["id"]
        resource = YourGem::Resource.find_by(external_id: resource_id)

        if resource
          resource.update!(
            name: payload["name"],
            status: payload["status"]
          )
        end
      rescue StandardError => e
        Rails.logger.error "Handler error: #{e.message}"
        raise  # Re-raise to trigger retry
      end
    end
  end
end
```

### 2. Register Handler in Engine

```ruby
# lib/your_gem/engine.rb
module YourGem
  class Engine < ::Rails::Engine
    include CaptainHook::GemIntegration

    isolate_namespace YourGem

    initializer "your_gem.register_webhooks" do
      ActiveSupport.on_load(:captain_hook_configured) do
        register_webhook_handler(
          provider: "external_service",
          event_type: "resource.updated",
          handler_class: "YourGem::Handlers::ResourceUpdatedHandler",
          priority: 100
        )
      end
    end
  end
end
```

### 3. Configure Provider in Host Application

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  config.register_provider(
    "external_service",
    token: ENV["EXTERNAL_SERVICE_TOKEN"],
    signing_secret: ENV["EXTERNAL_SERVICE_SECRET"],
    adapter_class: "CaptainHook::Adapters::WebhookSite"
  )
end
```

---

## Gem-to-Gem Communication Example

### Country Gem (Sender)

```ruby
# When country is updated, send webhook
module CountryGem
  class Country < ApplicationRecord
    include CaptainHook::GemIntegration

    after_commit :broadcast_update, on: :update

    private

    def broadcast_update
      send_webhook(
        provider: "country_gem_internal",
        event_type: "country.updated",
        payload: {
          id: id,
          code: code,
          name: name,
          population: population
        }
      )
    end
  end
end
```

### Location Gem (Receiver)

```ruby
# Receive country updates and sync locations
module LocationGem
  class Engine < ::Rails::Engine
    include CaptainHook::GemIntegration

    initializer "location_gem.webhooks" do
      ActiveSupport.on_load(:captain_hook_configured) do
        register_webhook_handler(
          provider: "country_gem_internal",
          event_type: "country.updated",
          handler_class: "LocationGem::Handlers::CountryUpdatedHandler"
        )
      end
    end
  end

  module Handlers
    class CountryUpdatedHandler
      def handle(event:, payload:, metadata:)
        LocationGem::Location
          .where(country_code: payload["code"])
          .update_all(country_name: payload["name"])
      end
    end
  end
end
```

### Host Application Configuration

```ruby
# config/initializers/inter_gem_webhooks.rb
CaptainHook.configure do |config|
  # Outgoing: Country Gem -> Captain Hook
  config.register_outgoing_endpoint(
    "country_gem_internal",
    base_url: "#{ENV['APP_URL']}/captain_hook/country_gem_internal/#{ENV['TOKEN']}",
    signing_secret: ENV["COUNTRY_WEBHOOK_SECRET"]
  )

  # Incoming: Captain Hook -> Location Gem
  config.register_provider(
    "country_gem_internal",
    token: ENV["TOKEN"],
    signing_secret: ENV["COUNTRY_WEBHOOK_SECRET"],
    adapter_class: "CaptainHook::Adapters::WebhookSite"
  )
end
```

---

## Helper Methods Reference

```ruby
# Include the module
include CaptainHook::GemIntegration

# Or use as module functions
CaptainHook::GemIntegration.send_webhook(...)

# Send a webhook
send_webhook(
  provider: "endpoint_name",
  event_type: "resource.created",
  payload: { id: 1, name: "Example" },
  metadata: { custom: "data" },
  headers: { "X-Custom" => "header" },
  async: true  # true = background job, false = synchronous
)

# Check if webhooks are configured
if webhook_configured?("endpoint_name")
  send_webhook(...)
end

# Get configured webhook URL
url = webhook_url("endpoint_name")

# Register a handler
register_webhook_handler(
  provider: "provider_name",
  event_type: "event.type",
  handler_class: "MyGem::Handlers::MyHandler",
  priority: 100,
  async: true,
  retry_delays: [30, 60, 300],
  max_attempts: 5
)

# Build payload from ActiveRecord model
payload = build_webhook_payload(
  my_model,
  additional_fields: { custom: "value" }
)

# Build metadata
metadata = build_webhook_metadata(
  additional_metadata: { source: "my_gem" }
)
```

---

## Webhook URL Pattern

When gems communicate internally, the webhook URL follows this pattern:

```
POST https://your-app.com/captain_hook/:provider/:token
```

Example:
```
POST https://myapp.com/captain_hook/country_gem_internal/abc123token
```

---

## Environment Variables

```bash
# Outgoing webhooks (your gem sending)
YOUR_GEM_WEBHOOK_URL=https://example.com/webhooks
YOUR_GEM_WEBHOOK_SECRET=your_signing_secret

# Incoming webhooks (your gem receiving)
EXTERNAL_PROVIDER_TOKEN=abc123token
EXTERNAL_PROVIDER_SECRET=signing_secret

# For inter-gem communication (internal)
INTERNAL_WEBHOOK_TOKEN=internal_token
INTERNAL_WEBHOOK_SECRET=shared_secret
```

---

## Payload Best Practices

### Sending

```ruby
{
  # Required: Resource identifier
  id: 123,

  # Resource attributes
  code: "US",
  name: "United States",
  
  # Timestamps (ISO 8601)
  created_at: "2024-01-01T10:00:00Z",
  updated_at: "2024-01-01T11:00:00Z",

  # For updates: include changes
  changes: {
    name: ["Old Name", "New Name"]
  }
}
```

### Receiving

```ruby
def handle(event:, payload:, metadata:)
  # Validate required fields
  resource_id = payload["id"] or raise "Missing id"

  # Use find_or_create_by for idempotency
  resource = MyGem::Resource.find_or_create_by!(external_id: resource_id) do |r|
    r.name = payload["name"]
  end

  # Or update existing
  resource = MyGem::Resource.find_by!(external_id: resource_id)
  resource.update!(name: payload["name"])
end
```

---

## Testing

```ruby
# test/services/webhook_notifier_test.rb
require "test_helper"

class WebhookNotifierTest < Minitest::Test
  def test_sends_webhook_when_resource_created
    skip "Requires database setup"
    
    resource = your_gem_resources(:one)
    
    # Test webhook is enqueued
    assert_enqueued_with(job: CaptainHook::OutgoingJob) do
      YourGem::Services::WebhookNotifier.new.notify_resource_created(resource)
    end
  end
end

# test/handlers/resource_handler_test.rb
class ResourceHandlerTest < Minitest::Test
  def test_handles_webhook_successfully
    handler = YourGem::Handlers::ResourceHandler.new
    payload = { "id" => 123, "name" => "Test" }
    
    handler.handle(event: mock_event, payload: payload, metadata: {})
    
    resource = YourGem::Resource.find_by(external_id: 123)
    assert_equal "Test", resource.name
  end
end
```

---

## Documentation Checklist for Your Gem

Include this in your gem's README:

```markdown
## Webhook Integration

This gem integrates with [Captain Hook](https://github.com/bowerbird-app/captain-hook).

### Outgoing Webhooks

Events sent by this gem:
- `resource.created` - When resource is created
- `resource.updated` - When resource is updated
- `resource.deleted` - When resource is deleted

Configuration:
\`\`\`ruby
CaptainHook.configure do |config|
  config.register_outgoing_endpoint(
    "your_gem_webhooks",
    base_url: ENV["YOUR_GEM_WEBHOOK_URL"],
    signing_secret: ENV["YOUR_GEM_WEBHOOK_SECRET"]
  )
end
\`\`\`

### Incoming Webhooks

Events this gem responds to:
- `external.resource.updated` - Updates local records

Configuration:
\`\`\`ruby
CaptainHook.configure do |config|
  config.register_provider(
    "external_provider",
    token: ENV["EXTERNAL_PROVIDER_TOKEN"],
    signing_secret: ENV["EXTERNAL_PROVIDER_SECRET"],
    adapter_class: "CaptainHook::Adapters::WebhookSite"
  )
end
\`\`\`
```

---

## Complete Documentation

For comprehensive guides and examples, see:
- [Inter-Gem Communication Guide](INTER_GEM_COMMUNICATION.md)
- [Gem Integration Examples](GEM_INTEGRATION_EXAMPLES.md)
- [Integration from Other Gems](integration_from_other_gems.md)

---

## Support

- **Repository**: https://github.com/bowerbird-app/captain-hook
- **Issues**: https://github.com/bowerbird-app/captain-hook/issues

---

## Key Takeaways

1. **Use `CaptainHook::GemIntegration` module** for simplified integration
2. **Send webhooks** with `send_webhook()` method
3. **Register handlers** with `register_webhook_handler()` method
4. **Use `after_commit` callbacks** (not `after_save`) for webhooks
5. **Handle errors gracefully** - don't let webhooks break your app
6. **Make handlers idempotent** - they may be retried
7. **Version your payloads** - include gem version in metadata
8. **Document webhook formats** - help other gems integrate
9. **Test thoroughly** - write tests for sending and receiving
10. **Keep payloads small** - send IDs, not entire objects
