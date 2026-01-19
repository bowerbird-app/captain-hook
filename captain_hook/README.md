# Provider Configuration

This directory contains provider configuration files for webhook integrations with CaptainHook.

## Directory Structure

Each provider has its own folder with the following structure:

```
captain_hook/
├── stripe/
│   ├── stripe.yml           # Provider configuration
│   ├── stripe.rb            # (Optional) Custom verifier if not built-in
│   └── actions/             # Action files for this provider
│       ├── payment_intent_succeeded_action.rb
│       └── charge_refunded_action.rb
├── paypal/
│   ├── paypal.yml
│   └── actions/
└── square/
    ├── square.yml
    └── actions/
```

## How It Works

### Built-in Verifiers (Automatic Discovery)

**CaptainHook now includes built-in verifiers for common providers!**

For supported providers (Stripe, Square, PayPal, WebhookSite), you **only need the YAML file**. CaptainHook will automatically find and use the built-in verifier.

```
captain_hook/
├── stripe/
│   ├── stripe.yml       # verifier_file: stripe.rb will use built-in verifier
│   └── actions/         # Your actions go here
├── square/
│   ├── square.yml
│   └── actions/
└── paypal/
    ├── paypal.yml
    └── actions/
```

When you specify `verifier_file: stripe.rb` in your YAML, CaptainHook will:
1. First check your app's provider directory for a custom verifier
2. Then check in loaded gems
3. Finally check CaptainHook's built-in verifiers

### Custom Verifiers (When Needed)

For providers not included in CaptainHook, create custom verifiers:

```
captain_hook/
└── custom_provider/
    ├── custom_provider.yml       # Configuration with verifier_file: custom_provider.rb
    ├── custom_provider.rb        # Your custom verifier logic
    └── actions/                  # Your actions
        └── event_action.rb
```

## ⚠️ Important: Check Before Creating

**Before creating a new provider, check if one already exists!**

If your app or a gem already has a provider for your service (e.g., `stripe`), you typically **don't need to create a new one**. Just register your actions in the provider's `actions/` folder.

**One Provider = One Webhook Endpoint**
- A provider represents a single webhook URL with signature verification
- Multiple actions can share the same provider to process different event types
- Actions for a provider should be placed in its `actions/` folder
- Only create separate providers for multi-tenant scenarios (different accounts/secrets)

See `docs/GEM_WEBHOOK_SETUP.md` for detailed guidance on when to share vs. create providers.

## Setting Up a Provider

### For Host Applications

To use a provider in your Rails application:

1. **Create a provider folder** in your application's `captain_hook/` directory:
   ```bash
   mkdir -p captain_hook/stripe/actions
   ```

2. **Create the YAML configuration** as `stripe.yml`:
   ```yaml
   name: stripe
   display_name: Stripe
   verifier_file: stripe.rb  # CaptainHook will find the built-in verifier automatically!
   signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
   ```

3. **Set environment variables** with your actual secrets:
   ```bash
   # .env
   STRIPE_WEBHOOK_SECRET=whsec_your_secret_here
   ```

4. **Add your actions** to the `actions/` folder:
   ```ruby
   # captain_hook/stripe/actions/payment_intent_succeeded_action.rb
   module Stripe
     class PaymentIntentSucceededAction
       def self.call(event)
         # Process payment.intent.succeeded event
       end
     end
   end
   ```

5. **Register actions** in an initializer or engine:
   ```ruby
   # config/initializers/captain_hook.rb
   CaptainHook.configure do |config|
     config.action_registry.register(
       provider: "stripe",
       event_type: "payment_intent.succeeded",
       action_class: Stripe::PaymentIntentSucceededAction
     )
   end
   ```

6. **Scan for providers** in the admin UI at `/captain_hook/admin/providers`

**Note:** You don't need to create `stripe.rb` - CaptainHook includes built-in verifiers. For custom providers, create the `.rb` file alongside the YAML.

### For Other Gems

If you're building a gem that integrates with a webhook provider:

1. **Use built-in verifiers when available** - No need to ship your own verifier for Stripe, Square, PayPal, or WebhookSite

2. **Include the YAML and actions** - Add to your gem:
   ```
   captain_hook/
   └── stripe/
       ├── stripe.yml              # Provider config
       └── actions/                # Your actions
           └── subscription_updated_action.rb
   ```

3. **For custom providers** - Ship both the YAML and verifier file if CaptainHook doesn't have a built-in verifier

4. **Register actions** - In your gem's engine.rb, register which actions process which events

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
verifier_file: stripe_gem_a.rb
signing_secret: ENV[GEM_A_STRIPE_SECRET]
```

**Gem B** also wants Stripe webhooks:
```yaml
# gem_b/captain_hook/providers/stripe_gem_b.yml
name: stripe_gem_b
display_name: Stripe (Gem B)
description: Stripe webhooks for Gem B
verifier_file: stripe_gem_b.rb
signing_secret: ENV[GEM_B_STRIPE_SECRET]
```

Both use the same `CaptainHook::Verifiers::Stripe` verifier but have different:
- Provider names (`stripe_gem_a` vs `stripe_gem_b`)
- Signing secrets (different environment variables)
- Webhook URLs (generated based on provider name)

Each gem registers actions for their own provider name:
```ruby
# gem_a/lib/gem_a/engine.rb
CaptainHook.register_action(
  provider: "stripe_gem_a",
  event_type: "payment_intent.succeeded",
  action_class: "GemA::StripePaymentHandler"
)

# gem_b/lib/gem_b/engine.rb
CaptainHook.register_action(
  provider: "stripe_gem_b",
  event_type: "payment_intent.succeeded",
  action_class: "GemB::StripePaymentHandler"
)
```

## Available Built-in Verifiers

CaptainHook ships with these verifiers built-in - **automatically discovered**:

- **Stripe** - `stripe.rb` - Full signature verification with HMAC-SHA256
- **Square** - `square.rb` - HMAC-SHA256 with Base64 encoding
- **PayPal** - `paypal.rb` - Certificate-based verification (simplified)
- **WebhookSite** - `webhook_site.rb` - No verification (testing only)
- **Base** - `base.rb` - No-op verifier (for custom implementations)

Simply use `verifier_file: stripe.rb` in your YAML - CaptainHook will find the built-in verifier automatically!

### Need a Custom Provider?

For providers not listed above:

1. **Create a custom verifier file** (e.g., `captain_hook/providers/myservice/myservice.rb`)
2. **Implement the verifier interface**:
   ```ruby
   class MyServiceVerifier
     include CaptainHook::VerifierHelpers
     
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
3. **Reference the file in your YAML** with `verifier_file: myservice.rb`

Alternatively, consider submitting a pull request to add your verifier to CaptainHook as a built-in!
