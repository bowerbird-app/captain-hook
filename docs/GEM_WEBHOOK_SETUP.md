# Setting Up Webhooks in Your Gem with CaptainHook

This guide shows you how to set up webhook handling for any third-party provider (Stripe, PayPal, Square, etc.) in your gem using CaptainHook.

## Overview

When building a Rails gem that integrates with third-party services, you often need to receive and process webhooks from these services. CaptainHook is a Rails engine that handles the heavy lifting of webhook management, allowing your gem to focus on business logic.

While this guide uses **Stripe as the example provider**, the same pattern applies to any webhook provider (PayPal, Square, Shopify, GitHub, etc.).

### Why This Setup?

Instead of implementing webhook handling from scratch in every gem, CaptainHook provides:

- **Signature Verification**: Ensures webhooks are authentic and from the claimed provider
- **Event Storage**: Persists all incoming webhooks for audit trails and debugging
- **Handler Registration**: Routes events to your business logic automatically
- **Admin UI**: Provides visibility into webhook traffic and processing status
- **Reliability**: Built-in retry logic, background job processing, and error tracking

### How It Works

Your gem provides three key components:

1. **Provider Config** - YAML file with webhook endpoint settings (configuration)
2. **Adapter** - Ruby class that verifies webhook signatures (security)
3. **Handlers** - Job classes that process specific event types (business logic)

When installed in a Rails app, CaptainHook:
- Discovers your provider configuration and adapter
- Registers your handlers
- Routes incoming webhooks to your code
- Manages the entire webhook lifecycle

This keeps your gem focused on **what to do** with webhook data, while CaptainHook handles **how to receive it safely**.

## Example Provider Adapters

**CaptainHook includes example adapters you can reference or copy:**
- Stripe - See test/dummy examples
- Square - See test/dummy examples
- PayPal - See test/dummy examples
- WebhookSite - See test/dummy examples (testing only)

**You can create custom adapters for any provider!** Adapters are now provider-specific and ship with your gem.

## Important: One Provider, Many Handlers

**Before creating a new provider, check if one already exists!**

If your Rails app or another gem already has a provider for your service (e.g., `stripe`), you typically **don't need to create a new one**. Instead, just register your handlers for the existing provider.

### When to Share a Provider

**Share the same provider when:**
- You're using the same webhook URL and signing secret
- Multiple gems/parts of your app need to process different event types from the same account
- Example: One gem handles `invoice.paid`, another handles `subscription.updated`

**Your app:**
```ruby
# captain_hook/providers/stripe/stripe.yml already exists
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.created",
  handler_class: "MyApp::PaymentHandler"
)
```

**Your gem:**
```ruby
# DON'T create a new stripe provider - use the existing one!
CaptainHook.register_handler(
  provider: "stripe",  # Same provider name
  event_type: "invoice.paid",
  handler_class: "MyGem::InvoiceHandler"
)
```

Both handlers use the **same webhook endpoint** and **same signature verification**.

### When to Create a New Provider

**Create a separate provider only when:**
- You need different webhook URLs (multi-tenant: different Stripe accounts)
- You need different signing secrets
- You're using different API credentials

**Multi-tenant example:**
```ruby
# Provider for Account A
# captain_hook/providers/stripe_primary/stripe_primary.yml
name: stripe_primary
signing_secret: ENV[STRIPE_PRIMARY_SECRET]

# Provider for Account B
# captain_hook/providers/stripe_secondary/stripe_secondary.yml
name: stripe_secondary
signing_secret: ENV[STRIPE_SECONDARY_SECRET]
```

**CaptainHook will warn you** if it detects duplicate provider names during scanning and provide guidance on whether to merge or rename.

## Directory Structure

Create this structure in your gem:

```
your_gem/
├── app/
│   └── jobs/                          # Event processing handlers (REQUIRED)
│       └── your_gem/
│           └── webhooks/
│               ├── event_one_handler.rb        # e.g., payment_succeeded_handler.rb
│               ├── event_two_handler.rb        # e.g., refund_processed_handler.rb
│               └── event_three_handler.rb      # e.g., subscription_updated_handler.rb
├── captain_hook/                      # Provider configuration (REQUIRED)
│   └── providers/
│       └── your_provider/             # Provider-specific directory
│           ├── your_provider.yml      # Configuration (e.g., stripe.yml)
│           └── your_provider.rb       # Adapter implementation (e.g., stripe.rb)
├── lib/
│   └── your_gem/
│       └── engine.rb                  # Handler registration (REQUIRED)
└── your_gem.gemspec                   # Gem dependencies (REQUIRED)
```

