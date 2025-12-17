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

### 1. Encryption Setup (Automatic!)

CaptainHook encrypts webhook signing secrets in the database using AES-256-GCM encryption.

**For Development**: Encryption keys are automatically generated on first server start and saved to `config/local_encryption_keys.yml` (gitignored). No setup required!

**For Production**: Set environment variables:

```bash
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=your_32_char_key
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=your_32_char_key
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=your_32_char_salt
SECRET_KEY_BASE=your_128_char_secret
```

Generate production keys with:
```bash
$ ruby generate_keys.rb
```

**Important**: Environment variables take precedence over the local file. Never commit `local_encryption_keys.yml` to version control.

### 2. Configure Providers

CaptainHook uses a file-based provider discovery system. Create provider configuration files in `captain_hook/providers/` directory.

**Create the directory structure:**

```bash
mkdir -p captain_hook/providers
mkdir -p captain_hook/handlers
mkdir -p captain_hook/adapters  # Optional, for custom adapters
```

**Create a provider YAML file** (e.g., `captain_hook/providers/stripe.yml`):

```yaml
# captain_hook/providers/stripe.yml
name: stripe
display_name: Stripe
description: Stripe payment and subscription webhooks
adapter_class: CaptainHook::Adapters::Stripe
active: true

# Security settings
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300

# Rate limiting (optional)
rate_limit_requests: 100
rate_limit_period: 60

# Payload size limit (optional, in bytes)
max_payload_size_bytes: 1048576
```

**Set environment variables:**

```bash
# .env or your environment
STRIPE_WEBHOOK_SECRET=whsec_your_secret_here
```

**Discover providers:**

1. Navigate to `/captain_hook/admin/providers`
2. Click "Scan for Providers"
3. CaptainHook will automatically create provider records from your YAML files

Providers are automatically discovered from:
- Your Rails app: `Rails.root/captain_hook/providers/*.yml`
- Loaded gems: `<gem_root>/captain_hook/providers/*.yml`

The `signing_secret` will be automatically encrypted in the database using AES-256-GCM encryption. Using `ENV[VARIABLE_NAME]` format ensures secrets are read from environment variables and never committed to version control.

### 3. Get Your Webhook URL

Each provider gets a unique webhook URL with a secure token. The URL is automatically generated and displayed in the admin UI:

```ruby
provider.webhook_url
# => "https://your-app.com/captain_hook/incoming/stripe/abc123token..."
```

**The URL format**: `/captain_hook/incoming/:provider_name/:token`

