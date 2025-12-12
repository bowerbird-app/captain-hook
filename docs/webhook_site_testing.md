# Webhook.site Testing Guide

This guide demonstrates how to use the `webhook_site` provider for testing both incoming and outgoing webhooks with CaptainHook.

## Overview

The `webhook_site` provider is a testing adapter that integrates with [Webhook.site](https://webhook.site) to enable easy local development and testing of webhook flows without requiring real production services.

**Features:**
- ✅ No signature verification (intentional for testing)
- ✅ Support for custom event types and request IDs
- ✅ Simple rake task for sending test pings
- ✅ Compatible with webhook.site CLI for forwarding
- ✅ Standard payload structure for consistency

## Configuration

### 1. Get Your Webhook.site URL

Visit https://webhook.site and copy your unique URL:
```
https://webhook.site/400efa14-c6e1-4e77-8a54-51e8c4026a5e
```

Your unique token is the last part of the URL (e.g., `400efa14-c6e1-4e77-8a54-51e8c4026a5e`).

### 2. Configure the Provider

Add to your `config/initializers/captain_hook.rb`:

```ruby
CaptainHook.configure do |config|
  # Register webhook_site provider for incoming webhooks
  config.register_provider(
    "webhook_site",
    token: ENV["WEBHOOK_SITE_TOKEN"] || "your-unique-token",
    adapter_class: "CaptainHook::Adapters::WebhookSite",
    timestamp_tolerance_seconds: 300,
    rate_limit_requests: 100,
    rate_limit_period: 60
  )

  # Register outgoing endpoint for webhook_site
  config.register_outgoing_endpoint(
    "webhook_site",
    base_url: ENV["WEBHOOK_SITE_URL"] || "https://webhook.site/your-unique-token",
    signing_secret: nil,  # No signing for webhook.site
    default_headers: {
      "Content-Type" => "application/json",
      "User-Agent" => "CaptainHook/#{CaptainHook::VERSION}",
      "X-Webhook-Provider" => "webhook_site"
    },
    circuit_breaker_enabled: false,
    max_attempts: 3,
    retry_delays: [5, 10, 30]  # Shorter delays for testing
  )
end
```

### 3. Set Environment Variables (Optional)

```bash
export WEBHOOK_SITE_URL=https://webhook.site/your-unique-token
export WEBHOOK_SITE_TOKEN=your-unique-token
```

## Testing Outgoing Webhooks

### Using the Rake Task

The simplest way to test outgoing webhooks:

```bash
cd test/dummy  # or your Rails app directory
bundle exec rails webhook_site:ping
```

This will:
1. Create an `OutgoingEvent` record
2. Enqueue a job to send the webhook
3. Send a POST request to your webhook.site URL
4. Display the event ID for tracking

**Output:**
```
Sending test.ping event to Webhook.site...
URL: https://webhook.site/your-unique-token
Created OutgoingEvent with ID: 550e8400-e29b-41d4-a716-446655440000
Enqueueing job...
Job enqueued! Check Webhook.site for the request.
```

### Payload Structure

The outgoing webhook sends this JSON payload:

```json
{
  "provider": "webhook_site",
  "event_type": "test.ping",
  "sent_at": "2024-01-15T10:30:00Z",
  "request_id": "uuid-here",
  "data": {
    "message": "hello from webhook gem"
  }
}
```

**Headers:**
- `Content-Type: application/json`
- `User-Agent: CaptainHook/0.1.0`
- `X-Webhook-Provider: webhook_site`
- `X-Webhook-Event: test.ping`
- `X-Request-Id: uuid-here`

### Programmatic Usage

```ruby
# In Rails console or your application code
event = CaptainHook::OutgoingEvent.create!(
  provider: "webhook_site",
  event_type: "user.created",
  target_url: "https://webhook.site/your-token",
  payload: {
    provider: "webhook_site",
    event_type: "user.created",
    sent_at: Time.current.iso8601,
    request_id: SecureRandom.uuid,
    data: {
      user_id: 123,
      email: "test@example.com"
    }
  },
  headers: {
    "X-Webhook-Provider" => "webhook_site",
    "X-Webhook-Event" => "user.created"
  }
)

# Enqueue for delivery
CaptainHook::OutgoingJob.perform_later(event.id)

# Or send synchronously (for testing)
CaptainHook::OutgoingJob.new.perform(event.id)
```

### Checking Delivery Status

```ruby
# In Rails console
event = CaptainHook::OutgoingEvent.find('event-id')

event.status           # => "delivered", "failed", "pending"
event.response_code    # => 200
event.response_body    # => "OK"
event.response_time_ms # => 145
event.attempt_count    # => 1
```

## Testing Incoming Webhooks

### Your Incoming Webhook URL

```
POST https://your-app.com/captain_hook/webhook_site/your-unique-token
```

Replace:
- `your-app.com` with your domain (or `localhost:3000` for local testing)
- `your-unique-token` with your webhook.site token

### Testing with curl

```bash
curl -X POST http://localhost:3000/captain_hook/webhook_site/your-unique-token \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Event: test.incoming" \
  -H "X-Request-Id: $(uuidgen)" \
  -d '{
    "event_type": "test.incoming",
    "request_id": "'$(uuidgen)'",
    "data": {
      "message": "Test incoming webhook",
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }
  }'
```

**Expected Response:**

Success (first time):
```json
{
  "id": "event-uuid",
  "status": "received"
}
```

Duplicate (subsequent calls with same request_id):
```json
{
  "id": "event-uuid",
  "status": "duplicate"
}
```

### Testing with webhook.site CLI

The webhook.site CLI can forward requests from webhook.site to your local server.

#### 1. Install the CLI

```bash
npm install -g @webhook.site/cli
# or
yarn global add @webhook.site/cli
```

#### 2. Forward to Local Server

```bash
whcli forward \
  --token=your-unique-token \
  --target=http://localhost:3000/captain_hook/webhook_site/your-unique-token
```

#### 3. Send Requests

Now you can send requests to your webhook.site URL, and they'll be forwarded to your local server:

```bash
curl -X POST https://webhook.site/your-unique-token \
  -H "Content-Type: application/json" \
  -d '{"event_type": "test.incoming", "data": {"message": "via webhook.site"}}'
```

The CLI will forward this to `http://localhost:3000/captain_hook/webhook_site/your-unique-token`.

### Registering Handlers

Create a handler for incoming webhook events:

```ruby
# app/services/webhook_site_test_handler.rb
class WebhookSiteTestHandler
  def handle(event:, payload:, metadata:)
    puts "Received webhook_site event:"
    puts "  Event type: #{event.event_type}"
    puts "  Payload: #{payload.inspect}"
    puts "  Metadata: #{metadata.inspect}"
    
    # Your processing logic here
  end
end
```

Register it:

```ruby
# config/initializers/captain_hook.rb
CaptainHook.register_handler(
  provider: "webhook_site",
  event_type: "test.incoming",
  handler_class: "WebhookSiteTestHandler",
  priority: 100,
  async: true
)
```

### Viewing Incoming Events

```ruby
# In Rails console
events = CaptainHook::IncomingEvent.where(provider: "webhook_site")

events.each do |event|
  puts "Event: #{event.event_type}"
  puts "Status: #{event.status}"
  puts "External ID: #{event.external_id}"
  puts "Payload: #{event.payload.inspect}"
  puts "---"
end
```

## Complete Test Flow

Here's a complete flow for testing both directions:

### 1. Start Your Rails Server

```bash
cd test/dummy  # or your Rails app
bundle exec rails server -p 3000
```

### 2. Configure webhook.site

Visit https://webhook.site and note your unique URL.

### 3. Test Outgoing (Rails → webhook.site)

```bash
export WEBHOOK_SITE_URL=https://webhook.site/your-token
bundle exec rails webhook_site:ping
```

Check webhook.site - you should see the request appear.

### 4. Test Incoming (curl → Rails)

```bash
curl -X POST http://localhost:3000/captain_hook/webhook_site/your-token \
  -H "Content-Type: application/json" \
  -d '{"event_type": "test.incoming", "data": {"source": "curl"}}'
```

Check your Rails logs to see the event being processed.

### 5. Test Round-Trip (webhook.site → Rails)

Start the forwarding:
```bash
whcli forward \
  --token=your-token \
  --target=http://localhost:3000/captain_hook/webhook_site/your-token
```

Send to webhook.site:
```bash
curl -X POST https://webhook.site/your-token \
  -H "Content-Type: application/json" \
  -d '{"event_type": "test.roundtrip", "data": {"source": "webhook.site"}}'
```

The request will appear on webhook.site AND be forwarded to your local Rails app.

## Troubleshooting

### Outgoing Webhooks Not Sending

```ruby
# Check job queue
Sidekiq::Stats.new.queues  # or check your ActiveJob backend

# Check event status
event = CaptainHook::OutgoingEvent.last
event.status
event.error_message
event.attempt_count
```

### Incoming Webhooks Failing

Check Rails logs:
```bash
tail -f test/dummy/log/development.log
```

Common issues:
- Wrong token in URL
- Invalid JSON payload
- Rate limit exceeded

### Events Not Processing

```ruby
# Check handler records
event = CaptainHook::IncomingEvent.last
handlers = event.incoming_event_handlers

handlers.each do |handler|
  puts "Handler: #{handler.handler_class}"
  puts "Status: #{handler.status}"
  puts "Error: #{handler.error_message}"
end
```

## Best Practices

1. **Use Unique Request IDs**: Always include a unique `request_id` in payloads for idempotency
2. **Test Failure Cases**: Simulate failures by using invalid URLs or stopping your server
3. **Monitor Webhook.site**: Keep the webhook.site page open to see requests in real-time
4. **Check Response Times**: Use webhook.site to verify your app responds quickly
5. **Test Retry Logic**: Stop your server, send requests, then restart to see retries

## Security Note

⚠️ **The webhook_site provider is for testing only.**

- No signature verification (verification always returns `true`)
- Uses public webhook.site URLs
- Should never be used in production
- Disable in production environments

```ruby
# config/initializers/captain_hook.rb
unless Rails.env.production?
  # Register webhook_site provider only in dev/test
  config.register_provider("webhook_site", ...)
end
```

## Further Reading

- [Webhook.site Documentation](https://docs.webhook.site/)
- [Webhook.site CLI](https://github.com/webhooksite/cli)
- [CaptainHook Main README](../README.md)
- [Integration Guide](integration_from_other_gems.md)
