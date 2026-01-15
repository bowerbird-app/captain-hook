# Provider Templates

This directory contains example provider configuration files that ship with CaptainHook.

## How It Works

### For CaptainHook Gem

These `.yml.example` files serve as **templates** and **documentation** for common webhook providers. They are **NOT automatically loaded** by CaptainHook - they're here for reference only.

### For Host Applications

To use a provider in your Rails application:

1. **Copy the template** to your application's `captain_hook/providers/` directory:
   ```bash
   mkdir -p captain_hook/providers
   cp captain_hook/providers/stripe.yml.example captain_hook/providers/stripe.yml
   ```

2. **Edit the configuration** to match your setup (especially environment variable names)

3. **Set environment variables** with your actual secrets:
   ```bash
   # .env
   STRIPE_WEBHOOK_SECRET=whsec_your_secret_here
   ```

4. **Scan for providers** in the admin UI at `/captain_hook/admin/providers`

### For Other Gems

If you're building a gem that integrates with a webhook provider:

1. **Include the adapter** - Ship an adapter class in your gem if CaptainHook doesn't have one built-in

2. **Include a provider YAML** - Add `captain_hook/providers/your_provider.yml` to your gem

3. **Include handlers** - Add `captain_hook/handlers/*.rb` to process specific events

4. **Register handlers** - In your gem's engine.rb, register which handlers process which events

See `docs/GEM_WEBHOOK_SETUP.md` for detailed instructions.

## Multi-Tenant Providers

CaptainHook supports multiple instances of the same provider with different credentials.

### Example: Multiple Stripe Accounts

**Gem A** wants Stripe webhooks:
```yaml
# gem_a/captain_hook/providers/stripe_gem_a.yml
name: stripe_gem_a
display_name: Stripe (Gem A)
description: Stripe webhooks for Gem A
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[GEM_A_STRIPE_SECRET]
```

**Gem B** also wants Stripe webhooks:
```yaml
# gem_b/captain_hook/providers/stripe_gem_b.yml
name: stripe_gem_b
display_name: Stripe (Gem B)
description: Stripe webhooks for Gem B
adapter_class: CaptainHook::Adapters::Stripe
signing_secret: ENV[GEM_B_STRIPE_SECRET]
```

Both use the same `CaptainHook::Adapters::Stripe` adapter but have different:
- Provider names (`stripe_gem_a` vs `stripe_gem_b`)
- Signing secrets (different environment variables)
- Webhook URLs (generated based on provider name)

Each gem registers handlers for their own provider name:
```ruby
# gem_a/lib/gem_a/engine.rb
CaptainHook.register_handler(
  provider: "stripe_gem_a",
  event_type: "payment_intent.succeeded",
  handler_class: "GemA::StripePaymentHandler"
)

# gem_b/lib/gem_b/engine.rb
CaptainHook.register_handler(
  provider: "stripe_gem_b",
  event_type: "payment_intent.succeeded",
  handler_class: "GemB::StripePaymentHandler"
)
```

## Available Adapters

CaptainHook ships with these adapters:

- **Stripe** - `CaptainHook::Adapters::Stripe`
- **Square** - `CaptainHook::Adapters::Square`
- **PayPal** - `CaptainHook::Adapters::Paypal`
- **WebhookSite** - `CaptainHook::Adapters::WebhookSite` (testing only)

### Need a New Provider?

If you need a provider not listed above, the adapter must be added to the CaptainHook gem itself. Contact the maintainers or submit a pull request to add support for your provider.

Adapters can only be created within the CaptainHook gem at `lib/captain_hook/adapters/` to ensure consistent security and verification logic across all installations.

See `docs/ADAPTERS.md` for details on CaptainHook's adapter architecture.