### Why Each File?

- **Provider Config (`stripe.yml`)**: Declarative configuration that tells CaptainHook about your provider - what it's called, which adapter to use, where to get secrets from environment variables, and security settings.

- **Adapter (`stripe.rb`)**: Ruby class that verifies webhook signatures specific to your provider. Uses `CaptainHook::AdapterHelpers` for security methods like HMAC generation and constant-time comparison.

- **Handlers (`*_handler.rb`)**: Your business logic. Each handler processes a specific event type (e.g., "payment succeeded"). They run as background jobs, so heavy processing won't block the webhook response.

- **Engine (`engine.rb`)**: Registers your handlers with CaptainHook when your gem loads. This tells CaptainHook which Ruby classes should process which event types.

- **Gemspec**: Ensures all webhook-related files are included when your gem is packaged and distributed.

## Step 1: Create Your Provider Adapter

Create an adapter class that handles webhook signature verification for your provider. CaptainHook provides the `AdapterHelpers` module with all the security utilities you need.

**Example: Stripe Adapter**

Create `captain_hook/providers/stripe/stripe.rb` in your gem:

```ruby
# frozen_string_literal: true

# Stripe webhook adapter
# Implements Stripe's webhook signature verification scheme
# https://stripe.com/docs/webhooks/signatures
class StripeAdapter
  include CaptainHook::AdapterHelpers

  SIGNATURE_HEADER = "Stripe-Signature"
  TIMESTAMP_TOLERANCE = 300 # 5 minutes

  # Verify Stripe webhook signature
  # Stripe sends signature as: t=timestamp,v1=signature
  def verify_signature(payload:, headers:, provider_config:)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return false if signature_header.blank?

    # Parse signature header: t=timestamp,v1=signature,v0=old_signature
    parsed = parse_kv_header(signature_header)
    timestamp = parsed["t"]
    signatures = [parsed["v1"], parsed["v0"]].flatten.compact
    
    return false if timestamp.blank? || signatures.empty?

    # Check timestamp tolerance
    if provider_config.timestamp_validation_enabled?
      tolerance = provider_config.timestamp_tolerance_seconds || TIMESTAMP_TOLERANCE
      return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
    end

    # Generate expected signature
    signed_payload = "#{timestamp}.#{payload}"
    expected_signature = generate_hmac(provider_config.signing_secret, signed_payload)

    # Check if any of the signatures match
    signatures.any? { |sig| secure_compare(sig, expected_signature) }
  end

  # Extract timestamp from Stripe signature header
  def extract_timestamp(headers)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return nil if signature_header.blank?

    parsed = parse_kv_header(signature_header)
    parsed["t"]&.to_i
  end

  # Extract event ID from Stripe payload
  def extract_event_id(payload)
    payload["id"]
  end

  # Extract event type from Stripe payload
  def extract_event_type(payload)
    payload["type"]
  end
end
```

**Available Helper Methods from `CaptainHook::AdapterHelpers`:**
- `secure_compare(a, b)` - Constant-time string comparison
- `generate_hmac(secret, data)` - Hex-encoded HMAC-SHA256
- `generate_hmac_base64(secret, data)` - Base64-encoded HMAC-SHA256
- `extract_header(headers, *keys)` - Case-insensitive header extraction
- `parse_kv_header(value)` - Parse "k1=v1,k2=v2" format
- `timestamp_within_tolerance?(timestamp, tolerance)` - Timestamp validation
- `skip_verification?(secret)` - Check if verification should be skipped
- `log_verification(provider, details)` - Debug logging

See [docs/ADAPTER_HELPERS.md](ADAPTER_HELPERS.md) for complete helper documentation.

## Step 2: Create Provider Configuration

Create a YAML file that defines your provider's webhook settings. The `name` field should be lowercase and URL-friendly (it becomes part of the webhook endpoint).

### Example: Stripe Configuration

Create `captain_hook/providers/stripe/stripe.yml` in your gem:

```yaml
# Provider configuration for Stripe
# Place this file in: captain_hook/providers/stripe/stripe.yml
name: stripe                                    # URL-friendly identifier (lowercase, no spaces)
display_name: Stripe                            # Human-readable name
description: Stripe payment processing webhooks # Brief description

# Reference your adapter file (in same directory)
adapter_file: stripe.rb                         # Your adapter file (class will be auto-detected)

# Signing secret from environment variable
# Set this in your .env file or environment:
# STRIPE_WEBHOOK_SECRET=whsec_...
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]      # Environment variable reference

# Security settings
timestamp_tolerance_seconds: 300  # 5 minutes
max_payload_size_bytes: 1048576   # 1 MB

# Rate limiting
rate_limit_requests: 100
rate_limit_period: 60  # 60 seconds

# Active by default
active: true
```

### Multi-Tenant Support

If you need multiple instances of the same provider (e.g., supporting multiple Stripe accounts), create separate provider directories:

```yaml
# captain_hook/providers/stripe_primary/stripe_primary.yml
name: stripe_primary
display_name: Stripe (Primary Account)
adapter_file: stripe_primary.rb
signing_secret: ENV[STRIPE_PRIMARY_SECRET]

# captain_hook/providers/stripe_secondary/stripe_secondary.yml
name: stripe_secondary
display_name: Stripe (Secondary Account)
adapter_file: stripe_secondary.rb
signing_secret: ENV[STRIPE_SECONDARY_SECRET]
```

Each instance gets its own webhook URL and handlers.

## Step 3: Create Handler Classes

Create handler classes for each event type you want to process. Handlers are plain Ruby classes with a `handle` method that receives the webhook data.

### Example Handler Structure

Create `app/jobs/your_gem/webhooks/[event_name]_handler.rb`:

**Example: Stripe Payment Intent Succeeded**

Create `app/jobs/your_gem/webhooks/payment_intent_succeeded_handler.rb`:

```ruby
# frozen_string_literal: true

module YourGem
  module Webhooks
    # Handler for Stripe payment_intent.succeeded events
    # Handlers are plain Ruby classes with a `handle` method
    # CaptainHook manages job queuing, retries, and execution
    class PaymentIntentSucceededHandler
      # Required method signature: handle(event:, payload:, metadata:)
      # @param event [CaptainHook::IncomingEvent] The stored webhook event
      # @param payload [Hash] The parsed webhook payload
      # @param metadata [Hash] Additional metadata about the webhook
      def handle(event:, payload:, metadata:)
        payment_intent_id = payload.dig("data", "object", "id")
        amount = payload.dig("data", "object", "amount")
        currency = payload.dig("data", "object", "currency")
        customer_id = payload.dig("data", "object", "customer")

        # Your business logic here
        Rails.logger.info "Payment succeeded: #{payment_intent_id} for #{amount} #{currency}"

        # Example: Update your database
        # Payment.find_by(stripe_payment_intent_id: payment_intent_id)&.mark_as_paid!

        # Example: Send confirmation email
        # PaymentMailer.payment_confirmation(payment_intent_id).deliver_later
        
        # Example: Create a record
        # YourGem::Payment.create!(
        #   stripe_payment_intent_id: payment_intent_id,
        #   amount: amount,
        #   currency: currency
        # )
      end
    end
  end
end
```

**Example: Stripe Charge Succeeded**

Create `app/jobs/your_gem/webhooks/charge_succeeded_handler.rb`:

```ruby
# frozen_string_literal: true

module YourGem
  module Webhooks
    # Handler for Stripe charge.succeeded events
    class ChargeSucceededHandler
      def handle(event:, payload:, metadata:)
        charge_id = payload.dig("data", "object", "id")
        amount = payload.dig("data", "object", "amount")
        receipt_url = payload.dig("data", "object", "receipt_url")

        Rails.logger.info "Charge succeeded: #{charge_id} for #{amount}"

        # Your business logic here
      end
    end
  end
end
```

**Example: Stripe Customer Created**

Create `app/jobs/your_gem/webhooks/customer_created_handler.rb`:

```ruby
# frozen_string_literal: true

module YourGem
  module Webhooks
    # Handler for Stripe customer.created events
    class CustomerCreatedHandler
      def handle(event:, payload:, metadata:)
        customer_id = payload.dig("data", "object", "id")
        email = payload.dig("data", "object", "email")
        name = payload.dig("data", "object", "name")

        Rails.logger.info "Customer created: #{customer_id} - #{email}"

        # Your business logic here
        # User.find_by(email: email)&.update(stripe_customer_id: customer_id)
      end
    end
  end
end
```

### Important Notes About Handlers

**Handlers are NOT ActiveJob classes!** They are plain Ruby classes with a `handle` method. CaptainHook wraps them in its own job system (`IncomingHandlerJob`) which provides:
- Automatic retry logic with exponential backoff
- Priority-based execution
- Status tracking and logging
- Optimistic locking to prevent duplicate processing

