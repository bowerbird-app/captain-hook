# CaptainHook Restructuring: Architecture Changes

## High-Level Overview

### The Problem

Previously, every gem or application that wanted to integrate with CaptainHook had to:
1. Implement their own webhook adapter (signature verification code)
2. Create provider configuration
3. Write handler classes for webhook processing

This led to:
- **Code duplication**: Multiple gems implementing the same Stripe/Square/PayPal adapters
- **Maintenance burden**: Adapter code scattered across many gems
- **Integration complexity**: Gems had to understand low-level signature verification details
- **No multi-tenant support**: Couldn't easily support multiple instances of the same provider

### The Solution

**CaptainHook now ships with built-in adapters** for common webhook providers:
- Stripe
- Square
- PayPal
- WebhookSite (testing)

**Gems only provide:**
- Handler classes (business logic)
- Provider YAML configs (settings)

**Benefits:**
- ✅ Simpler gem integration (no adapter code needed)
- ✅ Centralized adapter maintenance
- ✅ Multi-tenant support (multiple Stripe accounts, etc.)
- ✅ Consistent security implementations
- ✅ Easier to contribute new providers

### Multi-Tenant Support

A key feature of this restructuring is supporting multiple instances of the same provider:

**Example: SaaS with Multiple Stripe Accounts**

```yaml
# config for customer A
name: stripe_customer_a
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[STRIPE_SECRET_CUSTOMER_A]

# config for customer B
name: stripe_customer_b
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[STRIPE_SECRET_CUSTOMER_B]
```

Each instance:
- Uses the same adapter class
- Has unique name and webhook URL
- Has separate signing secret
- Can have different handlers

## Technical Implementation

### Architecture Changes

#### Before

```
gem_a/
├── app/adapters/captain_hook/adapters/
│   └── stripe.rb                    # Adapter code in gem
├── captain_hook/
│   ├── providers/stripe.yml         # Provider config
│   └── handlers/payment_handler.rb  # Handler

gem_b/
├── app/adapters/captain_hook/adapters/
│   └── stripe.rb                    # DUPLICATE adapter code
├── captain_hook/
│   ├── providers/stripe.yml         # Provider config
│   └── handlers/payment_handler.rb  # Handler
```

Problems:
- Duplicate adapter code in every gem
- Hard to maintain consistency
- No support for multiple accounts

#### After

```
captain_hook/ (gem)
├── lib/captain_hook/adapters/
│   ├── base.rb                      # ✅ Base adapter
│   ├── stripe.rb                    # ✅ Built-in Stripe adapter
│   ├── square.rb                    # ✅ Built-in Square adapter
│   ├── paypal.rb                    # ✅ Built-in PayPal adapter
│   └── webhook_site.rb              # ✅ Built-in test adapter
├── captain_hook/providers/
│   ├── stripe.yml.example           # ✅ Example configs
│   ├── square.yml.example
│   └── paypal.yml.example

gem_a/
├── captain_hook/
│   ├── providers/stripe_gem_a.yml   # Uses CaptainHook::Adapters::Stripe
│   └── handlers/payment_handler.rb  # Business logic only

gem_b/
├── captain_hook/
│   ├── providers/stripe_gem_b.yml   # Uses CaptainHook::Adapters::Stripe
│   └── handlers/payment_handler.rb  # Business logic only

rails_app/ (optional custom adapter)
└── app/adapters/captain_hook/adapters/
    └── custom_provider.rb           # Custom adapter for non-standard provider
```

Benefits:
- ✅ Single source of truth for common adapters
- ✅ Gems focus on business logic
- ✅ Multi-tenant support via unique provider names
- ✅ Custom adapters still possible

### File Changes

#### New Files

**Adapters (moved to gem):**
- `lib/captain_hook/adapters/base.rb` - Base adapter class
- `lib/captain_hook/adapters/stripe.rb` - Stripe implementation
- `lib/captain_hook/adapters/square.rb` - Square implementation
- `lib/captain_hook/adapters/paypal.rb` - PayPal implementation
- `lib/captain_hook/adapters/webhook_site.rb` - Testing adapter

**Discovery Service:**
- `lib/captain_hook/services/adapter_discovery.rb` - Finds available adapters

**Templates:**
- `captain_hook/providers/stripe.yml.example` - Stripe template
- `captain_hook/providers/square.yml.example` - Square template
- `captain_hook/providers/paypal.yml.example` - PayPal template
- `captain_hook/providers/webhook_site.yml.example` - Testing template
- `captain_hook/providers/README.md` - Documentation

