# CaptainHook Rails Engine

A comprehensive Rails engine for receiving and processing webhooks from external providers with features including signature verification, rate limiting, retry logic, and admin UI.

## How It Works

CaptainHook provides a complete webhook management system with automatic discovery, verification, and processing:

1. **Provider Setup**: Define providers in YAML files (`captain_hook/<provider>/<provider>.yml`) - automatically discovered on boot
2. **Global Configuration**: Set defaults in `config/captain_hook.yml` for max_payload_size_bytes and timestamp_tolerance_seconds
3. **Action Registration**: Register actions in `config/initializers/captain_hook.rb` - automatically synced to database on boot
4. **Webhook Reception**: External provider sends POST to `/captain_hook/:provider/:token`
5. **Security Validation**: Token → Rate limit → Payload size → Signature → Timestamp (configurable)
6. **Event Storage**: Creates `IncomingEvent` with idempotency (unique index on provider + external_id)
7. **Action Execution**: Looks up actions from database, creates execution records, enqueues jobs
8. **Background Processing**: `IncomingActionJob` executes actions with retry logic and exponential backoff
9. **Observability**: ActiveSupport::Notifications events for monitoring

**Key Architecture Points:**
- **Registry as Source of Truth**: Provider configuration (verifier, signing secret, display name) comes from YAML files
- **Minimal Database Storage**: Database only stores runtime data: token, active status, rate limits
- **Global Configuration**: Host app can override defaults via `config/captain_hook.yml`
- **ENV-based Secrets**: Signing secrets reference environment variables (e.g., `ENV[STRIPE_WEBHOOK_SECRET]`)
- **File-based Discovery**: Providers and verifiers auto-discovered from YAML files in app or gems
- **In-Memory Registry**: Actions stored in thread-safe `ActionRegistry` then synced to database
- **Idempotency**: Duplicate webhooks (same provider + external_id) return 200 OK without re-processing
- **Async by Default**: Actions run in background jobs with configurable retry delays
- **Provider Verifiers**: Each provider has verifier class for signature verification (Stripe, Square, PayPal, etc.)

## Features

- **Incoming Webhooks**
  - Idempotency via unique `(provider, external_id)` index
  - Provider-specific signature verification verifiers
  - Rate limiting per provider
  - Payload size limits
  - Timestamp validation to prevent replay attacks
  - Action priority and ordering
  - Automatic retry with exponential backoff
  - Optimistic locking for safe concurrency

- **Provider Management**
  - Registry-based provider configuration (YAML files as source of truth)
  - Minimal database storage for runtime data (token, rate limits, active status)
  - Global configuration file for application-wide defaults
  - Per-provider security settings via YAML
  - Webhook URL generation for sharing with providers
  - Active/inactive status control
  - ENV-based signing secret management
  - Built-in verifiers for Stripe, Square, PayPal, WebhookSite

- **Admin Interface**
  - View and manage providers
  - View incoming events with filtering
  - View registered actions per provider
  - **Edit and configure actions** (async/sync, retries, priority)
  - **Auto-Discovery**: Providers and actions automatically synced on boot
  - **Duplicate detection**: Warns when same provider exists in multiple sources
  - **Soft-delete actions** to prevent re-addition
  - Monitor event processing status
  - Track action execution

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

### 1. Global Configuration (Optional)

Create `config/captain_hook.yml` to set application-wide defaults:

```yaml
# config/captain_hook.yml
defaults:
  max_payload_size_bytes: 1048576      # 1MB default
  timestamp_tolerance_seconds: 300     # 5 minutes default

# Per-provider overrides (optional)
providers:
  stripe:
    max_payload_size_bytes: 2097152    # 2MB for Stripe
  square:
    timestamp_tolerance_seconds: 600    # 10 minutes for Square
```

**Note**: Individual provider YAML files can override these defaults. The priority is:
1. Provider YAML file value (highest priority)
2. Global config per-provider override
3. Global config default
4. Built-in default (lowest priority)

### 2. Environment Variables for Signing Secrets

CaptainHook now stores signing secrets as environment variable references (not in the database).

Set your provider webhook secrets as environment variables:

