# Provider Registry Refactor - Migration Guide

This guide explains the changes and migration steps for the provider registry refactor.

## What Changed

### Architecture Changes

**Before:**
- Provider configuration stored in database (display_name, description, signing_secret, verifier_class, etc.)
- All settings managed through database records
- Signing secrets encrypted in database

**After:**
- **Registry (YAML files)** = Source of truth for provider configuration
- **Database** = Minimal runtime data (token, active status, rate limits)
- **Global config** = Application-wide defaults (max_payload_size_bytes, timestamp_tolerance_seconds)
- **ENV variables** = Signing secret storage

### Database Schema Changes

**Removed columns from `captain_hook_providers` table:**
- `display_name` → Now from YAML
- `description` → Now from YAML
- `signing_secret` → Now from ENV via YAML reference
- `verifier_class` → Now from YAML
- `verifier_file` → Now from YAML
- `timestamp_tolerance_seconds` → Now from global config (can override in YAML)
- `max_payload_size_bytes` → Now from global config (can override in YAML)
- `metadata` → Removed

**Retained columns:**
- `name` (unique identifier)
- `token` (webhook URL token)
- `active` (enable/disable provider)
- `rate_limit_requests` (rate limit setting)
- `rate_limit_period` (rate limit period)
- `created_at`, `updated_at` (timestamps)

## Migration Steps

### 1. Run the Migration

```bash
# In your host application
rails captain_hook:install:migrations
rails db:migrate
```

This will run migration `20260120015225_simplify_providers_table.rb` which removes the columns from the database.

### 2. Create Global Config File (Optional)

Create `config/captain_hook.yml` in your host application:

```yaml
# config/captain_hook.yml
defaults:
  max_payload_size_bytes: 1048576      # 1MB default
  timestamp_tolerance_seconds: 300     # 5 minutes default

# Per-provider overrides (optional)
providers:
  # stripe:
  #   max_payload_size_bytes: 2097152   # 2MB for Stripe
```

**Note:** If you don't create this file, built-in defaults will be used.

### 3. Set Environment Variables for Signing Secrets

Signing secrets are now referenced from environment variables instead of being stored in the database.

**Update your `.env` file or production environment:**

```bash
# Example
STRIPE_WEBHOOK_SECRET=whsec_xxxxx
SQUARE_WEBHOOK_SECRET=your_square_secret
PAYPAL_WEBHOOK_SECRET=your_paypal_secret
```

**Your provider YAML files should reference these:**

```yaml
# captain_hook/stripe/stripe.yml
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

### 4. Verify Provider YAML Files

Your existing provider YAML files should already have the correct structure. If you were setting `timestamp_tolerance_seconds` or `max_payload_size_bytes` in YAML, they'll still work (provider-specific values override global config).

**Example provider YAML:**

```yaml
# captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe
description: Stripe payment webhooks
verifier_file: stripe.rb
active: true

# Signing secret via ENV (required)
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]

# Rate limiting (optional - can also be set via admin UI)
rate_limit_requests: 100
rate_limit_period: 60

# These now come from global config by default
# But can be overridden here if needed
# timestamp_tolerance_seconds: 600
# max_payload_size_bytes: 2097152
```

### 5. Data Migration Considerations

**Important:** The migration will remove data from the following columns:
- `display_name` - Now comes from YAML
- `description` - Now comes from YAML
- `signing_secret` - Now comes from ENV

**Before running the migration**, ensure:
1. Your provider YAML files have `display_name` and `description` set
2. Your signing secrets are in environment variables
3. Your YAML files reference signing secrets via `ENV[VARIABLE_NAME]`

**If you had signing secrets in the database:**
1. Export them before migration: `rails runner "CaptainHook::Provider.all.each { |p| puts \"#{p.name}: #{p.signing_secret}\" }"`
2. Add them to your environment variables
3. Update your YAML files to reference them

## Configuration Priority

The new architecture has a clear priority order for settings:

### For `max_payload_size_bytes` and `timestamp_tolerance_seconds`:

1. **Provider YAML file** (highest priority)
2. **Global config per-provider override** (`config/captain_hook.yml` under `providers:`)
3. **Global config default** (`config/captain_hook.yml` under `defaults:`)
4. **Built-in default** (1MB for payload, 300s for timestamp)

### For `rate_limit_requests` and `rate_limit_period`:

1. **Database value** (set via admin UI or provider YAML sync)
2. **Provider YAML file** (synced to database on boot)
3. **Built-in defaults** (100 requests per 60 seconds)

### For provider metadata (`display_name`, `description`, `verifier_class`, `verifier_file`):

1. **Provider YAML file** (only source)
2. **Fallback defaults** (display_name = titleized name, verifier_class = Base)

### For `signing_secret`:

1. **Environment variable** (referenced via `ENV[VARIABLE_NAME]` in YAML)

## Testing

After migration, verify your setup:

```bash
# Check that providers are correctly configured
rails console
> CaptainHook::Provider.all.each do |p|
>   config = CaptainHook.configuration.provider(p.name)
>   puts "#{p.name}: #{config.display_name} - #{config.verifier_class}"
>   puts "  Signing secret: #{config.resolve_signing_secret.present? ? 'SET' : 'NOT SET'}"
>   puts "  Max payload: #{config.max_payload_size_bytes}"
>   puts "  Timestamp tolerance: #{config.timestamp_tolerance_seconds}"
> end
```

## Rollback

If you need to rollback the migration:

```bash
rails db:rollback
```

This will restore the removed columns with their default values. You'll need to re-populate the data manually.

## Support

For issues or questions, see:
- [Main README](../README.md)