Share this URL with your provider (e.g., in Stripe's webhook settings). The token ensures that only requests to the correct URL are processed.

**Codespaces/Forwarding**: CaptainHook automatically detects GitHub Codespaces URLs or you can set `APP_URL` environment variable to override the base URL.

### 4. Create a Handler

Create a handler class in `captain_hook/handlers/`:

```ruby
# captain_hook/handlers/stripe_payment_succeeded_handler.rb
class StripePaymentSucceededHandler
  def handle(event:, payload:, metadata:)
    payment_intent_id = payload.dig("data", "object", "id")
    Payment.find_by(stripe_id: payment_intent_id)&.mark_succeeded!
  end
end
```

Handler method signature:
- `event`: The `CaptainHook::IncomingEvent` record
- `payload`: The parsed JSON payload (Hash)
- `metadata`: Additional metadata (Hash with `:timestamp`, `:headers`, etc.)

**Note**: While handlers can also be placed in `app/handlers/`, the recommended location is `captain_hook/handlers/` to keep all webhook-related code organized together.

### 5. Register the Handler

In `config/initializers/captain_hook.rb`:

```ruby
CaptainHook.configure do |config|
  # Admin interface settings
  config.admin_parent_controller = "ApplicationController"
  config.admin_layout = "application"
  
  # Data retention (days)
  config.retention_days = 90
end

# Register handler for specific event type
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "StripePaymentSucceededHandler",
  priority: 100,
  async: true
)

# Register handler for multiple event types with wildcard
CaptainHook.register_handler(
  provider: "square",
  event_type: "bank_account.*",  # Matches bank_account.created, bank_account.verified, etc.
  handler_class: "SquareBankAccountHandler",
  priority: 100,
  async: true
)
```

### 6. Test with Sandbox

CaptainHook includes a webhook sandbox at `/captain_hook/admin/sandbox`:

1. Select a provider
2. Enter a sample payload (JSON)
3. Click "Send Test Webhook"
4. View the results and handler execution logs

This lets you test your handlers without needing to trigger real events from the provider.

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

### Built-in Adapters

- **Stripe**: HMAC-SHA256 signature verification with hex encoding
- **Square**: HMAC-SHA256 signature verification with Base64 encoding
- **PayPal**: Certificate-based verification (simplified for testing)
- **WebhookSite**: Simple testing adapter (no signature verification)

### Using an Adapter

```ruby
CaptainHook::Provider.create!(
  name: "stripe",
  adapter_class: "CaptainHook::Adapters::Stripe",
  signing_secret: ENV["STRIPE_WEBHOOK_SECRET"]
)
```

The adapter dropdown in the admin UI automatically detects all available adapters.

### Creating a Custom Adapter

Need to integrate a provider not listed above? Create a custom adapter:

```ruby
# lib/captain_hook/adapters/my_provider.rb
module CaptainHook
  module Adapters
    class MyProvider < Base
      def verify_signature(payload:, headers:)
        # Implement provider-specific signature verification
        expected_sig = generate_hmac(payload, signing_secret)
        actual_sig = extract_header(headers, "X-My-Provider-Signature")
        
        Rack::Utils.secure_compare(expected_sig, actual_sig)
      end

      def extract_event_id(payload)
        payload["id"]
      end

      def extract_event_type(payload)
        payload["type"]
      end

      def extract_timestamp(headers)
        time_str = extract_header(headers, "X-My-Provider-Timestamp")
        Time.parse(time_str).to_i rescue nil
      end

      private

      def generate_hmac(payload, secret)
        OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      end
    end
  end
end
```

Then require it in `lib/captain_hook.rb`:

```ruby
require "captain_hook/adapters/my_provider"
```

**Full documentation**: See [docs/gem_template/ADAPTERS.md](docs/gem_template/ADAPTERS.md) for detailed adapter creation guide with examples for Stripe, Square, PayPal, and more.

## Security & Encryption

### Signing Secret Encryption

All webhook signing secrets are encrypted in the database using ActiveRecord Encryption (AES-256-GCM):

```ruby
# Automatically encrypted when saved
provider.signing_secret = "whsec_..."
provider.save!

# Automatically decrypted when read
provider.signing_secret # => "whsec_..." (decrypted)
```

**Hybrid ENV Override**: You can also store secrets in environment variables:

```bash
# .env
STRIPE_WEBHOOK_SECRET=whsec_abc123
```

The system checks `ENV["#{PROVIDER_NAME}_WEBHOOK_SECRET"]` first, then falls back to the encrypted database value.

### Security Checklist

All incoming webhooks are verified:
### Security Checklist

All incoming webhooks are verified:

1. Provider must be active
2. Token authentication (unique URL per provider)
3. Provider-specific signature verification (via adapter)
4. Timestamp validation (optional, but recommended)
5. Rate limiting (optional, but recommended)
6. Payload size limits (optional, but recommended)

**Environment Variables**: Never commit secrets to version control. Always use `.env` files (gitignored) or your hosting platform's environment variables.

## Admin Interface

Access the admin interface at `/captain_hook/admin`:

- **Providers**: Manage webhook providers, view webhook URLs, configure settings
- **Incoming Events**: View all received webhooks with filtering and search
- **Handlers**: View registered handlers per provider and their execution status
- **Sandbox**: Test webhooks without triggering real events from providers

## Testing Webhooks

### Using the Sandbox

1. Navigate to `/captain_hook/admin/sandbox`
2. Select your provider from the dropdown
3. Enter a test payload (JSON format)
4. Click "Send Test Webhook"
5. View handler execution results and logs

The sandbox bypasses signature verification for easy testing.

### Testing from External Provider

Most providers offer webhook testing tools:

- **Stripe**: Use the Stripe CLI `stripe trigger payment_intent.succeeded`
- **Square**: Use the Square Sandbox webhook simulator
- **PayPal**: Use the PayPal webhook simulator in the developer dashboard

### Using webhook.site or similar

Create a provider with the `CaptainHook::Adapters::WebhookSite` adapter for simple testing without signature verification.

## Handler Examples

### Basic Handler

```ruby
# app/handlers/stripe_payment_succeeded_handler.rb
class StripePaymentSucceededHandler
  def handle(event:, payload:, metadata:)
    Rails.logger.info "Payment succeeded: #{payload['id']}"
  end
end
```

### Handler with Error Handling

```ruby
class StripePaymentSucceededHandler
  def handle(event:, payload:, metadata:)
    payment_intent_id = payload.dig("data", "object", "id")
    
    payment = Payment.find_by!(stripe_id: payment_intent_id)
    payment.mark_succeeded!
    
    # Send confirmation email
    PaymentMailer.success(payment).deliver_later
    
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Payment not found: #{payment_intent_id}"
    raise # Re-raise to trigger retry
  end
end
```

### Handler with Wildcard Event Types

```ruby
# Handles multiple related events
class SquareBankAccountHandler
  def handle(event:, payload:, metadata:)
    event_type = payload["type"]
    bank_account = payload.dig("data", "object")
    
    case event_type
    when "bank_account.verified"
      BankAccount.find_by(square_id: bank_account["id"])&.mark_verified!
    when "bank_account.disabled"
      BankAccount.find_by(square_id: bank_account["id"])&.mark_disabled!
    end
  end
end

# Register with wildcard
CaptainHook.register_handler(
  provider: "square",
  event_type: "bank_account.*",
  handler_class: "SquareBankAccountHandler",
  async: true
)
```

## Documentation

- **Implementation Summary**: [docs/IMPLEMENTATION_SUMMARY.md](docs/IMPLEMENTATION_SUMMARY.md)
- **Architecture**: [docs/gem_template/](docs/gem_template/) (template reference)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
