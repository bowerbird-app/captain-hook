# Setting Up Webhooks in Your Gem with CaptainHook

This guide shows you how to set up webhook handling for any third-party provider (Stripe, PayPal, Square, etc.) in your gem using CaptainHook.

## Overview

When building a Rails gem that integrates with third-party services, you often need to receive and process webhooks from these services. CaptainHook is a Rails engine that handles the heavy lifting of webhook management, allowing your gem to focus on business logic.

While this guide uses **Stripe as the example provider**, the same pattern applies to any webhook provider (PayPal, Square, Shopify, GitHub, etc.).

### Why This Setup?

Instead of implementing webhook handling from scratch in every gem, CaptainHook provides:

- **Signature Verification**: Ensures webhooks are authentic and from the claimed provider
- **Event Storage**: Persists all incoming webhooks for audit trails and debugging
- **Action Registration**: Routes events to your business logic automatically
- **Admin UI**: Provides visibility into webhook traffic and processing status
- **Reliability**: Built-in retry logic, background job processing, and error tracking

### Built-in Verifiers

**CaptainHook ships with verifiers for common webhook providers:**
- **Stripe** - `CaptainHook::Verifiers::Stripe`
- **Square** - `CaptainHook::Verifiers::Square`
- **PayPal** - `CaptainHook::Verifiers::Paypal`
- **WebhookSite** - `CaptainHook::Verifiers::WebhookSite` (testing only)

These verifiers are maintained within the CaptainHook gem and provide secure, tested webhook signature verification. If you need a verifier for a provider not listed above, see the "Contributing New Verifiers" section at the end of this guide.

### How It Works

Your gem provides two key components:

1. **Provider Config** - YAML file specifying which built-in verifier to use
2. **Actions** - Job classes that process specific event types (your business logic)

When installed in a Rails app, CaptainHook:
- Discovers your provider configuration
- Uses the specified built-in verifier for signature verification
- Registers your actions
- Routes incoming webhooks to your code
- Manages the entire webhook lifecycle

This keeps your gem focused on **what to do** with webhook data, while CaptainHook handles **how to receive it safely**.

## Important: One Provider, Many Actions

**Before creating a new provider, check if one already exists!**

If your Rails app or another gem already has a provider for your service (e.g., `stripe`), you typically **don't need to create a new one**. Instead, just register your actions for the existing provider.

### When to Share a Provider

**Share the same provider when:**
- You're using the same webhook URL and signing secret
- Multiple gems/parts of your app need to process different event types from the same account
- Example: One gem handles `invoice.paid`, another handles `subscription.updated`

**Your app:**
```ruby
# captain_hook/providers/stripe/stripe.yml already exists
CaptainHook.register_action(
  provider: "stripe",
  event_type: "payment_intent.created",
  action_class: "MyApp::PaymentAction"
)
```

**Your gem:**
```ruby
# DON'T create a new stripe provider - use the existing one!
CaptainHook.register_action(
  provider: "stripe",  # Same provider name
  event_type: "invoice.paid",
  action_class: "MyGem::InvoiceAction"
)
```

