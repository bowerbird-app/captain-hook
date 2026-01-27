# Gem Webhook Setup Guide

## Overview

This guide shows **gem authors** how to integrate webhook handling into their gems using CaptainHook. When developers install your gem alongside CaptainHook in their Rails applications, your webhook providers and actions will be automatically discovered and made available without any additional configuration.

## What This Guide Covers

- Setting up the correct directory structure in your gem
- Creating provider configurations (YAML files)
- Creating custom verifiers for signature verification
- Creating webhook actions that process events
- Testing your gem integration
- Publishing and documenting your gem

## Who This Guide Is For

- Gem authors building integrations with third-party APIs
- Developers creating reusable webhook handlers
- Library maintainers providing webhook support
- Anyone wanting to package webhook integrations as gems

## Prerequisites

Your gem users will need:
- Rails 6.0 or higher
- CaptainHook gem installed in their application
- Ruby 2.7 or higher

Your gem should:
- Be compatible with Rails engines
- Follow Ruby gem conventions
- Have proper gemspec configuration

## Quick Start

Here's a minimal example of a gem that provides Stripe webhook integration:

```
your_gem/
├── lib/
│   ├── your_gem.rb
│   └── your_gem/
│       └── version.rb
├── captain_hook/
│   └── stripe/
│       ├── stripe.yml        # Provider configuration
│       ├── stripe.rb          # Custom verifier (optional)
│       └── actions/           # Webhook actions
│           └── payment_intent_succeeded_action.rb
├── your_gem.gemspec
└── README.md
```

When installed, CaptainHook will:
1. Discover your `captain_hook/` directory
2. Load provider configurations from YAML files
3. Register custom verifiers
4. Discover and sync actions to the database
5. Route webhooks to your actions automatically

## Directory Structure

### Required Structure

Your gem must follow this structure for CaptainHook to discover your webhook integrations:

```
your_gem/
├── captain_hook/                    # Root directory (required)
│   ├── <provider_name>/             # One directory per provider
│   │   ├── <provider_name>.yml      # Provider config (required)
│   │   ├── <provider_name>.rb       # Verifier class (optional)
│   │   └── actions/                 # Actions directory (optional)
│   │       ├── action1.rb
│   │       ├── action2.rb
│   │       └── subdirectory/        # Subdirectories supported
│   │           └── action3.rb
│   └── <another_provider>/
│       └── ...
```

### Key Rules

1. **`captain_hook/` at gem root**: Must be at the root level of your gem, not inside `lib/`
2. **Provider name**: Directory name becomes the provider identifier (use lowercase with underscores)
3. **YAML file naming**: Must match provider directory name (e.g., `stripe/stripe.yml`)
4. **Ruby file naming**: Verifier file should match provider name (e.g., `stripe/stripe.rb`)
5. **Actions directory**: Optional, but must be named exactly `actions/` if present

### Example with Multiple Providers

```
payment_integrations_gem/
├── lib/
│   └── payment_integrations.rb
└── captain_hook/
    ├── stripe/
    │   ├── stripe.yml
    │   ├── stripe.rb
    │   └── actions/
    │       ├── payment_succeeded_action.rb
    │       └── refund_created_action.rb
    ├── paypal/
    │   ├── paypal.yml
    │   ├── paypal.rb
    │   └── actions/
    │       └── payment_captured_action.rb
    └── square/
        ├── square.yml
        └── actions/
            └── payment_updated_action.rb
```

## Provider Configuration (YAML)

### Basic Configuration

Create a YAML file at `captain_hook/<provider>/<provider>.yml`:

```yaml
# captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe Payments
description: Webhook integration for Stripe payment events
verifier_file: stripe.rb

# Security settings
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300
max_payload_size_bytes: 1048576
```

### Configuration Fields

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | **Yes** | String | Provider identifier (must match directory name) |
| `display_name` | No | String | Human-readable name for admin UI |
| `description` | No | String | Brief description of the provider |
| `verifier_file` | **Yes** | String | Name of verifier Ruby file (can reference built-in verifiers) |
| `signing_secret` | **Yes** | String | ENV variable reference for webhook secret |
| `timestamp_tolerance_seconds` | No | Integer | Seconds to allow for clock skew (default: 300) |
| `max_payload_size_bytes` | No | Integer | Maximum webhook payload size (default: 1048576) |

