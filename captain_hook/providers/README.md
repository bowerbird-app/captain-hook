# Provider Templates

This directory contains example provider configuration files that ship with CaptainHook.

## How It Works

### Built-in Adapters (Recommended)

**CaptainHook now includes built-in adapters for common providers!**

For supported providers (Stripe, Square, PayPal, WebhookSite), you **only need the YAML file**. No Ruby adapter file required!

```
captain_hook/providers/
├── stripe/
│   └── stripe.yml       # Configuration only - adapter built into CaptainHook
├── square/
│   └── square.yml
└── paypal/
    └── paypal.yml
```

### Custom Adapters (When Needed)

For providers not included in CaptainHook, you can still create custom adapters:

```
captain_hook/providers/
└── custom_provider/
    ├── custom_provider.yml       # Configuration
    └── custom_provider.rb        # Your custom adapter logic
```

These `.yml.example` files serve as templates for creating your own provider folders.

## ⚠️ Important: Check Before Creating

**Before creating a new provider, check if one already exists!**

If your app or a gem already has a provider for your service (e.g., `stripe`), you typically **don't need to create a new one**. Just register your handlers for the existing provider.

**One Provider = One Webhook Endpoint**
- A provider represents a single webhook URL with signature verification
- Multiple handlers can share the same provider to process different event types
- Only create separate providers for multi-tenant scenarios (different accounts/secrets)

See `docs/GEM_WEBHOOK_SETUP.md` for detailed guidance on when to share vs. create providers.

### For Host Applications

To use a built-in provider in your Rails application:

1. **Create a provider folder** in your application's `captain_hook/providers/` directory:
   ```bash
   mkdir -p captain_hook/providers/stripe
   ```

2. **Copy the template** to the folder as `stripe.yml`:
   ```bash
   cp gem_path/captain_hook/providers/stripe.yml.example captain_hook/providers/stripe/stripe.yml
   ```

3. **Edit the configuration** to use the built-in adapter:
   ```yaml
   name: stripe
   display_name: Stripe
   adapter_class: CaptainHook::Adapters::Stripe  # Use built-in adapter!
   signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
   ```

4. **Set environment variables** with your actual secrets:
   ```bash
   # .env
   STRIPE_WEBHOOK_SECRET=whsec_your_secret_here
   ```

5. **Scan for providers** in the admin UI at `/captain_hook/admin/providers`

**Note:** For custom providers not included in CaptainHook, you can still create a custom adapter file (e.g., `custom_provider.rb`) and reference it with `adapter_file: custom_provider.rb` in the YAML.

### For Other Gems

If you're building a gem that integrates with a webhook provider:

1. **Use built-in adapters when available** - No need to ship your own adapter for Stripe, Square, PayPal, or WebhookSite

2. **Include only the YAML** - Add `captain_hook/providers/your_provider.yml` to your gem with `adapter_class: CaptainHook::Adapters::Stripe`

3. **For custom providers** - Ship both the YAML and adapter class if CaptainHook doesn't have a built-in adapter

4. **Include handlers** - Add `captain_hook/handlers/*.rb` to process specific events

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
adapter_file: stripe_gem_a.rb
signing_secret: ENV[GEM_A_STRIPE_SECRET]
```

**Gem B** also wants Stripe webhooks:
```yaml
# gem_b/captain_hook/providers/stripe_gem_b.yml
name: stripe_gem_b
display_name: Stripe (Gem B)
description: Stripe webhooks for Gem B
adapter_file: stripe_gem_b.rb
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

## Available Built-in Adapters

CaptainHook ships with these adapters built-in - **no adapter files needed**:

- **Stripe** - `CaptainHook::Adapters::Stripe` - Full signature verification with HMAC-SHA256
- **Square** - `CaptainHook::Adapters::Square` - HMAC-SHA256 with Base64 encoding
- **PayPal** - `CaptainHook::Adapters::Paypal` - Certificate-based verification (simplified)
- **WebhookSite** - `CaptainHook::Adapters::WebhookSite` - No verification (testing only)
- **Base** - `CaptainHook::Adapters::Base` - No-op adapter (for custom implementations)

Simply use `adapter_class: CaptainHook::Adapters::Stripe` in your YAML configuration!

### Need a Custom Provider?

For providers not listed above:

1. **Create a custom adapter file** (e.g., `captain_hook/providers/myservice/myservice.rb`)
2. **Implement the adapter interface**:
   ```ruby
   class MyServiceAdapter
     include CaptainHook::AdapterHelpers
     
     def verify_signature(payload:, headers:, provider_config:)
       # Your verification logic
     end
     
     def extract_event_id(payload)
       payload["id"]
     end
     
     def extract_event_type(payload)
       payload["type"]
     end
   end
   ```
3. **Reference the file in your YAML** with `adapter_file: myservice.rb`

Alternatively, consider submitting a pull request to add your adapter to CaptainHook as a built-in!