Both actions use the **same webhook endpoint** and **same signature verification**.

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
├── captain_hook/                      # Action handlers and provider config (REQUIRED)
│   ├── providers/
│   │   └── your_provider/             # Provider-specific directory
│   │       └── your_provider.yml      # Configuration (e.g., stripe.yml)
│   └── your_provider/                 # Provider name (e.g., stripe, paypal)
│       └── actions/                   # Action classes directory
│           ├── event_one_action.rb    # e.g., payment_succeeded_action.rb
│           ├── event_two_action.rb    # e.g., refund_processed_action.rb
│           └── event_three_action.rb  # e.g., subscription_updated_action.rb
├── lib/
│   └── your_gem/
│       └── engine.rb                  # Rails engine (if applicable)
└── your_gem.gemspec                   # Gem dependencies (REQUIRED)
```

### Why Each Directory?

- **Provider Config (`captain_hook/providers/stripe/stripe.yml`)**: Declarative configuration that tells CaptainHook about your provider - what it's called, which built-in verifier to use, where to get secrets from environment variables, and security settings.

- **Actions (`captain_hook/stripe/actions/*.rb`)**: Your business logic. Each action processes a specific event type (e.g., "payment succeeded"). They run as background jobs, so heavy processing won't block the webhook response. **Actions are automatically discovered on boot!**

- **Gemspec**: Ensures all webhook-related files are included when your gem is packaged and distributed.

## Step 1: Create Provider Configuration (YAML)

**CaptainHook includes built-in verifiers for common providers!** You only need to create a YAML configuration file that references the appropriate built-in verifier.

### Available Built-in Verifiers:

- **`stripe`** - For Stripe webhooks (`CaptainHook::Verifiers::Stripe`)
- **`square`** - For Square webhooks (`CaptainHook::Verifiers::Square`)
- **`paypal`** - For PayPal webhooks (`CaptainHook::Verifiers::Paypal`)
- **`webhook_site`** - For WebhookSite testing (`CaptainHook::Verifiers::WebhookSite`)

### Step 1: Create Provider Configuration

Create a YAML file that defines your provider's webhook settings. The `name` field should be lowercase and URL-friendly (it becomes part of the webhook endpoint).

### Example: Stripe Configuration

Create `captain_hook/providers/stripe/stripe.yml` in your gem:

```yaml
# Provider configuration for Stripe
# Place this file in: captain_hook/providers/stripe/stripe.yml
name: stripe                                    # URL-friendly identifier (lowercase, no spaces)
display_name: Stripe                            # Human-readable name
description: Stripe payment processing webhooks # Brief description

# Reference the built-in Stripe verifier
verifier_class: stripe                          # Use built-in Stripe verifier (CaptainHook::Verifiers::Stripe)

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

### Other Provider Examples:

**PayPal Configuration** (`captain_hook/providers/paypal/paypal.yml`):
```yaml
name: paypal
display_name: PayPal
description: PayPal payment webhooks
verifier_class: paypal  # Uses CaptainHook::Verifiers::Paypal
signing_secret: ENV[PAYPAL_WEBHOOK_ID]
timestamp_tolerance_seconds: 300
active: true
```

**Square Configuration** (`captain_hook/providers/square/square.yml`):
```yaml
name: square
display_name: Square
description: Square payment webhooks
verifier_class: square  # Uses CaptainHook::Verifiers::Square
signing_secret: ENV[SQUARE_SIGNATURE_KEY]
timestamp_tolerance_seconds: 300
active: true
```

### Multi-Tenant Support

If you need multiple instances of the same provider (e.g., supporting multiple Stripe accounts), create separate provider directories:

```yaml
# captain_hook/providers/stripe_primary/stripe_primary.yml
name: stripe_primary
display_name: Stripe (Primary Account)
verifier_class: stripe  # Both use the same built-in Stripe verifier
signing_secret: ENV[STRIPE_PRIMARY_SECRET]

# captain_hook/providers/stripe_secondary/stripe_secondary.yml
name: stripe_secondary
display_name: Stripe (Secondary Account)
verifier_class: stripe  # Both use the same built-in Stripe verifier
signing_secret: ENV[STRIPE_SECONDARY_SECRET]
```

Each instance gets its own webhook URL and actions, but they share the same signature verification logic from the built-in verifier.

## Step 2: Create Action Classes

⚠️ **IMPORTANT CHANGE**: Actions are now automatically discovered from the filesystem! You no longer need to manually register them in an initializer.

Create action classes in `captain_hook/<provider>/actions/` directories. Each action must have a `self.details` class method that returns metadata about the action.

### Example Action Structure

Create `captain_hook/stripe/actions/payment_intent_succeeded_action.rb`:

```ruby
# frozen_string_literal: true

# Action for Stripe payment_intent.succeeded events
# Actions are automatically discovered by scanning captain_hook/*/actions directories
module Stripe
  class PaymentIntentSucceededAction
    # REQUIRED: self.details class method for automatic discovery
    # This tells CaptainHook what event type this action handles
    def self.details
      {
        description: "Handles Stripe payment intent succeeded events",
        event_type: "payment_intent.succeeded",  # REQUIRED: exact event type from webhook
        priority: 100,                           # Optional: lower = higher priority (default: 100)
        async: true,                             # Optional: run in background (default: true)
        max_attempts: 5,                         # Optional: max retry attempts (default: 5)
        retry_delays: [30, 60, 300, 900, 3600]  # Optional: retry delays in seconds
      }
    end

    # Required method signature: webhook_action(event:, payload:, metadata:)
    # @param event [CaptainHook::IncomingEvent] The stored webhook event
    # @param payload [Hash] The parsed webhook payload
    # @param metadata [Hash] Additional metadata about the webhook
    def webhook_action(event:, payload:, metadata:)
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
```

**Example: Stripe Charge Succeeded**

Create `captain_hook/stripe/actions/charge_succeeded_action.rb`:

```ruby
# frozen_string_literal: true