### Environment Variable Pattern

**Always** use the `ENV[VARIABLE_NAME]` pattern for secrets:

```yaml
# ✅ CORRECT: References environment variable
signing_secret: ENV[YOUR_GEM_STRIPE_WEBHOOK_SECRET]

# ❌ WRONG: Hardcoded secret (security risk!)
signing_secret: whsec_abc123...

# ❌ WRONG: Rails.application.credentials won't work
signing_secret: Rails.application.credentials.stripe_webhook_secret
```

### Using Built-in Verifiers

CaptainHook includes a built-in Stripe verifier. Reference it directly:

```yaml
# captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe (via YourGem)
description: Stripe webhooks provided by YourGem
verifier_file: stripe.rb  # Uses CaptainHook's built-in Stripe verifier

signing_secret: ENV[YOUR_GEM_STRIPE_SECRET]
```

**Built-in verifiers available:**
- `stripe.rb` - Stripe signature verification

### Namespacing Your Provider

To avoid conflicts with host app or other gems, consider namespacing:

```yaml
# Option 1: Prefix with gem name
name: your_gem_stripe
display_name: Stripe (via YourGem)

# Option 2: Use descriptive suffix
name: stripe_marketplace
display_name: Stripe Marketplace Webhooks
```

## Custom Verifiers

### When to Create a Custom Verifier

Create a custom verifier when:
- The provider's signature scheme isn't built into CaptainHook
- You need custom validation logic
- The provider uses non-standard authentication

### Verifier Template

Create `captain_hook/<provider>/<provider>.rb`:

```ruby
# captain_hook/custom_provider/custom_provider.rb
# frozen_string_literal: true

# Define at gem root level (not inside module)
class CustomProviderVerifier
  # Include helper methods (HMAC, header extraction, secure compare, etc.)
  include CaptainHook::VerifierHelpers

  # Required: Define signature header name
  SIGNATURE_HEADER = "X-Custom-Provider-Signature"
  TIMESTAMP_HEADER = "X-Custom-Provider-Timestamp"

  # Required: Implement signature verification
  # @param payload [String] Raw request body
  # @param headers [Hash] Request headers (case-insensitive)
  # @param provider_config [CaptainHook::ProviderConfig] Provider configuration
  # @return [Boolean] true if signature is valid, false otherwise
  def verify_signature(payload:, headers:, provider_config:)
    # Extract signature from headers
    signature = extract_header(headers, SIGNATURE_HEADER)
    return false if signature.blank?

    # Extract timestamp if provider uses it
    timestamp = extract_header(headers, TIMESTAMP_HEADER)
    
    # Validate timestamp (optional but recommended)
    if provider_config.timestamp_validation_enabled? && timestamp.present?
      return false unless timestamp_within_tolerance?(
        timestamp.to_i,
        provider_config.timestamp_tolerance_seconds
      )
    end

    # Generate expected signature
    # This depends on your provider's algorithm
    data_to_sign = "#{timestamp}.#{payload}"
    expected_signature = generate_hmac(provider_config.signing_secret, data_to_sign)

    # Constant-time comparison (prevents timing attacks)
    secure_compare(signature, expected_signature)
  end
end
```

### Available Helper Methods

CaptainHook provides these helper methods via `VerifierHelpers`:

```ruby
# HMAC generation
generate_hmac(secret, data)           # Returns hex-encoded HMAC-SHA256
generate_hmac_base64(secret, data)    # Returns base64-encoded HMAC-SHA256

# Header extraction
extract_header(headers, "X-Signature") # Case-insensitive header lookup
extract_header(headers, "Key1", "Key2") # Try multiple keys

# Header parsing
parse_kv_header("t=123,v1=abc")       # Parses key=value header format
# => {"t"=>"123", "v1"=>"abc"}

# Security
secure_compare(a, b)                  # Constant-time string comparison
timestamp_within_tolerance?(ts, tol)  # Check if timestamp is recent

# Validation
missing_signing_secret?(provider_config) # Check if secret is configured
```

### Example: HMAC-SHA256 with Timestamp