If you need to enqueue additional background jobs from within a handler, you can do so:

```ruby
def handle(event:, payload:, metadata:)
  # Process some data immediately
  payment_id = payload.dig("data", "object", "id")
  
  # Enqueue additional background work
  SendReceiptEmailJob.perform_later(payment_id)
  UpdateAnalyticsJob.perform_later(payment_id)
end
```

## Step 4: Register Handlers in Your Engine

⚠️ **CRITICAL STEP**: Without this step, your handlers won't be called!

Handler registration tells CaptainHook which Ruby classes should process which webhook events. When a webhook arrives:
1. CaptainHook verifies the signature and stores the event
2. It looks up registered handlers for that provider + event type
3. It enqueues background jobs for each registered handler
4. Your handlers execute and process the business logic

**Without registration, CaptainHook won't know about your handlers and they'll never run.**

### Registration Pattern

Update your `lib/your_gem/engine.rb` to register handlers for each event type you want to handle:

```ruby
# frozen_string_literal: true

module YourGem
  class Engine < ::Rails::Engine
    isolate_namespace YourGem

    # IMPORTANT: Register webhook handlers after Rails initializes
    # This tells CaptainHook which handler classes process which events
    config.after_initialize do
      # Only register if CaptainHook is available
      if defined?(CaptainHook)
        # Registration format:
        # CaptainHook.register_handler(
        #   provider: "provider_name",      # Must match provider YAML name (e.g., "stripe", "paypal")
        #   event_type: "event.type",       # Exact event type string from webhook payload
        #   handler_class: "Full::ClassName" # Full class name as string
        # )

        # Example: Stripe handlers
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment_intent.succeeded",
          handler_class: "YourGem::Webhooks::PaymentIntentSucceededHandler"
        )

        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "charge.succeeded",
          handler_class: "YourGem::Webhooks::ChargeSucceededHandler"
        )

        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "customer.created",
          handler_class: "YourGem::Webhooks::CustomerCreatedHandler"
        )

        # Example: PayPal handlers (if you're also integrating PayPal)
        # CaptainHook.register_handler(
        #   provider: "paypal",
        #   event_type: "PAYMENT.SALE.COMPLETED",
        #   handler_class: "YourGem::Webhooks::PaypalPaymentCompletedHandler"
        # )

        # Example: Square handlers (if you're also integrating Square)
        # CaptainHook.register_handler(
        #   provider: "square",
        #   event_type: "payment.created",
        #   handler_class: "YourGem::Webhooks::SquarePaymentCreatedHandler"
        # )

        Rails.logger.info "YourGem: Registered webhook handlers"
      else
        Rails.logger.warn "YourGem: CaptainHook not available, webhook handlers not registered"
      end
    end
  end
end
```

### Why `after_initialize`?

Using `config.after_initialize` ensures:
- CaptainHook is fully loaded before we try to register handlers
- All your handler classes are loaded and available
- The handler registry is ready to accept registrations

### Verifying Registration Works

After adding this code and restarting your server, verify handlers are registered:

```ruby
# Rails console - Check specific handler
CaptainHook.handler_registry.handlers_for(provider: "your_provider", event_type: "your.event.type")
# Should return: ["YourGem::Webhooks::YourHandlerClass"]

# Example for Stripe:
CaptainHook.handler_registry.handlers_for(provider: "stripe", event_type: "payment_intent.succeeded")
# Should return: ["YourGem::Webhooks::PaymentIntentSucceededHandler"]

# Check all registered handlers across all providers
CaptainHook.handler_registry.all_handlers
# Should show all your registered handlers
```

If handlers aren't showing up:
1. Make sure you restarted the Rails server after adding registration code
2. Check the Rails logs for "Registered webhook handlers" message
3. Verify the handler class names are correct (full namespace)
4. Ensure CaptainHook is loaded before your gem (it usually is)

## Step 5: Update Your Gemspec

Make sure your gemspec includes the necessary files:

```ruby
# your_gem.gemspec
Gem::Specification.new do |spec|
  spec.name        = "your_gem"
  spec.version     = YourGem::VERSION
  spec.authors     = ["Your Name"]
  spec.email       = ["your.email@example.com"]
  spec.summary     = "Your gem description"
  spec.description = "Your gem description"
  spec.license     = "MIT"

  # Include all necessary files
  spec.files = Dir[
    "{app,captain_hook,config,db,lib}/**/*",
    "MIT-LICENSE",
    "Rakefile",
    "README.md"
  ]

  # Add CaptainHook as a dependency
  spec.add_dependency "rails", ">= 7.0"
  # spec.add_dependency "captain_hook" # Optional: only if you want to require it
end
```