```bash
# .env or production environment
STRIPE_WEBHOOK_SECRET=whsec_xxxxx
SQUARE_WEBHOOK_SECRET=your_square_secret
PAYPAL_WEBHOOK_SECRET=your_paypal_secret
```

**Important**: Provider YAML files reference these via `ENV[VARIABLE_NAME]` syntax.

### 3. Configure Providers

CaptainHook uses a file-based provider discovery system. Create provider configuration files in `captain_hook/<provider>/` directory.

**Providers and actions are automatically discovered and synced to the database when your Rails application starts.** There's no need to manually scan - just define your providers in YAML and register your actions in code, then restart your application.

**Provider verifiers are distributed with individual gems** (like `example-stripe`, `example-square`) or can be created in your host application. Each verifier handles provider-specific signature verification and event extraction.

Common providers typically have verifiers available:
- **Stripe** - Check for gems like `example-stripe` or create your own
- **Square** - Check for gems like `example-square` or create your own
- **PayPal** - Check for gems like `example-paypal` or create your own

See [Setting Up Webhooks in Your Gem](docs/GEM_WEBHOOK_SETUP.md) for how to create verifiers.

**Create the directory structure:**

```bash
mkdir -p captain_hook/stripe/actions
```

**Create a provider YAML file** (e.g., `captain_hook/stripe/stripe.yml`):

You can copy from the example templates shipped with CaptainHook and customize:

```yaml
# captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe
description: Stripe payment and subscription webhooks
verifier_file: stripe.rb
active: true

# Security settings
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]

# Rate limiting (optional - can be set per-provider or in database)
rate_limit_requests: 100
rate_limit_period: 60

# Payload size and timestamp tolerance now come from global config
# But can be overridden here if needed for this specific provider
# timestamp_tolerance_seconds: 600
# max_payload_size_bytes: 2097152
```

**Note on configuration priority:**
- `signing_secret`: Must be in provider YAML as `ENV[VARIABLE_NAME]` reference
- `rate_limit_requests/rate_limit_period`: Can be in YAML or set via admin UI (stored in database)
- `timestamp_tolerance_seconds/max_payload_size_bytes`: Come from global config by default, can override in provider YAML

**Create the verifier file** (if needed - Stripe has a built-in verifier) (`captain_hook/stripe/stripe.rb`):

```ruby
# frozen_string_literal: true

class StripeVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "Stripe-Signature"

  def verify_signature(payload:, headers:, provider_config:)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return false if signature_header.blank?

    parsed = parse_kv_header(signature_header)
    timestamp = parsed["t"]
    signatures = [parsed["v1"], parsed["v0"]].flatten.compact
    
    return false if timestamp.blank? || signatures.empty?

    if provider_config.timestamp_validation_enabled?
      tolerance = provider_config.timestamp_tolerance_seconds || 300
      return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
    end

    signed_payload = "#{timestamp}.#{payload}"
    expected_signature = generate_hmac(provider_config.signing_secret, signed_payload)

    signatures.any? { |sig| secure_compare(sig, expected_signature) }
  end

  def extract_timestamp(headers)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return nil if signature_header.blank?
    parse_kv_header(signature_header)["t"]&.to_i
  end

  def extract_event_id(payload)
    payload["id"]
  end

  def extract_event_type(payload)
    payload["type"]
  end
end
```

**Set environment variables:**

```bash
# .env or your environment
STRIPE_WEBHOOK_SECRET=whsec_your_secret_here
```

**Restart your application:**

When your Rails application starts, CaptainHook will automatically:
1. Discover providers from YAML files in `captain_hook/<provider>/`
2. Sync them to the database
3. Discover registered actions from your code
4. Sync them to the database

You can view the discovered providers at `/captain_hook/admin/providers`

Providers are automatically discovered from:
- Your Rails app: `Rails.root/captain_hook/<provider_name>/<provider_name>.yml`
- Loaded gems: `<gem_root>/captain_hook/<provider_name>/<provider_name>.yml`

Actions are automatically loaded from:
- Provider's `actions/` folder: `captain_hook/<provider_name>/actions/*.rb`

The `signing_secret` will be automatically encrypted in the database using AES-256-GCM encryption. Using `ENV[VARIABLE_NAME]` format ensures secrets are read from environment variables and never committed to version control.