```ruby
class HmacProviderVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Provider-Signature"
  TIMESTAMP_HEADER = "X-Provider-Timestamp"

  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, SIGNATURE_HEADER)
    timestamp = extract_header(headers, TIMESTAMP_HEADER)
    
    return false if signature.blank? || timestamp.blank?

    # Validate timestamp
    if provider_config.timestamp_validation_enabled?
      return false unless timestamp_within_tolerance?(
        timestamp.to_i,
        provider_config.timestamp_tolerance_seconds
      )
    end

    # Create signature: HMAC-SHA256(timestamp.payload, secret)
    data_to_sign = "#{timestamp}.#{payload}"
    expected = generate_hmac(provider_config.signing_secret, data_to_sign)
    
    secure_compare(signature, expected)
  end
end
```

### Example: Multi-Version Signatures (Stripe-style)

```ruby
class VersionedSignatureVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Signature"

  def verify_signature(payload:, headers:, provider_config:)
    sig_header = extract_header(headers, SIGNATURE_HEADER)
    return false if sig_header.blank?

    # Parse header: "t=1234567890,v1=abc123,v0=def456"
    parsed = parse_kv_header(sig_header)
    timestamp = parsed["t"]
    signatures = [parsed["v1"], parsed["v0"]].flatten.compact

    return false if timestamp.blank? || signatures.empty?

    # Validate timestamp
    if provider_config.timestamp_validation_enabled?
      return false unless timestamp_within_tolerance?(
        timestamp.to_i,
        provider_config.timestamp_tolerance_seconds
      )
    end

    # Try all signature versions
    data_to_sign = "#{timestamp}.#{payload}"
    expected = generate_hmac(provider_config.signing_secret, data_to_sign)
    
    signatures.any? { |sig| secure_compare(sig, expected) }
  end
end
```

## Creating Actions

### Action Structure

Actions process webhook events. Create them in `captain_hook/<provider>/actions/`:

```ruby
# captain_hook/stripe/actions/payment_intent_succeeded_action.rb
# frozen_string_literal: true

# Namespace with provider module (required!)
module Stripe
  class PaymentIntentSucceededAction
    # Required: Define action metadata
    def self.details
      {
        event_type: "payment_intent.succeeded",
        description: "Process successful Stripe payment intents",
        priority: 100,           # Lower = runs first (default: 100)
        async: true,             # Run in background (default: true)
        max_attempts: 5,         # Retry attempts (default: 5)
        retry_delays: [30, 60, 300, 900, 3600]  # Retry delays in seconds
      }
    end

    # Required: Process webhook event
    # @param event [CaptainHook::IncomingEvent] Database record of the webhook
    # @param payload [Hash] Parsed JSON payload
    # @param metadata [Hash] Additional metadata (reserved for future use)
    def webhook_action(event:, payload:, metadata: {})
      # Extract data from payload
      payment_intent = payload.dig("data", "object")
      payment_intent_id = payment_intent["id"]
      
      # Your business logic here
      Rails.logger.info "Processing payment: #{payment_intent_id}"
      
      # Example: Update your models
      order = find_order_by_payment_intent(payment_intent_id)
      order&.mark_as_paid!
      
      # Example: Send notifications
      OrderMailer.payment_confirmation(order).deliver_later if order
      
    rescue StandardError => e
      # Log error for debugging
      Rails.logger.error "Failed to process payment: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Re-raise to trigger retry
      raise
    end
    
    private
    
    def find_order_by_payment_intent(payment_intent_id)
      # Your gem's logic to find associated record
      # This depends on your gem's data model
    end
  end
end
```

### Action Metadata (`.details` method)

The `.details` class method **must** return a hash with these fields:

| Field | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `event_type` | **Yes** | String | N/A | Event type or pattern (e.g., `"payment.succeeded"`) |
| `description` | No | String | `nil` | Human-readable description |
| `priority` | No | Integer | `100` | Execution order (lower = first) |
| `async` | No | Boolean | `true` | Run in background job |
| `max_attempts` | No | Integer | `5` | Maximum retry attempts |
| `retry_delays` | No | Array | `[30, 60, 300, 900, 3600]` | Retry delays in seconds |

### Event Type Patterns

Actions support wildcards:

```ruby
# Exact match
def self.details
  { event_type: "payment_intent.succeeded" }
end

# Wildcard: all payment_intent.* events
def self.details
  { event_type: "payment_intent.*" }
end

# Catch-all: all events for this provider
def self.details
  { event_type: "*" }
end
```

### Module Namespacing (Critical!)