## Step 6: Install in Your Rails App

In your Rails application:

### 1. Add to Gemfile:

```ruby
# Gemfile
gem "your_gem", path: "../your_gem"
# or from rubygems:
# gem "your_gem"

# Make sure captain_hook is also installed
gem "captain_hook", path: "../captain-hook"
```

### 2. Bundle install:

```bash
bundle install
```

### 3. Set environment variables:

```bash
# .env or environment
# The variable name must match what you specified in your provider YAML file
YOUR_PROVIDER_WEBHOOK_SECRET=your_secret_value

# Examples:
# STRIPE_WEBHOOK_SECRET=whsec_your_stripe_webhook_signing_secret
# PAYPAL_WEBHOOK_ID=your_paypal_webhook_id
# SQUARE_SIGNATURE_KEY=your_square_signature_key
```

### 4. Restart server:

```bash
touch tmp/restart.txt
# or restart your development server
```

### 5. Scan for providers:

Go to `/captain_hook/admin/providers` and click "Discover New" (for first-time setup) or "Full Sync" (to update existing)

Or in console:

```ruby
discovery = CaptainHook::Services::ProviderDiscovery.new
definitions = discovery.call

sync = CaptainHook::Services::ProviderSync.new(definitions, update_existing: true)
sync.call
```

## Step 7: Configure Your Provider's Webhook Settings

### Generic Steps

1. Log into your provider's dashboard (Stripe, PayPal, Square, etc.)
2. Navigate to the webhooks/notifications section
3. Create a new webhook endpoint
4. Enter your webhook URL: `https://your-app.com/captain_hook/[provider_name]/[TOKEN]`
   - Get the token from CaptainHook admin UI after scanning providers
   - Example: `https://your-app.com/captain_hook/stripe/abc123xyz`
5. Select which events to receive (or select all)
6. Copy the signing secret/webhook ID provided by your provider
7. Set it in your environment using the variable name from your YAML config

### Example: Stripe

1. Go to Stripe Dashboard → Developers → Webhooks
2. Click "Add endpoint"
3. Enter URL: `https://your-app.com/captain_hook/stripe/[TOKEN]`
4. Select events: `payment_intent.succeeded`, `charge.succeeded`, `customer.created`
5. Copy the webhook signing secret (starts with `whsec_`)
6. Set: `STRIPE_WEBHOOK_SECRET=whsec_...`

### Example: PayPal

1. Go to PayPal Developer Dashboard → Webhooks
2. Create webhook
3. Enter URL: `https://your-app.com/captain_hook/paypal/[TOKEN]`
4. Select event types
5. Copy the Webhook ID
6. Set: `PAYPAL_WEBHOOK_ID=...`

## Step 8: Testing Locally

### Option A: Using Provider CLI Tools (e.g., Stripe CLI)

### 1. Install Stripe CLI:

```bash
# macOS
brew install stripe/stripe-cli/stripe

# Or download from https://stripe.com/docs/stripe-cli
```

### 2. Login:

```bash
stripe login
```

### 3. Get webhook URL from admin:

Go to `/captain_hook/admin/providers`, view the Stripe provider, copy the webhook URL.

### 4. Start listening:

```bash
stripe listen --forward-to https://your-codespace-url.app.github.dev/captain_hook/stripe/[TOKEN]
```

Copy the webhook signing secret shown and update your environment.

### 5. Trigger test events:

```bash
stripe trigger payment_intent.succeeded
stripe trigger charge.succeeded
stripe trigger customer.created
```

### 6. Check logs:

Watch your Rails logs to see events being processed:

```bash
tail -f log/development.log
```

### Option B: Manual Testing with curl

For providers without CLI tools, you can manually send test webhooks:

```bash
# Get your webhook URL from CaptainHook admin
# Create a test payload matching your provider's format
curl -X POST https://your-app.com/captain_hook/your_provider/[TOKEN] \
  -H "Content-Type: application/json" \
  -H "Your-Signature-Header: signature_value" \
  -d '{"event_type": "test.event", "data": {}}'
```

### Option C: Use Provider's Test Mode

