# ⚓ Captain Hook

A comprehensive Rails engine for managing webhook integrations with features including signature verification, action routing, rate limiting, retry logic, and an admin UI.

## 📋 Table of Contents

- [Features](#-features)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [Usage](#-usage)
  - [Built-in Providers](#built-in-providers)
  - [Creating Actions](#creating-actions)
  - [Adding Custom Providers](#adding-custom-providers)
- [Admin UI](#-admin-ui)
- [Architecture](#-architecture)
- [Testing](#-testing)
- [Contributing](#-contributing)
- [License](#-license)

## ✨ Features

### 🔐 Security
- **Signature Verification** - Validates webhook authenticity using provider-specific signatures
- **Timestamp Validation** - Prevents replay attacks with configurable time windows
- **Rate Limiting** - Protects against DoS with per-provider rate limits
- **Constant-Time Comparison** - Prevents timing attacks during signature verification

### 🎯 Reliability
- **Idempotency** - Automatic deduplication prevents processing duplicate webhooks
- **Retry Logic** - Configurable exponential backoff for failed actions
- **Background Processing** - Non-blocking webhook handling via ActiveJob
- **Circuit Breakers** - Prevents cascading failures
- **Optimistic Locking** - Handles concurrent processing safely

### 🚀 Developer Experience
- **Auto-Discovery** - Automatically finds and registers providers and actions
- **Action Routing** - Maps webhook events to your business logic
- **Admin UI** - Monitor webhook traffic, inspect payloads, retry failures
- **Built-in Providers** - Pre-configured verifiers for Stripe, Square, PayPal
- **Instrumentation** - ActiveSupport notifications for monitoring
- **Test Helpers** - Utilities for testing webhook integrations

### 📊 Observability
- **Event Storage** - Persists all incoming webhooks with full audit trail
- **Action Tracking** - Monitor processing status, attempts, and errors
- **Metrics** - Track success rates, latency, and throughput
- **Debugging Tools** - Inspect payloads, view error messages, retry failed actions

## 🚀 Installation

Add Captain Hook to your Rails application's Gemfile:

```ruby
gem 'captain_hook'
```

Install the gem:

```bash
bundle install
```

Run the setup wizard:

```bash
rails captain_hook:setup
```

The setup wizard will:
1. ✅ Mount the engine in your routes
2. ✅ Create configuration files
3. ✅ Install database migrations
4. ✅ Set up encryption keys for secure credential storage
5. ✅ Create an example provider (in development)

Run migrations:

```bash
rails db:migrate
```

## 🎯 Quick Start

### 1. Configure Your First Provider

Create a provider configuration file at `captain_hook/stripe/stripe.yml`:

```yaml
name: stripe
display_name: Stripe
description: Stripe payment webhooks
verifier_file: stripe.rb  # Built-in verifier
active: true

# Security
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300

# Rate limiting (optional)
rate_limit_requests: 100
rate_limit_period: 60
```

### 2. Create an Action

Create an action to handle specific events at `captain_hook/stripe/actions/payment_intent_succeeded_action.rb`:

```ruby
module Stripe
  class PaymentIntentSucceededAction
    # Define metadata about this action
    def self.details
      {
        description: "Handle successful payment intents",
        event_type: "payment_intent.succeeded",
        priority: 100,
        async: true,
        max_attempts: 5
      }
    end

    # Process the webhook
    def webhook_action(event:, payload:, metadata:)
      payment_intent = payload.dig("data", "object")
      
      # Your business logic here
      order = Order.find_by(payment_intent_id: payment_intent["id"])
      order.mark_as_paid! if order
      
      Rails.logger.info "✅ Processed payment: #{payment_intent['id']}"
    end
  end
end
```

### 3. Scan for Providers and Actions

Run the discovery rake task to register your configuration:

```bash
rails captain_hook:discover
```

### 4. Get Your Webhook URL

Your webhook endpoint is now available at:

```
POST https://yourapp.com/captain_hook/:provider/:token
```

For example, for Stripe:
```
POST https://yourapp.com/captain_hook/stripe/abc123token
```

Find your provider token in the admin UI or by running:

```bash
rails runner "puts CaptainHook::Provider.find_by(name: 'stripe').token"
```

### 5. Configure Your Provider

In your provider's dashboard (e.g., Stripe), add the webhook URL and select the events you want to receive.

## ⚙️ Configuration

### Global Configuration

Create or edit `config/initializers/captain_hook.rb`:

```ruby
CaptainHook.configure do |config|
  # Default rate limits
  config.default_rate_limit_requests = 100
  config.default_rate_limit_period = 60
  
  # Default payload size limit (in bytes)
  config.max_payload_size_bytes = 2.megabytes
  
  # Job queue for processing webhooks
  config.queue_name = :captain_hook_incoming
  
  # Enable/disable admin UI
  config.enable_admin_ui = true
  
  # Retention period for old webhooks
  config.webhook_retention_days = 90
end
```

### Environment Variables

Set these in your `.env` file:

```bash
# Provider signing secrets
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxx
SQUARE_WEBHOOK_SECRET=your_square_secret
PAYPAL_WEBHOOK_ID=your_paypal_webhook_id

# Encryption keys (generated by setup wizard)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=xxxxxxxxxxxxxxxx
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=xxxxxxxxxxxxxxxx
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=xxxxxxxxxxxxxxxx
```

## 📖 Usage

### Built-in Providers

Captain Hook includes pre-configured verifiers for popular webhook providers:

#### Stripe
```yaml
name: stripe
verifier_file: stripe.rb  # Uses CaptainHook::Verifiers::Stripe
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

**Supported events:** All Stripe webhook events  
**Signature header:** `Stripe-Signature`  
**Documentation:** https://stripe.com/docs/webhooks

#### Square
```yaml
name: square
verifier_file: square.rb  # Uses CaptainHook::Verifiers::Square
signing_secret: ENV[SQUARE_WEBHOOK_SECRET]
```

**Supported events:** All Square webhook events  
**Signature header:** `X-Square-Signature`  
**Documentation:** https://developer.squareup.com/docs/webhooks

#### PayPal
```yaml
name: paypal
verifier_file: paypal.rb  # Uses CaptainHook::Verifiers::Paypal
signing_secret: ENV[PAYPAL_WEBHOOK_ID]
```

**Supported events:** All PayPal webhook events  
**Documentation:** https://developer.paypal.com/docs/api-basics/notifications/webhooks/

### Creating Actions

Actions are where your business logic lives. Each action handles a specific event type from a provider.

#### Basic Action Structure

```ruby
module ProviderName
  class EventNameAction
    # Required: Define action metadata
    def self.details
      {
        description: "Human-readable description",
        event_type: "event.type",      # Matches webhook event type
        priority: 100,                   # Lower = higher priority
        async: true,                     # Process in background job
        max_attempts: 5,                 # Retry failed actions
        retry_delays: [30, 60, 300]      # Seconds between retries
      }
    end

    # Required: Process the webhook
    def webhook_action(event:, payload:, metadata:)
      # event: CaptainHook::IncomingEvent record
      # payload: Parsed JSON webhook payload
      # metadata: Additional event metadata
      
      # Your business logic here
    end
  end
end
```

#### Action Example: Stripe Payment Intent

```ruby
module Stripe
  class PaymentIntentSucceededAction
    def self.details
      {
        description: "Process successful payments",
        event_type: "payment_intent.succeeded",
        priority: 50,  # High priority
        async: true,
        max_attempts: 5,
        retry_delays: [30, 60, 300, 900, 3600]
      }
    end

    def webhook_action(event:, payload:, metadata:)
      payment_intent = payload.dig("data", "object")
      
      order = Order.find_by!(
        payment_intent_id: payment_intent["id"]
      )
      
      order.transaction do
        order.update!(
          status: "paid",
          paid_at: Time.current,
          payment_method: payment_intent["payment_method"]
        )
        
        # Send confirmation email
        OrderMailer.payment_confirmed(order).deliver_later
        
        # Update inventory
        order.line_items.each(&:decrement_stock!)
      end
      
      Rails.logger.info "✅ Payment processed: Order ##{order.id}"
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.warn "⚠️  Order not found for payment: #{payment_intent['id']}"
      # Don't retry - order doesn't exist
    end
  end
end
```

#### Wildcard Actions

Handle multiple event types with a single action using wildcards:

```ruby
module Stripe
  class CustomerEventsAction
    def self.details
      {
        description: "Handle all customer events",
        event_type: "customer.*",  # Matches customer.created, customer.updated, etc.
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
      customer_data = payload.dig("data", "object")
      
      case event.event_type
      when "customer.created"
        handle_customer_created(customer_data)
      when "customer.updated"
        handle_customer_updated(customer_data)
      when "customer.deleted"
        handle_customer_deleted(customer_data)
      end
    end
  end
end
```

### Adding Custom Providers

If you need a provider that's not built-in:

#### 1. Create Provider Configuration

`captain_hook/my_provider/my_provider.yml`:

```yaml
name: my_provider
display_name: My Provider
description: Custom webhook provider
verifier_file: my_provider.rb
active: true
signing_secret: ENV[MY_PROVIDER_SECRET]
```

#### 2. Create Custom Verifier

`captain_hook/my_provider/my_provider.rb`:

```ruby
module CaptainHook
  module Verifiers
    class MyProvider < Base
      def verify_signature(payload:, headers:, provider_config:)
        signature = headers["X-My-Provider-Signature"]
        return false unless signature.present?
        
        secret = provider_config.signing_secret
        expected = compute_signature(payload, secret)
        
        secure_compare(signature, expected)
      end
      
      private
      
      def compute_signature(payload, secret)
        OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      end
    end
  end
end
```

#### 3. Create Actions

`captain_hook/my_provider/actions/event_action.rb`:

```ruby
module MyProvider
  class EventAction
    def self.details
      {
        description: "Handle my provider events",
        event_type: "event.type",
        priority: 100,
        async: true,
        max_attempts: 5
      }
    end

    def webhook_action(event:, payload:, metadata:)
      # Your logic here
    end
  end
end
```

## 🎨 Admin UI

Access the admin UI at:

```
http://localhost:3000/captain_hook
```

### Features

- **Dashboard** - Overview of webhook traffic and health
- **Providers** - Manage provider configurations and tokens
- **Events** - Browse all incoming webhooks with filtering
- **Actions** - Monitor action execution status
- **Retry Failed Actions** - Manually retry failed webhook processing
- **Inspect Payloads** - View full webhook JSON payloads
- **Search & Filter** - Find specific webhooks by provider, event type, date

### Securing the Admin UI

Protect the admin UI with authentication:

```ruby
# config/routes.rb
authenticate :user, ->(u) { u.admin? } do
  mount CaptainHook::Engine => "/captain_hook"
end
```

Or use HTTP Basic Auth:

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  config.admin_username = ENV["CAPTAIN_HOOK_ADMIN_USER"]
  config.admin_password = ENV["CAPTAIN_HOOK_ADMIN_PASSWORD"]
end
```

## 🏗️ Architecture

### File Structure

```
your_rails_app/
├── captain_hook/                    # Your webhook configurations
│   ├── stripe/
│   │   ├── stripe.yml              # Provider config
│   │   └── actions/
│   │       ├── payment_intent_succeeded_action.rb
│   │       └── subscription_updated_action.rb
│   ├── square/
│   │   ├── square.yml
│   │   └── actions/
│   │       └── payment_action.rb
│   └── paypal/
│       ├── paypal.yml
│       └── actions/
│           └── order_action.rb
│
├── config/
│   └── initializers/
│       └── captain_hook.rb         # Global configuration
│
└── db/
    └── migrate/
        └── [timestamp]_create_captain_hook_*.rb
```

### Database Schema

Captain Hook uses four main tables:

**captain_hook_providers** - Provider configurations
- `name` - Provider identifier (stripe, square, etc.)
- `token` - Unique webhook URL token
- `active` - Enable/disable provider
- `signing_secret` - Encrypted webhook secret

**captain_hook_incoming_events** - Webhook event log
- `provider` - Provider name
- `external_id` - Provider's event ID
- `event_type` - Event type (payment_intent.succeeded)
- `payload` - Full JSON payload
- `metadata` - Additional event data
- `status` - pending, processing, completed, failed

**captain_hook_actions** - Registered actions
- `provider` - Provider name
- `event_type` - Event type pattern
- `action_class` - Action class name
- `priority` - Execution order
- `async` - Background processing flag
- `max_attempts` - Retry limit

**captain_hook_incoming_event_actions** - Action execution records
- `incoming_event_id` - FK to event
- `action_class` - Action executed
- `status` - pending, processing, succeeded, failed
- `attempt_count` - Number of retry attempts
- `error_message` - Failure reason

### Request Flow

```
1. Webhook arrives → POST /captain_hook/:provider/:token
2. Signature verification → CaptainHook::Verifiers::*
3. Event storage → CaptainHook::IncomingEvent.create!
4. Idempotency check → Duplicate detection by external_id
5. Action discovery → Find matching actions by event_type
6. Action queuing → Create IncomingEventAction records
7. Background processing → IncomingActionJob.perform_later
8. Execute action → YourAction#webhook_action
9. Update status → Mark succeeded/failed
10. Retry on failure → Exponential backoff
```

### Service Layer

Captain Hook uses a service-oriented architecture:

- **ProviderDiscovery** - Scans for provider YAML files
- **ActionDiscovery** - Finds action classes
- **ProviderSync** - Syncs providers to database
- **ActionSync** - Syncs actions to database
- **ActionLookup** - Finds actions for events
- **RateLimiter** - Enforces rate limits
- **VerifierDiscovery** - Locates signature verifiers

## 🧪 Testing

### Testing Your Actions

```ruby
# test/actions/stripe/payment_intent_succeeded_action_test.rb
require "test_helper"

class PaymentIntentSucceededActionTest < ActiveSupport::TestCase
  setup do
    @action = Stripe::PaymentIntentSucceededAction.new
    @event = captain_hook_incoming_events(:payment_intent)
    @payload = {
      "id" => "evt_123",
      "type" => "payment_intent.succeeded",
      "data" => {
        "object" => {
          "id" => "pi_123",
          "amount" => 1000
        }
      }
    }
  end

  test "processes successful payment" do
    @action.webhook_action(
      event: @event,
      payload: @payload,
      metadata: {}
    )
    
    assert @event.reload.completed?
  end
end
```

### Test Helpers

Captain Hook provides test helpers:

```ruby
# Generate valid webhook signature
signature = captain_hook_signature(payload, provider: :stripe)

# Create test event
event = create_captain_hook_event(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  payload: { test: "data" }
)

# Simulate webhook request
post captain_hook_webhook_path(
  provider: "stripe",
  token: @provider.token
),
  params: webhook_payload,
  headers: { "Stripe-Signature" => signature }
```

### Testing Signature Verification

```ruby
# test/verifiers/my_provider_verifier_test.rb
class MyProviderVerifierTest < ActiveSupport::TestCase
  setup do
    @verifier = CaptainHook::Verifiers::MyProvider.new
    @secret = "secret123"
  end

  test "accepts valid signature" do
    payload = '{"event":"test"}'
    signature = compute_signature(payload, @secret)
    
    result = @verifier.verify_signature(
      payload: payload,
      headers: { "X-Signature" => signature },
      provider_config: build_config
    )
    
    assert result
  end

  test "rejects invalid signature" do
    result = @verifier.verify_signature(
      payload: '{"event":"test"}',
      headers: { "X-Signature" => "invalid" },
      provider_config: build_config
    )
    
    refute result
  end
end
```

## 🔧 Rake Tasks

Captain Hook provides several rake tasks:

```bash
# Setup wizard (installation)
rails captain_hook:setup

# Discover and register providers and actions
rails captain_hook:discover

# Validate configuration
rails captain_hook:doctor

# Archive old webhooks
rails captain_hook:archive[90]  # Archive events older than 90 days

# Clean up old events
rails captain_hook:cleanup[30]  # Delete archived events older than 30 days

# Retry failed actions
rails captain_hook:retry_failed[24]  # Retry actions that failed in last 24 hours
```

## 📊 Monitoring & Instrumentation

Captain Hook emits ActiveSupport notifications for monitoring:

```ruby
# Subscribe to all webhook events
ActiveSupport::Notifications.subscribe(/captain_hook/) do |name, start, finish, id, payload|
  duration = finish - start
  Rails.logger.info "#{name}: #{duration}ms - #{payload.inspect}"
end

# Available events:
# captain_hook.webhook_received
# captain_hook.signature_verified
# captain_hook.signature_failed
# captain_hook.action_started
# captain_hook.action_completed
# captain_hook.action_failed
# captain_hook.rate_limit_exceeded
```

### Metrics Integration

```ruby
# config/initializers/captain_hook_metrics.rb
ActiveSupport::Notifications.subscribe("captain_hook.action_completed") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  
  # Send to your metrics service
  StatsD.histogram("webhook.action.duration", event.duration)
  StatsD.increment("webhook.action.success", 
    tags: ["provider:#{event.payload[:provider]}"])
end
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/bowerbird-app/captain-hook.git
cd captain-hook

# Install dependencies
bundle install

# Set up test database
cd test/dummy
bin/rails db:create db:migrate
cd ../..

# Run tests
bundle exec rake test

# Run RSpec tests
bundle exec rspec
```

### Adding a New Built-in Verifier

If you're adding support for a common provider:

1. Create verifier in `lib/captain_hook/verifiers/provider_name.rb`
2. Inherit from `CaptainHook::Verifiers::Base`
3. Implement `verify_signature` method
4. Add example config in `captain_hook/provider_name/`
5. Write comprehensive tests
6. Submit PR with documentation

## 📝 License

This project is licensed under the MIT License - see the [MIT-LICENSE](MIT-LICENSE) file for details.

## 🆘 Support

- **Documentation:** [GitHub Wiki](https://github.com/bowerbird-app/captain-hook/wiki)
- **Issues:** [GitHub Issues](https://github.com/bowerbird-app/captain-hook/issues)
- **Discussions:** [GitHub Discussions](https://github.com/bowerbird-app/captain-hook/discussions)

## 🙏 Acknowledgments

Captain Hook is inspired by and builds upon patterns from:
- [Stripe's webhook handling best practices](https://stripe.com/docs/webhooks/best-practices)
- [Rails Event Store](https://railseventstore.org/)
- [Sidekiq's retry mechanism](https://github.com/mperham/sidekiq)

---

Made with ⚓ by the Bowerbird team