**Always namespace actions with the provider module:**

```ruby
# ✅ CORRECT: Namespaced with provider
module Stripe
  class PaymentIntentAction
    # ...
  end
end

# ❌ WRONG: No namespace
class StripePaymentIntentAction
  # Won't be discovered!
end

# ❌ WRONG: Wrong namespace
module MyGem
  class PaymentIntentAction
    # Won't be discovered!
  end
end
```

### Gem Action Namespacing

CaptainHook automatically namespaces your gem's actions to prevent conflicts:

```ruby
# Your gem defines:
# captain_hook/stripe/actions/payment_action.rb
module Stripe
  class PaymentAction
    # ...
  end
end

# Stored in database as:
# "YourGemName::Stripe::PaymentAction"
# 
# This prevents conflicts if:
# - Host app defines Stripe::PaymentAction
# - Another gem defines Stripe::PaymentAction
```

All three can coexist and will execute in priority order!

### File Naming Conventions

```ruby
# File: payment_intent_succeeded_action.rb
# Class: Stripe::PaymentIntentSucceededAction

# File: charge_refunded_action.rb
# Class: Stripe::ChargeRefundedAction

# File: webhook_logger.rb (custom name)
# Class: Stripe::WebhookLogger
```

### Multiple Actions Per Provider

You can provide multiple actions:

```ruby
# captain_hook/stripe/actions/
├── payment_intent_succeeded_action.rb    # High priority
├── payment_intent_failed_action.rb       # Normal priority
├── charge_refunded_action.rb             # Normal priority
└── logging/
    └── all_events_logger_action.rb       # Low priority, wildcard
```

## Complete Example: Building a Payment Gem

Let's create a complete example gem that provides Stripe webhook integration:

### Gem Structure

```
stripe_toolkit/
├── lib/
│   ├── stripe_toolkit.rb
│   └── stripe_toolkit/
│       ├── version.rb
│       └── models/
│           └── payment.rb
├── captain_hook/
│   └── stripe/
│       ├── stripe.yml
│       └── actions/
│           ├── payment_succeeded_action.rb
│           ├── payment_failed_action.rb
│           └── refund_created_action.rb
├── stripe_toolkit.gemspec
└── README.md
```

### Provider Configuration

```yaml
# captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe (via StripeToolkit)
description: Stripe webhook integration provided by StripeToolkit gem
verifier_file: stripe.rb

signing_secret: ENV[STRIPE_TOOLKIT_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300
max_payload_size_bytes: 2097152
```

### Payment Success Action

```ruby
# captain_hook/stripe/actions/payment_succeeded_action.rb
# frozen_string_literal: true

module Stripe
  class PaymentSucceededAction
    def self.details
      {
        event_type: "payment_intent.succeeded",
        description: "Mark payments as successful and notify users",
        priority: 50,
        async: true,
        max_attempts: 5,
        retry_delays: [30, 60, 300, 900, 3600]
      }
    end

    def webhook_action(event:, payload:, metadata: {})
      payment_intent = payload.dig("data", "object")
      
      # Find or create payment record
      payment = StripeToolkit::Payment.find_or_initialize_by(
        stripe_payment_intent_id: payment_intent["id"]
      )
      
      payment.update!(
        status: "succeeded",
        amount: payment_intent["amount"],
        currency: payment_intent["currency"],
        succeeded_at: Time.current,
        metadata: payment_intent["metadata"]
      )
      
      # Trigger gem's notification system
      StripeToolkit::Notifications.payment_succeeded(payment)
      
      Rails.logger.info "[StripeToolkit] Payment succeeded: #{payment.id}"
    end
  end
end
```

### Payment Failed Action

```ruby
# captain_hook/stripe/actions/payment_failed_action.rb
# frozen_string_literal: true

module Stripe
  class PaymentFailedAction
    def self.details
      {
        event_type: "payment_intent.payment_failed",
        description: "Handle failed payments and notify users",
        priority: 50,
        async: true,
        max_attempts: 3,  # Fewer retries for failures
        retry_delays: [30, 60, 300]
      }
    end

    def webhook_action(event:, payload:, metadata: {})
      payment_intent = payload.dig("data", "object")
      error = payment_intent.dig("last_payment_error", "message")
      
      payment = StripeToolkit::Payment.find_or_initialize_by(
        stripe_payment_intent_id: payment_intent["id"]
      )
      
      payment.update!(
        status: "failed",
        error_message: error,
        failed_at: Time.current
      )
      
      # Trigger gem's notification system
      StripeToolkit::Notifications.payment_failed(payment, error)
      
      Rails.logger.warn "[StripeToolkit] Payment failed: #{payment.id} - #{error}"
    end
  end
end
```