module Stripe
  class ChargeSucceededAction
    def self.details
      {
        description: "Handles Stripe charge succeeded events",
        event_type: "charge.succeeded",
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
      charge_id = payload.dig("data", "object", "id")
      amount = payload.dig("data", "object", "amount")
      receipt_url = payload.dig("data", "object", "receipt_url")

      Rails.logger.info "Charge succeeded: #{charge_id} for #{amount}"

      # Your business logic here
    end
  end
end
```

**Example: Using Wildcards for Multiple Events**

Create `captain_hook/square/actions/bank_account_action.rb`:

```ruby
# frozen_string_literal: true

module Square
  class BankAccountAction
    def self.details
      {
        description: "Handles all Square bank account events",
        event_type: "bank_account.*",  # Wildcard matches all bank_account.* events
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
      # event.event_type will be the specific event (e.g., "bank_account.verified")
      case event.event_type
      when "bank_account.created"
        # Handle created
      when "bank_account.verified"
        # Handle verified
      when "bank_account.disabled"
        # Handle disabled
      end
    end
  end
end
```

### Important Notes About Actions

**Namespacing**: Actions MUST be namespaced with a module matching the provider name:
- For provider "stripe": `module Stripe; class YourAction; end; end`
- For provider "paypal": `module Paypal; class YourAction; end; end`
- For provider "square": `module Square; class YourAction; end; end`

**File Location**: Actions MUST be in `captain_hook/<provider>/actions/` directory

**Class Name**: The file name should match the class name in snake_case:
- `payment_intent_action.rb` → `class PaymentIntentAction`
- `charge_succeeded_action.rb` → `class ChargeSucceededAction`

**Required Methods**:
1. `self.details` - Class method returning a hash with at minimum `:event_type`
2. `webhook_action(event:, payload:, metadata:)` - Instance method that processes the webhook

**Actions are NOT ActiveJob classes!** They are plain Ruby classes with a `webhook_action` method. CaptainHook wraps them in its own job system (`IncomingActionJob`) which provides:
- Automatic retry logic with exponential backoff
- Priority-based execution
- Status tracking and logging
- Optimistic locking to prevent duplicate processing

If you need to enqueue additional background jobs from within a action, you can do so:

```ruby
def webhook_action(event:, payload:, metadata:)
  # Process some data immediately
  payment_id = payload.dig("data", "object", "id")
  
  # Enqueue additional background work
  SendReceiptEmailJob.perform_later(payment_id)
  UpdateAnalyticsJob.perform_later(payment_id)
end
```

## Step 3: Update Your Gemspec

✨ **NEW**: Actions are now automatically discovered! No manual registration needed.

Make sure your gemspec includes the `captain_hook` directory:

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

  # IMPORTANT: Include captain_hook directory for automatic action discovery
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

### How Automatic Discovery Works

When your Rails application boots with CaptainHook installed:

1. **Filesystem Scan**: CaptainHook scans all `captain_hook/<provider>/actions/**/*.rb` files in the load path
2. **Class Loading**: Each action file is loaded and its class is instantiated
3. **Details Extraction**: The `self.details` method is called to get event type, priority, async settings, etc.
4. **Registration**: Actions are automatically registered in the ActionRegistry
5. **Database Sync**: Registered actions are synced to the database for tracking

**You don't need to do anything beyond creating the action files!** Just:
- Put them in the right directory (`captain_hook/<provider>/actions/`)
- Namespace them correctly (`module ProviderName; class ActionName`)
- Include a `self.details` class method
- Include a `webhook_action` instance method

### Verifying Actions Are Discovered

After installing your gem and restarting the Rails server, check that actions were discovered:

```ruby
# Rails console - View discovered actions
CaptainHook::Action.where(provider: "stripe")
# Should show your Stripe actions

# Check if a specific action exists
CaptainHook::Action.find_by(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::PaymentIntentSucceededAction"
)
# Should return the action record

# View all actions
CaptainHook::Action.all
```

You should also see log messages during boot:
```
🔍 CaptainHook: Auto-scanning providers and actions...
✅ Discovered action: Stripe::PaymentIntentSucceededAction for stripe:payment_intent.succeeded
✅ CaptainHook: Synced actions - Created: 3, Updated: 0, Skipped: 0
```

## Step 4: Install in Your Rails App

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

## Step 6: Configure Your Provider's Webhook Settings

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

## Step 7: Testing Locally

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

### Check actions are discovered:

```ruby
# Rails console - Check actions in database
CaptainHook::Action.where(provider: "stripe")
# Should show your Stripe actions

# Check specific action
CaptainHook::Action.find_by(
  provider: "stripe",
  event_type: "payment_intent.succeeded"
)
# Should return the action record with class name "Stripe::PaymentIntentSucceededAction"

# View all actions
CaptainHook::Action.all
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

## Adding More Event Actions

✨ **NEW**: Just create a new action file - no registration needed!

To handle additional events from your provider:

1. **Create a new action file** in `captain_hook/<provider>/actions/`
2. **Add the `self.details` method** with the event type
3. **Restart your Rails server** - actions are automatically discovered on boot

### Example: Adding a New Stripe Event

For handling `invoice.payment_succeeded`:

```ruby
# captain_hook/stripe/actions/invoice_payment_succeeded_action.rb
# frozen_string_literal: true

module Stripe
  class InvoicePaymentSucceededAction
    def self.details
      {
        description: "Handles Stripe invoice payment succeeded events",
        event_type: "invoice.payment_succeeded",
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
      invoice_id = payload.dig("data", "object", "id")
      # Your logic here
      Rails.logger.info "Invoice paid: #{invoice_id}"
    end
  end
end
```

That's it! When you restart the Rails server, CaptainHook will automatically discover this action and register it.

## Troubleshooting

### Actions not being called?

**Most common issue**: Actions not discovered or files in wrong location

1. **Verify actions are discovered**:
   ```ruby
   # Rails console - Check if action exists in database
   CaptainHook::Action.find_by(
     provider: "stripe",
     event_type: "payment_intent.succeeded"
   )
   # Should return an Action record
   ```
   
   If this returns nil, your actions weren't discovered! Check:
   - Are action files in `captain_hook/<provider>/actions/` directory?
   - Is the provider name in the path matching the provider in the database? (e.g., "stripe" not "Stripe")
   - Does the action class have a `self.details` method?
   - Is the action class properly namespaced (e.g., `module Stripe; class ActionName`)?
   - Did you restart the Rails server after creating the action file?

2. **Check Rails logs during boot** for discovery messages:
   ```bash
   tail -f log/development.log | grep "CaptainHook"
   ```
   You should see:
   ```
   🔍 CaptainHook: Auto-scanning providers and actions...
   ✅ Discovered action: Stripe::PaymentIntentSucceededAction for stripe:payment_intent.succeeded
   ```

3. **Check if provider exists**: 
   ```ruby
   CaptainHook::Provider.find_by(name: "stripe")
   ```
   If nil, use "Discover New" or "Full Sync" in the admin UI

4. **Check Sidekiq is running** (actions are background jobs)
   ```bash
   bundle exec sidekiq
   ```

5. **Check Rails logs** for errors:
   ```bash
   tail -f log/development.log
   ```
   Look for action execution errors or job failures

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
5. Check your verifier implementation matches the provider's documentation
6. Enable debug logging to see the signature verification process

### Provider not discovered?

1. Make sure YAML file is in `captain_hook/providers/stripe.yml`
2. Make sure gemspec includes `captain_hook/**/*` in files
3. Run bundle install and restart server
4. Try scanning again

## Complete Example Event Processing Flow

1. **Provider sends webhook** → Your Rails app at `/captain_hook/[provider]/[TOKEN]`
   - Example: `/captain_hook/stripe/abc123` or `/captain_hook/paypal/xyz789`
2. **CaptainHook receives** → Verifies signature using the built-in verifier
3. **Creates IncomingEvent** → Stores event in database for audit trail
4. **Finds registered actions** → Looks up actions for `provider` + `event_type`
   - Example: `stripe` + `payment_intent.succeeded`
5. **Enqueues action jobs** → Adds jobs to background queue (Sidekiq/Solid Queue)
6. **Actions execute** → Your business logic runs in background jobs
7. **Updates action status** → Marks as completed or failed, with retry logic

---

## Contributing New Verifiers

**Need a verifier for a provider not currently supported?**

Verifiers can only be created within the CaptainHook gem itself to ensure consistent security verification across all installations. To add support for a new provider:

1. **Check if it already exists**: Review the list of built-in verifiers in `lib/captain_hook/verifiers/`

2. **Submit a Pull Request** to the CaptainHook repository:
   - Create a new verifier class in `lib/captain_hook/verifiers/your_provider.rb`
   - Inherit from `CaptainHook::Verifiers::Base`
   - Implement the required methods (see [docs/VERIFIERS.md](VERIFIERS.md))
   - Add comprehensive tests
   - Include documentation about the provider's webhook signature scheme

3. **Example verifier structure**:
   ```ruby
   # lib/captain_hook/verifiers/your_provider.rb
   module CaptainHook
     module Verifiers
       class YourProvider < Base
         def verify_signature(payload:, headers:, provider_config:)
           # Implementation here
         end
         
         def extract_event_id(payload)
           # Extract unique event ID
         end
         
         def extract_event_type(payload)
           # Extract event type string
         end
       end
     end
   end
   ```

4. **Reference documentation**: See existing verifiers (Stripe, Square, PayPal) in `lib/captain_hook/verifiers/` for examples

For detailed information about creating verifiers, see [docs/VERIFIERS.md](VERIFIERS.md).
