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
  - **Edit and configure handlers** (async/sync, retries, priority)
  - **Scan and sync handlers** from application code
  - **Soft-delete handlers** to prevent re-addition
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

This will:
- Mount the engine at `/captain_hook` in your routes
- Create an initializer at `config/initializers/captain_hook.rb`
- Configure Tailwind CSS (if detected) to include engine views

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

**CaptainHook ships with built-in adapters for common providers:**
- **Stripe** - `CaptainHook::Adapters::Stripe`
- **Square** - `CaptainHook::Adapters::Square`  
- **PayPal** - `CaptainHook::Adapters::Paypal`
- **WebhookSite** - `CaptainHook::Adapters::WebhookSite` (testing)

**You don't need to create adapters for these providers** - just reference them in your provider YAML config.

**Create the directory structure:**

```bash
mkdir -p captain_hook/providers
mkdir -p captain_hook/handlers
```

**Create a provider YAML file** (e.g., `captain_hook/providers/stripe.yml`):

You can copy from the example templates shipped with CaptainHook:

```bash
# Example templates are in the gem at captain_hook/providers/*.yml.example
# Copy and customize for your needs
cp captain_hook/providers/stripe.yml.example captain_hook/providers/stripe.yml
```

Or create from scratch:

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

**Multiple Instances of Same Provider:**

You can have multiple instances of the same provider type (e.g., multiple Stripe accounts):

```yaml
# captain_hook/providers/stripe_account_a.yml
name: stripe_account_a
display_name: Stripe (Account A)
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[STRIPE_SECRET_ACCOUNT_A]

# captain_hook/providers/stripe_account_b.yml
name: stripe_account_b
display_name: Stripe (Account B)  
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[STRIPE_SECRET_ACCOUNT_B]
```

Each gets its own webhook URL and can have different handlers.

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
  # Optional: Configure admin settings
  # config.admin_parent_controller = "ApplicationController"
  # config.admin_layout = "application"
  # config.retention_days = 90
end

# Register handlers - must be inside after_initialize block
Rails.application.config.after_initialize do
  # Register handler for specific event type
  CaptainHook.register_handler(
    provider: "stripe",
    event_type: "payment_intent.succeeded",
    handler_class: "StripePaymentSucceededHandler",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  # Register handler for multiple event types with wildcard
  CaptainHook.register_handler(
    provider: "square",
    event_type: "bank_account.*",  # Matches bank_account.created, bank_account.verified, etc.
    handler_class: "SquareBankAccountHandler",
    priority: 100,
    async: true
  )
end
```

**Important**: Handler registration must be inside `Rails.application.config.after_initialize` to ensure CaptainHook is fully loaded.

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

CaptainHook ships with built-in adapters for popular webhook providers. Adapters handle provider-specific signature verification and event extraction.

### Built-in Adapters

CaptainHook includes these adapters out of the box:

- **Stripe** (`CaptainHook::Adapters::Stripe`)
  - HMAC-SHA256 signature verification with hex encoding
  - Timestamp validation for replay attack prevention
  - Supports Stripe's signature format: `t=timestamp,v1=signature`

- **Square** (`CaptainHook::Adapters::Square`)
  - HMAC-SHA256 signature verification with Base64 encoding
  - Notification URL validation
  - Supports X-Square-Hmacsha256-Signature header

- **PayPal** (`CaptainHook::Adapters::Paypal`)
  - Certificate-based verification (simplified)
  - Transmission ID and timestamp validation
  - Supports PayPal's transmission headers

- **WebhookSite** (`CaptainHook::Adapters::WebhookSite`)
  - No signature verification (testing only)
  - Use for local development and testing

### Using an Adapter

Adapters are specified in your provider YAML configuration:

```yaml
# captain_hook/providers/stripe.yml
name: stripe
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

The admin UI automatically detects all available adapters (both built-in and custom) in the adapter dropdown.

### Creating a Custom Adapter

Need to integrate a provider not listed above? Create a custom adapter in your Rails application:

```ruby
# app/adapters/captain_hook/adapters/my_provider.rb
module CaptainHook
  module Adapters
    class MyProvider < Base
      def verify_signature(payload:, headers:)
        # Implement provider-specific signature verification
        signature = headers["X-My-Provider-Signature"]
        return false if signature.blank?
        
        expected = generate_hmac(provider_config.signing_secret, payload)
        secure_compare(signature, expected)
      end

      def extract_event_id(payload)
        payload["id"]
      end

      def extract_event_type(payload)
        payload["type"] || "unknown"
      end

      def extract_timestamp(headers)
        time_str = headers["X-My-Provider-Timestamp"]
        Time.parse(time_str).to_i rescue nil
      end

      private

      def generate_hmac(secret, data)
        OpenSSL::HMAC.hexdigest("SHA256", secret, data)
      end
    end
  end
end
```

Place adapters in `app/adapters/captain_hook/adapters/` - they'll be automatically discovered by the admin UI dropdown.

**Full documentation**: See [docs/ADAPTERS.md](docs/ADAPTERS.md) for detailed adapter creation guide with examples for Stripe, Square, PayPal, and more.

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
  - **Scan for Providers**: Discover providers from YAML files and sync to database
  - **Scan Handlers**: Discover and sync handlers for each provider
- **Incoming Events**: View all received webhooks with filtering and search
- **Handlers**: View, edit, and manage registered handlers per provider
  - Configure async/sync execution mode
  - Set retry attempts and delays
  - Adjust handler priority
  - Soft-delete handlers to prevent re-addition
- **Sandbox**: Test webhooks without triggering real events from providers

See [Handler Management](docs/HANDLER_MANAGEMENT.md) for detailed documentation on managing handlers.

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

- **Stripe CLI**: 
  ```bash
  # Trigger test events
  stripe trigger payment_intent.succeeded
  
  # Or forward webhooks to your local server
  stripe listen --forward-to localhost:3000/captain_hook/incoming/stripe/YOUR_TOKEN
  ```
  Replace `YOUR_TOKEN` with your provider's token from the admin UI.

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

### For Gem Developers

**Building a gem that needs webhook support?** 

See our comprehensive guide: [**Setting Up Webhooks in Your Gem**](docs/GEM_WEBHOOK_SETUP.md)

This guide shows you how to create provider adapters, handler classes, and YAML configurations that integrate seamlessly with CaptainHook. Perfect for payment processing gems, notification services, or any gem that receives webhooks from external providers.

### General Documentation

- **Handler Management**: [docs/HANDLER_MANAGEMENT.md](docs/HANDLER_MANAGEMENT.md) - Managing handlers via admin UI
- **Provider Discovery**: [docs/PROVIDER_DISCOVERY.md](docs/PROVIDER_DISCOVERY.md) - File-based provider configuration
- **Custom Adapters**: [docs/CUSTOM_ADAPTERS.md](docs/CUSTOM_ADAPTERS.md) - Creating adapters for new providers
- **Adapters Reference**: [docs/ADAPTERS.md](docs/ADAPTERS.md) - Detailed adapter implementation guide
- **Signing Secret Storage**: [docs/SIGNING_SECRET_STORAGE.md](docs/SIGNING_SECRET_STORAGE.md) - Security and encryption details
- **Implementation Summary**: [docs/IMPLEMENTATION_SUMMARY.md](docs/IMPLEMENTATION_SUMMARY.md) - Technical overview
- **Visual Guide**: [docs/VISUAL_GUIDE.md](docs/VISUAL_GUIDE.md) - Screenshots and UI walkthrough

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