### Refund Action

```ruby
# captain_hook/stripe/actions/refund_created_action.rb
# frozen_string_literal: true

module Stripe
  class RefundCreatedAction
    def self.details
      {
        event_type: "charge.refunded",
        description: "Process refunds and update payment records",
        priority: 100,
        async: true,
        max_attempts: 5
      }
    end

    def webhook_action(event:, payload:, metadata: {})
      charge = payload.dig("data", "object")
      refunds = charge["refunds"]["data"]
      
      refunds.each do |refund|
        StripeToolkit::Refund.create!(
          stripe_refund_id: refund["id"],
          stripe_charge_id: charge["id"],
          amount: refund["amount"],
          status: refund["status"],
          reason: refund["reason"],
          refunded_at: Time.at(refund["created"])
        )
      end
      
      Rails.logger.info "[StripeToolkit] Processed #{refunds.length} refund(s)"
    end
  end
end
```

### Gemspec Configuration

```ruby
# stripe_toolkit.gemspec
Gem::Specification.new do |spec|
  spec.name          = "stripe_toolkit"
  spec.version       = StripeToolkit::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["you@example.com"]

  spec.summary       = "Stripe integration toolkit with webhook handling"
  spec.description   = "Provides Stripe webhook integration via CaptainHook"
  spec.homepage      = "https://github.com/yourusername/stripe_toolkit"
  spec.license       = "MIT"

  spec.files         = Dir[
    "lib/**/*",
    "captain_hook/**/*",  # Important: Include webhook files!
    "README.md",
    "LICENSE.txt"
  ]

  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "rails", ">= 6.0"
  
  # Note: Don't add captain_hook as dependency if it's optional
  # Document it as a peer dependency in README instead
  
  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.0"
end
```

## Testing Your Gem Integration

### Testing Action Discovery

```ruby
# spec/integration/captain_hook_integration_spec.rb
require "spec_helper"

RSpec.describe "CaptainHook Integration" do
  describe "action discovery" do
    it "discovers actions from gem" do
      discovery = CaptainHook::Services::ActionDiscovery.new
      actions = discovery.call
      
      stripe_actions = actions.select { |a| a["provider"] == "stripe" }
      
      expect(stripe_actions).to include(
        hash_including(
          "provider" => "stripe",
          "event" => "payment_intent.succeeded",
          "action" => "StripeToolkit::Stripe::PaymentSucceededAction"
        )
      )
    end
  end

  describe "provider discovery" do
    it "discovers provider from gem" do
      discovery = CaptainHook::Services::ProviderDiscovery.new
      providers = discovery.call
      
      stripe_provider = providers.find { |p| p["name"] == "stripe" }
      
      expect(stripe_provider).to include(
        "name" => "stripe",
        "display_name" => "Stripe (via StripeToolkit)",
        "source" => start_with("gem:")
      )
    end
  end
end
```

### Testing Actions

```ruby
# spec/actions/stripe/payment_succeeded_action_spec.rb
require "spec_helper"

RSpec.describe Stripe::PaymentSucceededAction do
  describe ".details" do
    it "returns correct metadata" do
      details = described_class.details
      
      expect(details[:event_type]).to eq("payment_intent.succeeded")
      expect(details[:priority]).to eq(50)
      expect(details[:async]).to be true
    end
  end

  describe "#webhook_action" do
    let(:event) { double(:event, provider: "stripe") }
    let(:payload) do
      {
        "data" => {
          "object" => {
            "id" => "pi_123456",
            "amount" => 5000,
            "currency" => "usd"
          }
        }
      }
    end

    it "processes payment successfully" do
      action = described_class.new
      
      expect {
        action.webhook_action(event: event, payload: payload, metadata: {})
      }.to change { StripeToolkit::Payment.count }.by(1)
      
      payment = StripeToolkit::Payment.last
      expect(payment.status).to eq("succeeded")
      expect(payment.amount).to eq(5000)
    end
  end
end
```

