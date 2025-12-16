# Inter-Gem Communication Example

This directory contains example code demonstrating how to implement inter-gem communication using CaptainHook.

## Overview

This example simulates a hypothetical "SearchGem" that communicates with an external lookup service via webhooks.

## Flow

```
1. User creates SearchRequest
   ↓
2. SearchRequest model emits ActiveSupport::Notifications event
   ↓
3. Main app subscribes to notification and sends webhook via CaptainHook
   ↓
4. External lookup service receives webhook and processes
   ↓
5. External service sends response webhook back
   ↓
6. CaptainHook receives incoming webhook
   ↓
7. SearchResponseHandler processes webhook and updates SearchRequest
   ↓
8. Search is completed with results
```

## Files

### Models

**`app/models/search_request.rb`**
- Represents a search request from a hypothetical gem
- Emits `search_gem.search.requested` notification after creation
- Uses `after_commit` to ensure transaction is complete

**`app/models/search_response_handler.rb`**
- Handler for incoming webhooks from the lookup service
- Updates SearchRequest with results from the webhook
- Demonstrates error handling and graceful failures

### Configuration

**`config/initializers/captain_hook.rb`**
- Configures bidirectional webhook communication
- Registers outgoing endpoint for sending webhooks
- Registers incoming provider for receiving webhooks

**`config/initializers/inter_gem_webhooks.rb`**
- Subscribes to SearchGem notifications
- Sends webhooks when notifications are received
- Registers handlers for incoming webhooks
- Includes detailed comments explaining the flow

### Database

**`db/migrate/20251216000001_create_search_requests.rb`**
- Migration for SearchRequest table
- Includes status tracking and results storage

## Testing the Flow

### 1. Create the database table

```bash
cd test/dummy
bin/rails db:migrate
```

### 2. Start the Rails server

```bash
cd test/dummy
bin/dev
```

### 3. Create a search request

```ruby
# In Rails console
SearchRequest.create!(query: "ruby programming")
```

This will:
1. Emit a notification
2. Send a webhook to the configured lookup service
3. Create an OutgoingEvent record

### 4. Check the outgoing event

```ruby
CaptainHook::OutgoingEvent.last
# => Should show the webhook that was sent
```

### 5. Simulate an incoming webhook

```bash
# POST to the webhook endpoint
curl -X POST http://localhost:3000/captain_hook/lookup_service/example-token \
  -H "Content-Type: application/json" \
  -d '{
    "id": "evt_123",
    "timestamp": "2025-01-01T12:00:00Z",
    "type": "search.completed",
    "data": {
      "search_request_id": 1,
      "results": [
        {"title": "Ruby Programming Guide", "score": 0.95},
        {"title": "Ruby Best Practices", "score": 0.87}
      ]
    }
  }'
```

### 6. Check the search request was updated

```ruby
search = SearchRequest.last
search.status        # => "completed"
search.results       # => [{"title" => "Ruby Programming Guide", ...}, ...]
search.completed_at  # => timestamp
```

## Configuration

Set these environment variables for external service integration:

```bash
# URL where webhooks are sent TO
LOOKUP_SERVICE_URL=https://your-external-service.com/webhooks

# Shared secret for signing webhooks (both directions)
LOOKUP_SERVICE_SECRET=your-secure-secret

# Token for receiving webhooks FROM the service
LOOKUP_SERVICE_TOKEN=your-unique-token

# Your app URL (for callback URLs in metadata)
APP_URL=https://your-app.com
```

For development/testing, these default to example values in the initializers.

## Key Patterns Demonstrated

### 1. Decoupled Gem Design

The SearchRequest model has no knowledge of CaptainHook:

```ruby
# In gem - just emit a notification
ActiveSupport::Notifications.instrument("search_gem.search.requested", data)
```

The main app handles webhook integration:

```ruby
# In main app - subscribe and send webhook
ActiveSupport::Notifications.subscribe("search_gem.search.requested") do |_, _, _, _, payload|
  CaptainHook::GemIntegration.send_webhook(...)
end
```

### 2. Use after_commit, Not after_save

```ruby
# ✅ GOOD - Transaction is complete
after_commit :emit_event, on: :create

# ❌ BAD - May emit before transaction commits
after_save :emit_event
```

### 3. Graceful Error Handling

Handlers should handle errors without raising:

```ruby
def handle(event:, payload:, metadata:)
  resource = find_resource(payload)
  return unless resource  # Exit gracefully if not found
  
  resource.update!(data)
rescue ActiveRecord::RecordInvalid => e
  Rails.logger.error "Update failed: #{e.message}"
  # Don't re-raise - let CaptainHook handle retries
end
```

### 4. Idempotency

Include unique IDs for idempotency:

```ruby
payload: {
  id: SecureRandom.uuid,  # Unique event ID
  timestamp: Time.current.iso8601,
  data: { ... }
}
```

### 5. Metadata for Tracking

Include source and version information:

```ruby
metadata: {
  source: "search_gem",
  version: "1.0.0",
  environment: Rails.env,
  callback_url: "https://app.com/captain_hook/lookup_service/token"
}
```

## Adapting for Your Gem

To adapt this pattern for your own gem:

1. **Replace SearchRequest** with your gem's model
2. **Change notification name** from `search_gem.search.requested` to your event name
3. **Update handler class** to process your specific webhook data
4. **Configure your endpoint** in `captain_hook.rb`
5. **Update payload/metadata** to match your data structure

## Further Reading

- [INTER_GEM_COMMUNICATION.md](../../docs/INTER_GEM_COMMUNICATION.md) - Complete guide
- [QUICK_REFERENCE.md](../../docs/QUICK_REFERENCE.md) - Quick setup reference
- [integration_from_other_gems.md](../../docs/integration_from_other_gems.md) - Integration patterns
- [README.md](../../README.md) - Main CaptainHook documentation
