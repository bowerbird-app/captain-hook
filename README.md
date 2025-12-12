# CaptainHook Rails Engine

A comprehensive Rails engine for managing webhooks with features including signature verification, rate limiting, circuit breakers, retry logic, and admin UI.

## Features

- **Incoming Webhooks**
  - Idempotency via unique `(provider, external_id)` index
  - Provider-specific signature verification adapters
  - Rate limiting per provider
  - Payload size limits
  - Timestamp validation to prevent replay attacks
  - Handler priority and ordering
  - Automatic retry with exponential backoff
  - Optimistic locking for safe concurrency

- **Outgoing Webhooks**
  - HMAC-SHA256 signature generation
  - Circuit breaker pattern for failing endpoints
  - SSRF protection
  - Retry logic with exponential backoff
  - Response tracking (code, body, time)
  - Optimistic locking for safe concurrency

- **Admin Interface**
  - View incoming and outgoing events
  - Filter and search capabilities
  - Response tracking and error details
  - Configurable authentication

- **Observability**
  - ActiveSupport::Notifications instrumentation
  - Rate limiting stats
  - Circuit breaker state monitoring
  - Comprehensive event tracking

- **Data Retention**
  - Automatic archival of old events
  - Configurable retention period

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'captain_hook'
```

And then execute:

```bash
$ bundle install
```

Run the installer:

```bash
$ rails generate captain_hook:install
```

This will create:
- An initializer at `config/initializers/captain_hook.rb`
- A configuration file at `config/captain_hook.yml`

Run migrations:

```bash
$ rails captain_hook:install:migrations
$ rails db:migrate
```

## Configuration

Configure CaptainHook in `config/initializers/captain_hook.rb`:

```ruby
CaptainHook.configure do |config|
  # Admin interface settings
  config.admin_parent_controller = "ApplicationController"
  config.admin_layout = "application"
  
  # Data retention (days)
  config.retention_days = 90

  # Register incoming webhook providers
  config.register_provider(
    "stripe",
    token: ENV["STRIPE_WEBHOOK_TOKEN"],
    signing_secret: ENV["STRIPE_WEBHOOK_SECRET"],
    adapter_class: "CaptainHook::Adapters::Stripe",
    timestamp_tolerance_seconds: 300,        # 5 minutes
    max_payload_size_bytes: 1_048_576,       # 1MB
    rate_limit_requests: 100,
    rate_limit_period: 60                    # 100 requests per 60 seconds
  )

  # Register outgoing webhook endpoints
  config.register_outgoing_endpoint(
    "production_endpoint",
    base_url: "https://example.com/webhooks",
    signing_secret: ENV["OUTGOING_WEBHOOK_SECRET"],
    signing_header: "X-Captain-Hook-Signature",
    timestamp_header: "X-Captain-Hook-Timestamp",
    default_headers: { "Content-Type" => "application/json" },
    retry_delays: [30, 60, 300, 900, 3600],  # Exponential backoff
    max_attempts: 5,
    circuit_breaker_enabled: true,
    circuit_failure_threshold: 5,
    circuit_cooldown_seconds: 300
  )
end
```

See [docs/integration_from_other_gems.md](docs/integration_from_other_gems.md) for detailed integration examples.

## Quick Start

### 1. Receiving Webhooks

Create a handler:

```ruby
class StripePaymentSucceededHandler
  def handle(event:, payload:, metadata:)
    payment_intent_id = payload.dig("data", "object", "id")
    Payment.find_by(stripe_id: payment_intent_id)&.mark_succeeded!
  end
end
```

Register it:

```ruby
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "StripePaymentSucceededHandler",
  priority: 100
)
```

Your webhook URL: `POST https://your-app.com/captain_hook/stripe/your_token`

### 2. Sending Webhooks

```ruby
event = CaptainHook::OutgoingEvent.create!(
  provider: "production_endpoint",
  event_type: "user.created",
  target_url: "https://example.com/webhooks",
  payload: { user_id: user.id, email: user.email }
)

CaptainHook::OutgoingJob.perform_later(event.id)
```

## Testing with Webhook.site

CaptainHook includes a built-in `webhook_site` provider for easy testing of both incoming and outgoing webhooks.

### Configuration

Set up the webhook_site provider in your initializer:

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  # Register webhook_site provider for testing
  config.register_provider(
    "webhook_site",
    token: ENV["WEBHOOK_SITE_TOKEN"] || "400efa14-c6e1-4e77-8a54-51e8c4026a5e",
    adapter_class: "CaptainHook::Adapters::WebhookSite",
    timestamp_tolerance_seconds: 300,
    rate_limit_requests: 100,
    rate_limit_period: 60
  )

  # Register outgoing endpoint for webhook_site
  config.register_outgoing_endpoint(
    "webhook_site",
    base_url: ENV["WEBHOOK_SITE_URL"] || "https://webhook.site/400efa14-c6e1-4e77-8a54-51e8c4026a5e",
    signing_secret: nil,  # webhook.site doesn't require signatures
    default_headers: {
      "Content-Type" => "application/json",
      "User-Agent" => "CaptainHook/#{CaptainHook::VERSION}",
      "X-Webhook-Provider" => "webhook_site"
    },
    circuit_breaker_enabled: false,
    max_attempts: 3
  )
end
```

### Testing Outgoing Webhooks

Send a test ping to Webhook.site:

```bash
# Set your webhook.site URL (get one from https://webhook.site)
export WEBHOOK_SITE_URL=https://webhook.site/YOUR-UNIQUE-ID
export WEBHOOK_SITE_TOKEN=YOUR-UNIQUE-ID

# Send test ping
cd test/dummy
bundle exec rails webhook_site:ping
```

The task will create an outgoing event with this payload structure:

```json
{
  "provider": "webhook_site",
  "event_type": "test.ping",
  "sent_at": "2024-01-01T12:00:00Z",
  "request_id": "uuid-here",
  "data": {
    "message": "hello from webhook gem"
  }
}
```

### Testing Incoming Webhooks

Your incoming webhook endpoint will be:

```
POST https://your-app.com/captain_hook/webhook_site/YOUR-UNIQUE-ID
```

Test it with curl:

```bash
curl -X POST http://localhost:3000/captain_hook/webhook_site/YOUR-UNIQUE-ID \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Event: test.incoming" \
  -H "X-Request-Id: $(uuidgen)" \
  -d '{
    "event_type": "test.incoming",
    "data": {
      "message": "incoming test"
    }
  }'
```

### Using Webhook.site CLI for Forwarding

Forward webhook.site requests to your local server:

```bash
# Install webhook.site CLI
npm install -g webhook.site-cli

# Forward to local server
whcli forward \
  --token=YOUR-UNIQUE-ID \
  --target=http://localhost:3000/captain_hook/webhook_site/YOUR-UNIQUE-ID
```

This allows you to test the complete flow: send to webhook.site → forwarded to local → processed by CaptainHook.

## Security

**Never store secrets in the database.** Use environment variables or Rails encrypted credentials.

All incoming webhooks are verified:
1. Token authentication
2. Provider-specific signature verification
3. Timestamp validation

Outgoing webhooks include SSRF protection and signature generation.

## Documentation

- **Full README**: See above for comprehensive documentation
- **Integration Guide**: [docs/integration_from_other_gems.md](docs/integration_from_other_gems.md)
- **Architecture**: [docs/gem_template/](docs/gem_template/) (template reference)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