Most providers offer a test/sandbox mode where you can trigger real events:
- Stripe: Use test API keys and trigger events via dashboard or CLI
- PayPal: Use PayPal Sandbox environment
- Square: Use Square Sandbox with test transactions

## Verification

### Check handlers are registered:

```ruby
# Rails console
CaptainHook.handler_registry.handlers_for(provider: "your_provider", event_type: "your.event")
# => ["YourGem::Webhooks::YourHandler"]

# Example for Stripe:
CaptainHook.handler_registry.handlers_for(provider: "stripe", event_type: "payment_intent.succeeded")
# => ["YourGem::Webhooks::PaymentIntentSucceededHandler"]
```

### Check provider is created:

```ruby
# Rails console
CaptainHook::Provider.find_by(name: "your_provider_name")

# Example:
CaptainHook::Provider.find_by(name: "stripe")
```

### Check events are being received:

```ruby
# Rails console
CaptainHook::IncomingEvent.where(provider: "your_provider_name").order(created_at: :desc).first

# Example:
CaptainHook::IncomingEvent.where(provider: "stripe").order(created_at: :desc).first
```

## Adding More Event Handlers

To handle additional events from your provider:

1. **Create a new handler class** in `app/jobs/your_gem/webhooks/`
2. **Register it in your engine** in `config.after_initialize` block
3. **Restart your Rails server**

### Example: Adding a New Stripe Event

For handling `invoice.payment_succeeded`:

```ruby
# app/jobs/your_gem/webhooks/invoice_payment_succeeded_handler.rb
module YourGem
  module Webhooks
    class InvoicePaymentSucceededHandler
      def handle(event:, payload:, metadata:)
        invoice_id = payload.dig("data", "object", "id")
        # Your logic here
      end
    end
  end
end
```

Register in engine.rb:

```ruby
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "invoice.payment_succeeded",
  handler_class: "YourGem::Webhooks::InvoicePaymentSucceededHandler"
)
```

## Troubleshooting

### Handlers not being called?

**Most common issue**: Handlers not registered properly

1. **Verify handlers are registered**:
   ```ruby
   # Rails console
   CaptainHook.handler_registry.handlers_for(provider: "stripe", event_type: "payment_intent.succeeded")
   # Should return: ["YourGem::Webhooks::PaymentIntentSucceededHandler"]
   ```
   
   If this returns an empty array, your handlers aren't registered! Check:
   - Did you add the registration code to `lib/your_gem/engine.rb`?
   - Did you restart the Rails server after adding the code?
   - Are the provider names matching exactly? (case-sensitive: "stripe" not "Stripe")
   - Are the event type strings exactly matching what Stripe sends?

2. **Check if provider exists**: 
   ```ruby
   CaptainHook::Provider.find_by(name: "stripe")
   ```
   If nil, use "Discover New" or "Full Sync" in the admin UI

3. **Check Sidekiq is running** (handlers are background jobs)
   ```bash
   bundle exec sidekiq
   ```

4. **Check Rails logs** for errors:
   ```bash
   tail -f log/development.log
   ```
   Look for handler execution errors or job failures

5. **Check the engine is loading**:
   ```ruby
   # Rails console
   defined?(YourGem::Engine)
   # Should return: "constant"
   ```

### Signature verification failing?

1. Make sure your signing secret environment variable is set correctly
2. Verify the environment variable name matches your YAML config
3. Use test/sandbox secrets when testing locally
4. Use production secrets for production environment
5. Check your adapter implementation matches the provider's documentation
6. Enable debug logging to see the signature verification process

### Provider not discovered?

1. Make sure YAML file is in `captain_hook/providers/stripe.yml`
2. Make sure gemspec includes `captain_hook/**/*` in files
3. Run bundle install and restart server
4. Try scanning again

## Complete Example Event Processing Flow

1. **Provider sends webhook** → Your Rails app at `/captain_hook/[provider]/[TOKEN]`
   - Example: `/captain_hook/stripe/abc123` or `/captain_hook/paypal/xyz789`
2. **CaptainHook receives** → Verifies signature using your custom adapter
3. **Creates IncomingEvent** → Stores event in database for audit trail
4. **Finds registered handlers** → Looks up handlers for `provider` + `event_type`
   - Example: `stripe` + `payment_intent.succeeded`
5. **Enqueues handler jobs** → Adds jobs to background queue (Sidekiq/Solid Queue)
6. **Handlers execute** → Your business logic runs in background jobs
7. **Updates handler status** → Marks as completed or failed, with retry logic
