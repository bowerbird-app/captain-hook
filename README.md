# CaptainHook Rails Engine

A comprehensive Rails engine for receiving and processing webhooks from external providers with features including signature verification, rate limiting, retry logic, and admin UI.

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

- **Provider Management**
  - Database-backed provider configuration
  - Per-provider security settings
  - Webhook URL generation for sharing with providers
  - Active/inactive status control
  - Support for custom adapters (Stripe, OpenAI, GitHub, etc.)

- **Admin Interface**
  - View and manage providers
  - View incoming events with filtering
  - View registered handlers per provider
  - Monitor event processing status
  - Track handler execution

- **Security Features**
  - HMAC signature verification
  - Timestamp validation (replay attack prevention)
  - Rate limiting per provider
  - Payload size limits
  - Token-based authentication
  - Support for IP whitelisting (planned)

- **Observability**
  - ActiveSupport::Notifications instrumentation
  - Rate limiting stats
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

## Quick Start

### 1. Create a Provider

Via Admin UI: Navigate to `/captain_hook/admin/providers` and click "Add Provider"

Or via Rails console:

```ruby
provider = CaptainHook::Provider.create!(
  name: "stripe",
  display_name: "Stripe",
  description: "Stripe payment webhooks",
  signing_secret: ENV["STRIPE_WEBHOOK_SECRET"],
  adapter_class: "CaptainHook::Adapters::Stripe",
  timestamp_tolerance_seconds: 300,
  max_payload_size_bytes: 1_048_576,
  rate_limit_requests: 100,
  rate_limit_period: 60,
  active: true
)
```

### 2. Get Your Webhook URL

The webhook URL is automatically generated when you create a provider:

```ruby
provider.webhook_url
# => "https://your-app.com/captain_hook/stripe/abc123token..."
```

Share this URL with your provider (e.g., in Stripe's webhook settings).

### 3. Create a Handler

Create a handler class in `app/handlers/`:

```ruby
# app/handlers/stripe_payment_succeeded_handler.rb
class StripePaymentSucceededHandler
  def handle(event:, payload:, metadata:)
    payment_intent_id = payload.dig("data", "object", "id")
    Payment.find_by(stripe_id: payment_intent_id)&.mark_succeeded!
  end
end
```

### 4. Register the Handler

In `config/initializers/captain_hook.rb`:

```ruby
CaptainHook.configure do |config|
  # Admin interface settings
  config.admin_parent_controller = "ApplicationController"
  config.admin_layout = "application"
  
  # Data retention (days)
  config.retention_days = 90
end

# Register handler
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "StripePaymentSucceededHandler",
  priority: 100,
  async: true
)
```

## Configuration

### Provider Settings

Each provider can be configured with:

- **name**: Unique identifier (lowercase, underscores only)
- **display_name**: Human-readable name
- **signing_secret**: Secret for HMAC signature verification
- **adapter_class**: Class for provider-specific signature verification
- **timestamp_tolerance_seconds**: Tolerance window for timestamp validation (prevents replay attacks)
- **max_payload_size_bytes**: Maximum payload size (DoS protection)
- **rate_limit_requests**: Maximum requests per period
- **rate_limit_period**: Time period for rate limiting (seconds)
- **active**: Enable/disable webhook reception

### Handler Registration

Handlers can be configured with:

- **provider**: Provider name (must match a provider)
- **event_type**: Event type to handle (e.g., "payment.succeeded")
- **handler_class**: Class name (as string) that implements the handler
- **priority**: Execution order (lower numbers run first)
- **async**: Whether to run in background job (default: true)
- **max_attempts**: Maximum retry attempts (default: 5)
- **retry_delays**: Array of delays between retries in seconds (default: [30, 60, 300, 900, 3600])

## Adapters

CaptainHook includes adapters for popular webhook providers:

### Stripe

```ruby
CaptainHook::Provider.create!(
  name: "stripe",
  adapter_class: "CaptainHook::Adapters::Stripe",
  signing_secret: ENV["STRIPE_WEBHOOK_SECRET"]
)
```

### Custom Adapter

Create a custom adapter for your provider:

```ruby
module CaptainHook
  module Adapters
    class MyProvider < Base
      def verify_signature(payload:, headers:)
        # Implement signature verification
        expected_sig = generate_signature(payload)
        actual_sig = headers["X-My-Provider-Signature"]
        expected_sig == actual_sig
      end

      def extract_event_id(payload)
        payload["id"]
      end

      def extract_event_type(payload)
        payload["type"]
      end
    end
  end
end
```

## Admin Interface

Access the admin interface at `/captain_hook/admin`:

- **Providers**: Manage webhook providers and view their settings
- **Incoming Events**: View all received webhooks with filtering
- **Handlers**: View registered handlers per provider

## Security

**Never store secrets in the database.** Use environment variables or Rails encrypted credentials.

All incoming webhooks are verified:
1. Provider must be active
2. Token authentication
3. Provider-specific signature verification
4. Timestamp validation (optional, but recommended)
5. Rate limiting (optional, but recommended)
6. Payload size limits (optional, but recommended)

## Testing

Use the included webhook tester at `/webhook_tester` to test your webhook configuration.

## Documentation

- **Implementation Summary**: [docs/IMPLEMENTATION_SUMMARY.md](docs/IMPLEMENTATION_SUMMARY.md)
- **Architecture**: [docs/gem_template/](docs/gem_template/) (template reference)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