### Testing in a Dummy Rails App

Create a test Rails app that uses your gem:

```ruby
# spec/dummy/config/application.rb
require "rails/all"
require "captain_hook"
require "stripe_toolkit"

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.0
  end
end
```

```ruby
# spec/integration/webhook_processing_spec.rb
RSpec.describe "Webhook Processing", type: :request do
  let(:provider) { CaptainHook::Provider.find_by(name: "stripe") }
  let(:payload) do
    {
      type: "payment_intent.succeeded",
      data: {
        object: {
          id: "pi_123456",
          amount: 5000,
          currency: "usd"
        }
      }
    }.to_json
  end

  it "processes webhook and executes action" do
    post "/captain_hook/stripe/#{provider.token}",
         params: payload,
         headers: {
           "Content-Type" => "application/json",
           "Stripe-Signature" => generate_valid_signature(payload)
         }

    expect(response).to have_http_status(:ok)
    
    event = CaptainHook::IncomingEvent.last
    expect(event.provider).to eq("stripe")
    expect(event.event_type).to eq("payment_intent.succeeded")
    
    # Check action was created
    action = event.incoming_event_actions.first
    expect(action.action_class).to include("PaymentSucceededAction")
  end
end
```

## Publishing Your Gem

### README Documentation

Document CaptainHook integration in your README:

```markdown
# StripeToolkit

Stripe integration toolkit with automatic webhook handling.

## Installation

Add to your Gemfile:

```ruby
gem 'captain_hook'  # Required for webhook handling
gem 'stripe_toolkit'
```

Run:
```bash
bundle install
rails captain_hook:install  # Install CaptainHook
rails db:migrate           # Run CaptainHook migrations
```

## Webhook Setup

StripeToolkit provides automatic webhook handling via CaptainHook.

### 1. Set Environment Variable

```bash
# .env
STRIPE_TOOLKIT_WEBHOOK_SECRET=whsec_your_webhook_signing_secret
```

### 2. Configure Stripe Dashboard

Set your webhook endpoint in Stripe Dashboard:

```
https://your-app.com/captain_hook/stripe/:token
```

Get the token from: `/captain_hook/admin/providers`

### 3. Select Events

Subscribe to these events in Stripe Dashboard:
- `payment_intent.succeeded`
- `payment_intent.payment_failed`
- `charge.refunded`

### 4. Done!

Webhooks are automatically processed. View them at:
```
https://your-app.com/captain_hook/admin
```

## Provided Webhook Actions

| Event Type | Action | Description |
|------------|--------|-------------|
| `payment_intent.succeeded` | PaymentSucceededAction | Marks payments as successful |
| `payment_intent.payment_failed` | PaymentFailedAction | Handles failed payments |
| `charge.refunded` | RefundCreatedAction | Processes refunds |

## Customization

### Disable Specific Actions

In Rails console or admin UI:

```ruby
action = CaptainHook::Action.find_by(
  provider: "stripe",
  action_class: "StripeToolkit::Stripe::PaymentFailedAction"
)
action.soft_delete!
```

### Override Retry Configuration

```ruby
action.update!(
  max_attempts: 10,
  retry_delays: [60, 120, 300, 600, 1800]
)
```

### Add Custom Actions

Create your own action in your Rails app:

```ruby
# captain_hook/stripe/actions/custom_action.rb
module Stripe
  class CustomAction
    def self.details
      { event_type: "customer.subscription.updated", priority: 50 }
    end

    def webhook_action(event:, payload:, metadata: {})
      # Your custom logic
    end
  end
end
```

## Troubleshooting

### Webhooks Not Processing

1. Check CaptainHook is installed: `bundle list | grep captain_hook`
2. Check migrations ran: `rails db:migrate:status`
3. Check provider exists: Visit `/captain_hook/admin/providers`
4. Check environment variable: `echo $STRIPE_TOOLKIT_WEBHOOK_SECRET`

### Actions Not Discovered

Restart your Rails app:
```bash
rails restart
```

Check logs for discovery messages:
```
🔍 CaptainHook: Found 3 registered action(s)
✅ Created action: StripeToolkit::Stripe::PaymentSucceededAction
```

## Support

- Documentation: https://github.com/yourusername/stripe_toolkit
- Issues: https://github.com/yourusername/stripe_toolkit/issues
```