#### Modified Files

**Core:**
- `lib/captain_hook.rb` - Added adapter requires
- `captain_hook.gemspec` - Include captain_hook directory

**Documentation:**
- `README.md` - Added built-in adapter info, multi-tenant examples
- `docs/GEM_WEBHOOK_SETUP.md` - Simplified, emphasize built-in adapters
- `docs/ADAPTERS.md` - Updated with contributing guidelines
- `CHANGELOG.md` - Documented all changes

### Code Examples

#### Using a Built-in Adapter

```yaml
# captain_hook/providers/stripe.yml
name: stripe
display_name: Stripe
adapter_class: CaptainHook::Adapters::Stripe  # ✅ Built-in
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300
active: true
```

#### Multi-Tenant Setup

```yaml
# Payment gem's provider
name: payment_gem_stripe
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[PAYMENT_GEM_STRIPE_SECRET]

# Subscription gem's provider
name: subscription_gem_stripe
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[SUBSCRIPTION_GEM_STRIPE_SECRET]
```

Handler registration:
```ruby
# payment_gem/lib/payment_gem/engine.rb
CaptainHook.register_handler(
  provider: "payment_gem_stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "PaymentGem::StripePaymentHandler"
)

# subscription_gem/lib/subscription_gem/engine.rb
CaptainHook.register_handler(
  provider: "subscription_gem_stripe",
  event_type: "invoice.payment_succeeded",
  handler_class: "SubscriptionGem::StripeInvoiceHandler"
)
```

#### Need Support for a New Provider?

Adapters can only be created within the CaptainHook gem itself to ensure consistent security verification:

```ruby
# lib/captain_hook/adapters/custom_provider.rb (in CaptainHook gem)
module CaptainHook
  module Adapters
    class CustomProvider < Base
      def verify_signature(payload:, headers:)
        # Custom verification logic
        signature = headers["X-Custom-Signature"]
        expected = generate_hmac(provider_config.signing_secret, payload)
        secure_compare(signature, expected)
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

To add support for a new provider, submit a pull request to the CaptainHook gem or contact the maintainers.

### Discovery Mechanism

The `AdapterDiscovery` service finds adapters from:

1. **Built-in adapters** (in CaptainHook gem):
   - CaptainHook::Adapters::Stripe
   - CaptainHook::Adapters::Square
   - CaptainHook::Adapters::Paypal
   - CaptainHook::Adapters::WebhookSite

2. **Custom adapters**:
   - Must be added to `lib/captain_hook/adapters/` in the CaptainHook gem
   - Automatically available in admin UI dropdown after gem update

### Security Implications

**Improved Security:**
- ✅ Centralized security updates affect all users
- ✅ Peer-reviewed implementations in CaptainHook gem
- ✅ Consistent constant-time comparisons
- ✅ Proper timestamp validation
- ✅ All adapters audited before release

**Controlled Extension:**
- New adapters must be added to CaptainHook gem (via PR)
- Environment variable override still works
- Application-specific handler logic supported

### Backward Compatibility

**Breaking Change:**
If a gem previously provided its own adapter:
- Remove the adapter file from your application/gem
- Update provider YAML to use built-in CaptainHook adapter
- Handlers and registration code unchanged

**Migration Path:**
1. Remove custom adapter files (adapters now in CaptainHook gem only)
2. Update provider YAML: `adapter_class: CaptainHook::Adapters::Stripe`
3. Test signature verification still works
4. Deploy

**Non-Breaking:**
- Handler registration unchanged
- Provider discovery unchanged
- Admin UI unchanged

## Benefits Summary

### For Gem Developers
- ✅ No adapter code to write or maintain
- ✅ Focus on business logic (handlers)
- ✅ Multi-tenant support built-in
- ✅ Faster integration

### For CaptainHook Maintainers
- ✅ Single place to update adapters
- ✅ Easier to add new providers
- ✅ Better test coverage
- ✅ Community contributions more valuable

### For End Users
- ✅ More reliable webhook processing
- ✅ Consistent security across providers
- ✅ Better documentation
- ✅ Easier debugging

## Future Enhancements

This restructuring enables:
- More built-in adapters (Shopify, GitHub, Twilio, etc.)
- Adapter versioning and upgrades
- Provider-specific optimizations
- Better testing tools
- Adapter marketplace/registry