**Multiple Instances of Same Provider:**

You can have multiple instances of the same provider type (e.g., multiple Stripe accounts). Each needs its own directory with YAML config and verifier file:

```yaml
# captain_hook/stripe_account_a/stripe_account_a.yml
name: stripe_account_a
display_name: Stripe (Account A)
verifier_file: stripe_account_a.rb
signing_secret: ENV[STRIPE_SECRET_ACCOUNT_A]

# captain_hook/stripe_account_b/stripe_account_b.yml
name: stripe_account_b
display_name: Stripe (Account B)  
verifier_file: stripe_account_b.rb
signing_secret: ENV[STRIPE_SECRET_ACCOUNT_B]
```

```ruby
# captain_hook/stripe_account_a/stripe_account_a.rb
class StripeAccountAVerifier
  include CaptainHook::VerifierHelpers
  # Same Stripe verification logic
end

# captain_hook/stripe_account_b/stripe_account_b.rb
class StripeAccountBVerifier
  include CaptainHook::VerifierHelpers
  # Same Stripe verification logic
end
```

Each gets its own webhook URL and can have different actions.

### 3. Get Your Webhook URL

Each provider gets a unique webhook URL with a secure token. The URL is automatically generated and displayed in the admin UI:

```ruby
provider.webhook_url
# => "https://your-app.com/captain_hook/stripe/abc123token..."
```

**The URL format**: `/captain_hook/:provider_name/:token`