### Changelog

Document webhook integration in CHANGELOG:

```markdown
## [1.0.0] - 2026-01-27

### Added
- CaptainHook webhook integration
- Automatic Stripe webhook handling
- PaymentSucceededAction for successful payments
- PaymentFailedAction for failed payments
- RefundCreatedAction for refund processing

### Dependencies
- Requires CaptainHook gem for webhook functionality
```

## Best Practices

### 1. Namespace Your Provider

Avoid conflicts with host app:

```yaml
# ✅ GOOD: Namespaced provider name
name: your_gem_stripe
display_name: Stripe (via YourGem)

# ❌ RISKY: Generic provider name
name: stripe  # May conflict with host app's Stripe integration
```

### 2. Use Descriptive Environment Variables

```yaml
# ✅ GOOD: Unique, descriptive
signing_secret: ENV[YOUR_GEM_STRIPE_WEBHOOK_SECRET]

# ❌ BAD: Generic, may conflict
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

### 3. Document Environment Variables

In README, clearly document required environment variables:

```markdown
## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `YOUR_GEM_STRIPE_WEBHOOK_SECRET` | Yes | Stripe webhook signing secret |
| `YOUR_GEM_STRIPE_API_KEY` | No | Stripe API key for optional features |
```

### 4. Handle Missing Dependencies Gracefully

```ruby
# lib/your_gem.rb
if defined?(CaptainHook)
  # CaptainHook is available, webhook features enabled
  Rails.logger.info "YourGem: CaptainHook integration enabled"
else
  # CaptainHook not installed, skip webhook features
  Rails.logger.warn "YourGem: CaptainHook not found. Webhook handling disabled."
end
```

### 5. Provide Sensible Defaults

```ruby
def self.details
  {
    event_type: "payment.succeeded",
    priority: 100,           # Default priority
    async: true,             # Safe default
    max_attempts: 5,         # Reasonable retry count
    retry_delays: [30, 60, 300, 900, 3600]  # Exponential backoff
  }
end
```

### 6. Log Meaningful Information

```ruby
def webhook_action(event:, payload:, metadata: {})
  payment_id = payload.dig("data", "object", "id")
  
  Rails.logger.info "[YourGem] Processing payment: #{payment_id}"
  
  # ... process payment ...
  
  Rails.logger.info "[YourGem] Payment #{payment_id} processed successfully"
rescue StandardError => e
  Rails.logger.error "[YourGem] Failed to process #{payment_id}: #{e.message}"
  raise  # Re-raise for retry
end
```

### 7. Make Actions Idempotent

Actions may be retried, so ensure they can run multiple times safely:

```ruby
def webhook_action(event:, payload:, metadata: {})
  payment_id = payload.dig("data", "object", "id")
  
  # ✅ GOOD: find_or_initialize_by is idempotent
  payment = Payment.find_or_initialize_by(stripe_id: payment_id)
  payment.update!(status: "succeeded")
  
  # ✅ GOOD: Check before creating
  return if Notification.exists?(payment_id: payment.id)
  Notification.create!(payment_id: payment.id, type: "success")
end
```

### 8. Test Edge Cases

```ruby
RSpec.describe Stripe::PaymentSucceededAction do
  it "handles missing payment intent gracefully" do
    payload = { "data" => { "object" => nil } }
    
    action = described_class.new
    expect {
      action.webhook_action(event: event, payload: payload, metadata: {})
    }.not_to raise_error
  end

  it "handles duplicate webhooks idempotently" do
    action = described_class.new
    
    # Process twice with same payload
    2.times do
      action.webhook_action(event: event, payload: payload, metadata: {})
    end
    
    # Should only create one payment record
    expect(Payment.count).to eq(1)
  end
end
```

## Advanced Topics

### Multiple Provider Support

Support multiple providers in one gem:

```
your_gem/
└── captain_hook/
    ├── stripe/
    │   ├── stripe.yml
    │   └── actions/
    ├── paypal/
    │   ├── paypal.yml
    │   └── actions/
    └── square/
        ├── square.yml
        └── actions/
```

### Conditional Action Loading

Load actions based on gem configuration:

```ruby
# lib/your_gem.rb
module YourGem
  class << self
    attr_accessor :enable_webhooks, :webhook_providers

    def configure
      yield self
    end
  end

  # Defaults
  self.enable_webhooks = true
  self.webhook_providers = [:stripe, :paypal]
