# Provider Discovery System - Visual Guide

## UI Changes

### Before: Manual Provider Creation

```
┌────────────────────────────────────────────────────────────┐
│  Webhook Providers                    [Add Provider] ←──── │
├────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ No providers configured yet.                         │  │
│  │                                                       │  │
│  │ Providers represent webhook sources like Stripe,    │  │
│  │ OpenAI, GitHub, etc. Add your first provider to     │  │
│  │ start receiving webhooks.                            │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└────────────────────────────────────────────────────────────┘

User clicks "Add Provider" → Manual form entry → Not version controlled
```

### After: Automated Discovery

```
┌────────────────────────────────────────────────────────────┐
│  Webhook Providers            [Scan for Providers] ←────── │
├────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ No providers configured yet.                         │  │
│  │                                                       │  │
│  │ Providers are discovered from YAML files in the     │  │
│  │ captain_hook/providers/ directory.                   │  │
│  │ [Scan for providers] to discover and create them.   │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└────────────────────────────────────────────────────────────┘

User clicks "Scan for Providers" → Auto-discover → Version controlled
```

## Workflow Diagram

### Discovery Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    User Action                              │
│         Click "Scan for Providers" button                   │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│              ProvidersController#scan                       │
│   POST /captain_hook/admin/providers/scan                   │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│           ProviderDiscovery Service                         │
│   Scan filesystem for YAML configuration files              │
└──────────────────┬──────────────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │                     │
        ▼                     ▼