Share this URL with your provider (e.g., in Stripe's webhook settings). The token ensures that only requests to the correct URL are processed.

**Codespaces/Forwarding**: CaptainHook automatically detects GitHub Codespaces URLs or you can set `APP_URL` environment variable to override the base URL.

### 4. Create a Action

Create a action class in the provider's `actions/` folder:

```ruby
# captain_hook/stripe/actions/payment_succeeded_action.rb
class StripePaymentSucceededAction
  def webhook_action(event:, payload:, metadata:)
    payment_intent_id = payload.dig("data", "object", "id")
    Payment.find_by(stripe_id: payment_intent_id)&.mark_succeeded!
  end
end
```

Action method signature:
- `event`: The `CaptainHook::IncomingEvent` record
- `payload`: The parsed JSON payload (Hash)
- `metadata`: Additional metadata (Hash with `:timestamp`, `:headers`, etc.)

### 5. Actions Are Automatically Discovered!

✨ **NEW**: No manual registration needed! Just create action files in the right location.

CaptainHook automatically scans `captain_hook/<provider>/actions/**/*.rb` directories and discovers actions on boot.

**Action Structure Required:**

```ruby
# captain_hook/stripe/actions/payment_succeeded_action.rb
module Stripe
  class PaymentSucceededAction
    # REQUIRED: Metadata for automatic discovery
    def self.details
      {
        description: "Handles Stripe payment succeeded events",
        event_type: "payment_intent.succeeded",  # REQUIRED
        priority: 100,                           # Optional (default: 100)
        async: true,                             # Optional (default: true)
        max_attempts: 5                          # Optional (default: 5)
      }
    end

    # REQUIRED: Webhook processing method
    def webhook_action(event:, payload:, metadata:)
      # Your business logic here
    end
  end
end
```

**Wildcard Event Types:**

```ruby
# captain_hook/square/actions/bank_account_action.rb
module Square
  class BankAccountAction
    def self.details
      {
        event_type: "bank_account.*",  # Matches bank_account.created, bank_account.verified, etc.
        priority: 100,
        async: true
      }
    end

    def webhook_action(event:, payload:, metadata:)
      # event.event_type contains the specific event
      case event.event_type
      when "bank_account.created"
        # Handle created
      when "bank_account.verified"
        # Handle verified
      end
    end
  end
end
```

**After creating action files, restart your Rails application.** CaptainHook will automatically discover and sync the actions to the database on boot.

You can view your discovered actions at `/captain_hook/admin/providers/:id/actions`

**Important**: 
- Actions must be in `captain_hook/<provider>/actions/` directories
- Action classes must be namespaced under the provider module (e.g., `module Stripe`)
- Action classes must have a `self.details` class method with at least `:event_type`
- Action classes must have a `webhook_action` instance method

For more details, see [docs/GEM_WEBHOOK_SETUP.md](docs/GEM_WEBHOOK_SETUP.md) and [docs/ACTION_DISCOVERY.md](docs/ACTION_DISCOVERY.md).

### 6. Test with Sandbox

CaptainHook includes a webhook sandbox at `/captain_hook/admin/sandbox`:

1. Select a provider
2. Enter a sample payload (JSON)
3. Click "Send Test Webhook"
4. View the results and action execution logs

This lets you test your actions without needing to trigger real events from the provider.

## Configuration

### Provider Settings

Each provider can be configured with:

- **name**: Unique identifier (lowercase, underscores only)
- **display_name**: Human-readable name
- **signing_secret**: Secret for HMAC signature verification
- **verifier_file**: Ruby file containing the verifier class for provider-specific signature verification
- **timestamp_tolerance_seconds**: Tolerance window for timestamp validation (prevents replay attacks)
- **max_payload_size_bytes**: Maximum payload size (DoS protection)
- **rate_limit_requests**: Maximum requests per period
- **rate_limit_period**: Time period for rate limiting (seconds)
- **active**: Enable/disable webhook reception

### Action Registration

Actions can be configured with:

- **provider**: Provider name (must match a provider)
- **event_type**: Event type to handle (e.g., "payment.succeeded")
- **action_class**: Class name (as string) that implements the action
- **priority**: Execution order (lower numbers run first)
- **async**: Whether to run in background job (default: true)
- **max_attempts**: Maximum retry attempts (default: 5)
- **retry_delays**: Array of delays between retries in seconds (default: [30, 60, 300, 900, 3600])

## Verifiers

Verifiers handle provider-specific signature verification and event extraction. They are distributed with individual gems (like `example-stripe`, `example-square`) or can be created in your host application.

### Using an Verifier

Verifiers are specified in your provider YAML configuration:

```yaml
# captain_hook/providers/stripe.yml
name: stripe
verifier_file: stripe.rb
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

### Providers Without Signature Verification

For providers that don't support signature verification (e.g., testing environments, internal webhooks), you can omit the `verifier_file` field entirely:

```yaml
# captain_hook/providers/internal_service.yml
name: internal_service
display_name: Internal Service
description: Internal webhooks without verification
# verifier_file: (not specified - no signature verification)
active: true
```

**Security Warning**: Providers without signature verification rely solely on token-based URL authentication. Only use this for:
- Trusted internal services within your infrastructure
- Development/testing environments
- Services that don't provide signature verification mechanisms

For production external webhooks, always use an verifier with proper signature verification.

### Creating a Custom Verifier

Verifiers can be created in your host application or distributed as separate gems. See [docs/VERIFIERS.md](docs/VERIFIERS.md) for detailed implementation guide, or check out [Setting Up Webhooks in Your Gem](docs/GEM_WEBHOOK_SETUP.md) for building verifiers in gems.

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
3. Provider-specific signature verification (via verifier)
4. Timestamp validation (optional, but recommended)
5. Rate limiting (optional, but recommended)
6. Payload size limits (optional, but recommended)

**Environment Variables**: Never commit secrets to version control. Always use `.env` files (gitignored) or your hosting platform's environment variables.

## Admin Interface

Access the admin interface at `/captain_hook/admin`:

- **Providers**: Manage webhook providers, view webhook URLs, configure settings
  - **Scan for Providers**: Discover providers from YAML files and sync to database
  - **Scan Actions**: Discover and sync actions for each provider
- **Incoming Events**: View all received webhooks with filtering and search
- **Actions**: View, edit, and manage registered actions per provider
  - Configure async/sync execution mode
  - Set retry attempts and delays
  - Adjust action priority
  - Soft-delete actions to prevent re-addition
- **Sandbox**: Test webhooks without triggering real events from providers

See [Action Management](docs/ACTION_MANAGEMENT.md) for detailed documentation on managing actions.

## Testing Webhooks

### Using the Sandbox

1. Navigate to `/captain_hook/admin/sandbox`
2. Select your provider from the dropdown
3. Enter a test payload (JSON format)
4. Click "Send Test Webhook"
5. View action execution results and logs

The sandbox bypasses signature verification for easy testing.

### Testing from External Provider

Most providers offer webhook testing tools:

- **Stripe CLI**: 
  ```bash
  # Trigger test events
  stripe trigger payment_intent.succeeded
  
  # Or forward webhooks to your local server
  stripe listen --forward-to localhost:3000/captain_hook/stripe/YOUR_TOKEN
  ```
  Replace `YOUR_TOKEN` with your provider's token from the admin UI.

- **Square**: Use the Square Sandbox webhook simulator
- **PayPal**: Use the PayPal webhook simulator in the developer dashboard

### Using webhook.site or similar

Create a provider with the `CaptainHook::Verifiers::WebhookSite` verifier for simple testing without signature verification.

## Action Examples

### Basic Action

```ruby
# captain_hook/stripe/actions/payment_succeeded_action.rb
module Stripe
  class PaymentSucceededAction
    def self.details
      {
        description: "Handles Stripe payment succeeded events",
        event_type: "payment_intent.succeeded",
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
      Rails.logger.info "Payment succeeded: #{payload.dig('data', 'object', 'id')}"
    end
  end
end
```

### Action with Error Handling

```ruby
# captain_hook/stripe/actions/payment_succeeded_action.rb
module Stripe
  class PaymentSucceededAction
    def self.details
      {
        event_type: "payment_intent.succeeded",
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
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
end
```

### Action with Wildcard Event Types

```ruby
# captain_hook/square/actions/bank_account_action.rb
# Handles multiple related events
module Square
  class BankAccountAction
    def self.details
      {
        description: "Handles Square bank account events",
        event_type: "bank_account.*",  # Wildcard matches all bank_account.* events
        priority: 100,
        async: true
      }
    end

    def webhook_action(event:, payload:, metadata:)
      event_type = payload["type"]
      bank_account = payload.dig("data", "object")
      
      # event.event_type contains the specific event
      case event.event_type
      when "bank_account.verified"
        BankAccount.find_by(square_id: bank_account["id"])&.mark_verified!
      when "bank_account.disabled"
        BankAccount.find_by(square_id: bank_account["id"])&.mark_disabled!
      end
    end
  end
end

# No manual registration needed - automatically discovered on boot!
```

## Documentation

### For Gem Developers

**Building a gem that needs webhook support?** 

See our comprehensive guide: [**Setting Up Webhooks in Your Gem**](docs/GEM_WEBHOOK_SETUP.md)

This guide shows you how to create provider verifiers, action classes, and YAML configurations that integrate seamlessly with CaptainHook. Perfect for payment processing gems, notification services, or any gem that receives webhooks from external providers.

### General Documentation

- **Action Management**: [docs/ACTION_MANAGEMENT.md](docs/ACTION_MANAGEMENT.md) - Managing actions via admin UI
- **Provider Discovery**: [docs/PROVIDER_DISCOVERY.md](docs/PROVIDER_DISCOVERY.md) - File-based provider configuration
- **Verifiers Reference**: [docs/VERIFIERS.md](docs/VERIFIERS.md) - Detailed verifier implementation guide
- **Signing Secret Storage**: [docs/SIGNING_SECRET_STORAGE.md](docs/SIGNING_SECRET_STORAGE.md) - Security and encryption details
- **Visual Guide**: [docs/VISUAL_GUIDE.md](docs/VISUAL_GUIDE.md) - Screenshots and UI walkthrough
- **Performance Benchmarks**: [benchmark/README.md](benchmark/README.md) - Benchmarking suite and CI integration

## Development

### Running Tests

```bash
bundle exec rake test
```

### Running Benchmarks

```bash
# From test/dummy app
cd test/dummy && RAILS_ENV=test bundle exec rake benchmark:all

# Individual benchmarks
cd test/dummy && RAILS_ENV=test bundle exec rake benchmark:signatures
cd test/dummy && RAILS_ENV=test bundle exec rake benchmark:database
cd test/dummy && RAILS_ENV=test bundle exec rake benchmark:actions
```

See [benchmark/README.md](benchmark/README.md) for complete documentation.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