end

# In action file
return unless YourGem.enable_webhooks
return unless YourGem.webhook_providers.include?(:stripe)
```

### Shared Logic Between Actions

Create base classes for common functionality:

```ruby
# lib/your_gem/webhook_action_base.rb
module YourGem
  class WebhookActionBase
    protected

    def log_webhook(message, level: :info)
      Rails.logger.public_send(level, "[YourGem] #{message}")
    end

    def find_or_create_payment(stripe_id)
      Payment.find_or_create_by!(stripe_payment_intent_id: stripe_id)
    end
  end
end

# In actions
module Stripe
  class PaymentSucceededAction < YourGem::WebhookActionBase
    def webhook_action(event:, payload:, metadata: {})
      log_webhook("Processing payment success")
      payment = find_or_create_payment(payload.dig("data", "object", "id"))
      payment.mark_succeeded!
    end
  end
end
```

## Troubleshooting

### Actions Not Discovered After Gem Install

**Problem**: Installed gem but actions don't appear

**Solution**: Restart Rails application:
```bash
rails restart
```

CaptainHook discovers actions during application boot.

### Provider Conflicts

**Problem**: Your provider name conflicts with host app's provider

**Solution**: Use namespaced provider names:
```yaml
# Instead of: name: stripe
name: your_gem_stripe
```

### Missing Environment Variable Errors

**Problem**: Users get signature verification failures

**Solution**: Document environment variables clearly in README and provide helpful error messages:

```ruby
def verify_signature(payload:, headers:, provider_config:)
  if missing_signing_secret?(provider_config)
    Rails.logger.error "[YourGem] Missing webhook secret. Set ENV['YOUR_GEM_STRIPE_WEBHOOK_SECRET']"
    return false
  end
  
  # ... verification logic ...
end
```

### Actions Execute Multiple Times

**Problem**: Action runs multiple times for one webhook

**Explanation**: This is expected if multiple actions match (specific + wildcard)

**Solution**: Use specific event types and document this behavior in README.

## Example Gems Using CaptainHook

See these examples for reference:

```ruby
# Payment processing gem
gem 'stripe_advanced'  # Stripe webhooks with advanced features
gem 'paypal_toolkit'   # PayPal webhook integration

# E-commerce integrations
gem 'shopify_sync'     # Shopify webhook syncing
gem 'woocommerce_bridge' # WooCommerce webhooks

# SaaS integrations
gem 'intercom_events'  # Intercom webhook handling
gem 'segment_webhooks' # Segment webhook processor
```

## Support and Resources

- **CaptainHook Documentation**: See main README and docs/
- **Action Discovery**: [docs/ACTION_DISCOVERY.md](ACTION_DISCOVERY.md)
- **Provider Discovery**: [docs/PROVIDER_DISCOVERY.md](PROVIDER_DISCOVERY.md)
- **Technical Details**: [TECHNICAL_PROCESS.md](../TECHNICAL_PROCESS.md)

## Checklist

Before publishing your gem:

- [ ] `captain_hook/` directory at gem root
- [ ] Provider YAML file created with all required fields
- [ ] Verifier class created (if custom verification needed)
- [ ] Actions created with correct module namespace
- [ ] `.details` method returns all required fields
- [ ] `webhook_action` method handles events correctly
- [ ] Actions are idempotent (can run multiple times safely)
- [ ] Environment variables documented in README
- [ ] Tests written for actions and verifiers
- [ ] Gemspec includes `captain_hook/**/*` in files
- [ ] README includes setup instructions
- [ ] CHANGELOG documents webhook integration
- [ ] Example webhook payload documented
- [ ] Troubleshooting section in README

## Summary

To integrate your gem with CaptainHook:

1. **Create directory structure**: `captain_hook/<provider>/`
2. **Add provider YAML**: Configuration with ENV variable references
3. **Create verifier** (optional): Custom signature verification
4. **Create actions**: Namespaced classes with `.details` and `webhook_action`
5. **Test thoroughly**: Action discovery, execution, idempotency
6. **Document clearly**: README with setup, env vars, troubleshooting
7. **Publish**: Include `captain_hook/**/*` in gemspec files

When users install your gem, CaptainHook will automatically discover and enable your webhook integration—no additional configuration required!