┌──────────────────┐  ┌──────────────────┐
│  Scan Rails App  │  │   Scan Gems      │
│  captain_hook/   │  │   captain_hook/  │
│  providers/*.yml │  │   providers/*.yml│
└────────┬─────────┘  └──────┬───────────┘
         │                   │
         └──────────┬────────┘
                    │
                    ▼
        ┌────────────────────────┐
        │ Parse YAML Files       │
        │ Add Metadata           │
        │ Return Definitions[]   │
        └────────┬───────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│              ProviderSync Service                           │
│   Sync discovered providers to database                     │
└──────────────────┬──────────────────────────────────────────┘
                   │
        ┌──────────┴──────────────┐
        │                         │
        ▼                         ▼
┌──────────────────┐    ┌─────────────────────┐
│ For Each Provider│    │  Resolve ENV Vars   │
│ Find or Create   │    │  ENV[VAR_NAME]      │
│ in Database      │    │        ↓            │
│                  │    │  ENV["VAR_NAME"]    │
└────────┬─────────┘    └──────────┬──────────┘
         │                         │
         └───────────┬─────────────┘
                     │
                     ▼
            ┌─────────────────┐
            │ Save Provider   │
            │ (Encrypts       │
            │  signing secret)│
            └────────┬────────┘
                     │
                     ▼
        ┌─────────────────────────┐
        │ Track Results:          │
        │ • created: [...]        │
        │ • updated: [...]        │
        │ • errors: [...]         │
        └────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│               Display Flash Message                         │
│   "Scan completed! Created 3 providers, Updated 1"          │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│           Redirect to Provider Index                        │
│   Show table with all discovered/created providers          │
└─────────────────────────────────────────────────────────────┘
```

## File Structure Visualization

### Application Structure

```
your_rails_app/
│
├── config/
│   ├── initializers/
│   │   └── captain_hook.rb         # Handler registrations
│   └── environments/
│       └── production.rb            # ENV: STRIPE_WEBHOOK_SECRET
│
├── captain_hook/                    # ← New centralized location
│   ├── providers/                   # ← YAML configuration files
│   │   ├── stripe.yml              # Stripe provider config
│   │   ├── square.yml              # Square provider config
│   │   └── paypal.yml              # PayPal provider config
│   │
│   ├── handlers/                    # ← Webhook event handlers
│   │   ├── stripe_payment_intent_handler.rb
│   │   ├── square_bank_account_handler.rb
│   │   └── paypal_payment_handler.rb
│   │
│   └── adapters/                    # ← Custom signature adapters (optional)
│       └── custom_service_adapter.rb
│
└── .env                             # ENV variables (gitignored)
    STRIPE_WEBHOOK_SECRET=whsec_xxx
    SQUARE_WEBHOOK_SECRET=sq_xxx
```

### Gem Structure (Optional)

```
my_stripe_gem/
│
├── lib/
│   └── my_stripe_gem.rb
│
└── captain_hook/                    # ← Gem can ship providers!
    ├── providers/
    │   └── stripe.yml              # Auto-discovered when gem loads
    │
    ├── handlers/
    │   └── stripe_payment_handler.rb
    │
    └── adapters/
        └── stripe_adapter.rb
```

## YAML Configuration Example

### File: `captain_hook/providers/stripe.yml`

```yaml
# ============================================
# Stripe Webhook Provider Configuration
# ============================================
# This file is automatically discovered by CaptainHook
# Click "Scan for Providers" in the admin UI to sync

# Required Fields
# ---------------
name: stripe                                    # Unique identifier
adapter_class: CaptainHook::Adapters::Stripe   # Signature verifier

# Optional Display Fields
# -----------------------
display_name: Stripe                            # Human-readable name
description: Stripe payment and subscription webhooks

# Security Settings
# -----------------
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]     # ENV variable reference
timestamp_tolerance_seconds: 300                # 5 minutes (replay attack protection)

# Rate Limiting
# -------------
rate_limit_requests: 100                        # Max requests per period
rate_limit_period: 60                           # Time period (seconds)

# Payload Protection
# ------------------
max_payload_size_bytes: 1048576                # 1 MB max payload

# Status
# ------
active: true                                    # Enable/disable webhook reception
```

## Environment Variable Resolution

### YAML File

```yaml
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

### Environment

```bash
# .env (development/test)
STRIPE_WEBHOOK_SECRET=whsec_dev_secret_123

# Heroku (production)
heroku config:set STRIPE_WEBHOOK_SECRET=whsec_prod_secret_456

# Docker Compose
environment:
  - STRIPE_WEBHOOK_SECRET=whsec_docker_secret_789
```

### Sync Process

```
YAML: "ENV[STRIPE_WEBHOOK_SECRET]"
  ↓
ProviderSync resolves to:
  ↓
ENV["STRIPE_WEBHOOK_SECRET"] → "whsec_dev_secret_123"
  ↓
Save to database (ActiveRecord encrypts):
  ↓
Database: encrypted_value_abc123xyz
  ↓
Provider.signing_secret → "whsec_dev_secret_123" (decrypted on read)
```

## Security Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Developer                                │
│   Creates: captain_hook/providers/stripe.yml                │
│   Sets: ENV[STRIPE_WEBHOOK_SECRET] in environment           │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│              Version Control (Git)                          │
│   YAML file committed ✓                                     │
│   ENV variable NOT committed (in .gitignore) ✓              │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│           Scan for Providers (User Action)                  │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│        ProviderSync Resolves ENV Reference                  │
│   "ENV[STRIPE_WEBHOOK_SECRET]" → ENV value                  │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│       ActiveRecord Encryption (Save to DB)                  │
│   Plain: "whsec_abc123"                                     │
│   Encrypted: "AES-256-GCM encrypted blob"                   │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│            Database Storage                                 │
│   signing_secret column: encrypted_value                    │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│       Webhook Request (Runtime)                             │
│   Provider.signing_secret (auto-decrypts) → verify signature│
└─────────────────────────────────────────────────────────────┘

✓ Secrets never in source code
✓ Secrets encrypted in database
✓ Secrets resolved from environment
```

## Comparison: Before vs After

### Manual Provider Creation (Before)

```
Developer Workflow:
1. Open browser → /captain_hook/admin/providers
2. Click "Add Provider"
3. Fill form:
   - Name: stripe
   - Display Name: Stripe
   - Signing Secret: whsec_... (visible in UI!)
   - Adapter Class: CaptainHook::Adapters::Stripe
   - Timestamp Tolerance: 300
   - Rate Limit: 100
   - Rate Period: 60
4. Click "Create"
5. Repeat for each provider
6. Configuration lives in database only
7. Not version controlled
8. Different across environments

Cons:
❌ Manual and repetitive
❌ Secrets visible in UI
❌ Not version controlled
❌ Environment-specific configuration scattered
❌ No gem support
```

### Automated Discovery (After)

```
Developer Workflow:
1. Create file: captain_hook/providers/stripe.yml
2. Add content:
   name: stripe
   signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
   adapter_class: CaptainHook::Adapters::Stripe
   ...
3. Set ENV: STRIPE_WEBHOOK_SECRET=whsec_...
4. Commit YAML file (git add, git commit)
5. Deploy or run locally
6. Open browser → /captain_hook/admin/providers
7. Click "Scan for Providers"
8. Done! All providers created

Pros:
✅ Automated and fast
✅ Secrets in environment variables
✅ Version controlled
✅ Consistent across environments
✅ Gem support built-in
✅ One-click creation
```

## Result Table

### Provider Index After Scan

```
┌────────────────────────────────────────────────────────────────────────┐
│  Webhook Providers                      [Scan for Providers]          │
├────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │ ✓ Scan completed! Created 3 providers                         │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │ Name      │ Display   │ Adapter │ Status │ Events │ Actions    │ │
│  ├───────────┼───────────┼─────────┼────────┼────────┼────────────┤ │
│  │ stripe    │ Stripe    │ Stripe  │ Active │    42  │ View Edit  │ │
│  │ square    │ Square    │ Square  │ Active │    18  │ View Edit  │ │
│  │ paypal    │ PayPal    │ PayPal  │ Active │     7  │ View Edit  │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  About Providers                                                       │
│  • Providers are discovered from YAML files                           │
│  • Configuration in captain_hook/providers/ directory                 │
│  • Signing secrets from ENV variables                                 │
│  • Click "Scan for Providers" to discover new ones                    │
│                                                                         │
└────────────────────────────────────────────────────────────────────────┘
```

## Summary

The Provider Discovery System provides:
- 🎯 **One-Click Setup**: "Scan for Providers" button
- 📁 **File-Based Config**: YAML files in captain_hook/providers/
- 🔐 **Secure**: ENV variables for secrets, encryption at rest
- 📦 **Version Controlled**: Configuration is part of codebase
- 🔄 **Consistent**: Same setup across all environments
- 🚀 **Scalable**: Works with gems, not just main app
