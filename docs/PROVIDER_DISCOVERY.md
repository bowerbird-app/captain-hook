# Provider Discovery

## Overview

Provider Discovery is CaptainHook's automatic system for finding and loading webhook provider configurations from YAML files. During application boot, CaptainHook scans your Rails application and installed gems for `captain_hook/<provider>/` directories, loads their configurations, and syncs them to the database.

This document explains how provider discovery works, how to set up providers, and how to troubleshoot discovery issues.

## Key Concepts

- **Provider**: A webhook source (e.g., Stripe, GitHub, custom API)
- **Provider Discovery**: Automatic scanning of filesystem for provider YAML files
- **Provider Registry**: In-memory cache of discovered provider configurations
- **Provider Sync**: Process that syncs discovered providers to the database
- **Provider Config**: Combined configuration from YAML, database, and global settings
- **Discovery Priority**: Application providers override gem providers

## How Provider Discovery Works

### Discovery Process

1. **Application Boot**: CaptainHook's engine initializer triggers discovery
2. **Filesystem Scan**: Searches for `captain_hook/<provider>/<provider>.yml` files
3. **YAML Loading**: Parses YAML files and validates structure
4. **Verifier Loading**: Loads custom verifier Ruby files (if present)
5. **Action Loading**: Loads action files from `actions/` directory
6. **Deduplication**: Removes duplicates (application overrides gems)
7. **Database Sync**: Creates or updates Provider records
8. **Configuration Resolution**: Merges YAML, database, and global configs

### Discovery Flow

```
Application Boot
    ↓
Engine Initializer
    ↓
ProviderDiscovery.new.call
    ↓
┌─────────────────────────────────────┐
│ 1. Scan Rails.root/captain_hook/    │
│    - Look for */stripe.yml          │
│    - Load stripe.rb (verifier)      │
│    - Load actions/*.rb files        │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 2. Scan All Loaded Gems             │
│    - Check each gem for             │
│      captain_hook/ directory        │
│    - Load provider YAMLs            │
│    - Load verifiers and actions     │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 3. Deduplicate Providers            │
│    - Remove duplicate names         │
│    - Application > Gems             │
│    - Warn about duplicates          │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 4. Sync to Database (ProviderSync)  │
│    - Create new Provider records    │
│    - Update existing records        │
│    - Generate unique tokens         │
│    - Preserve manual DB changes     │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ 5. Build Provider Configs           │
│    - Merge YAML + DB + global       │
│    - Resolve ENV variables          │
│    - Apply configuration hierarchy  │
└─────────────────────────────────────┘
    ↓
Providers Ready for Webhooks
```

## Provider File Structure

### Required Directory Structure

```
captain_hook/
└── <provider_name>/
    ├── <provider_name>.yml       # Required: Provider configuration
    ├── <provider_name>.rb         # Optional: Custom verifier
    └── actions/                   # Optional: Action classes
        ├── action1.rb
        ├── action2.rb
        └── subdirectory/
            └── action3.rb
```

### Example: Stripe Provider

```
captain_hook/
└── stripe/
    ├── stripe.yml                 # Provider configuration
    ├── stripe.rb                  # Custom verifier (optional if using built-in)
    └── actions/
        ├── payment_intent_succeeded_action.rb
        └── charge_refunded_action.rb
```

### Naming Rules

1. **Directory name**: Lowercase with underscores (e.g., `stripe`, `github`, `custom_api`)
2. **YAML file**: Must match directory name exactly (e.g., `stripe/stripe.yml`)
3. **Verifier file**: Should match directory name (e.g., `stripe/stripe.rb`)
4. **Actions directory**: Must be named exactly `actions/` (case-sensitive)

## Provider Configuration (YAML)

### Basic Configuration

Create `captain_hook/<provider>/<provider>.yml`:

```yaml
# captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe Payments
description: Receive and process Stripe webhook events
verifier_file: stripe.rb

# Security settings
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300
max_payload_size_bytes: 1048576

# Database-synced fields (optional)
active: true
rate_limit_requests: 100
rate_limit_period: 60
```

### Configuration Fields

| Field | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `name` | **Yes** | String | N/A | Provider identifier (must match directory) |
| `display_name` | No | String | Titleized name | Human-readable name for admin UI |
| `description` | No | String | `nil` | Brief description of the provider |
| `verifier_file` | **Yes** | String | N/A | Name of verifier Ruby file |
| `signing_secret` | **Yes** | String | N/A | Webhook signing secret (use ENV pattern) |
| `timestamp_tolerance_seconds` | No | Integer | `300` | Clock skew tolerance in seconds |
| `max_payload_size_bytes` | No | Integer | `1048576` | Maximum payload size (1MB) |
| `active` | No | Boolean | `true` | Whether provider is active |
| `rate_limit_requests` | No | Integer | `100` | Requests allowed per period |
| `rate_limit_period` | No | Integer | `60` | Time period for rate limit (seconds) |

### Environment Variable Pattern

**Always** reference secrets as environment variables using the `ENV[VARIABLE_NAME]` pattern:

```yaml
# ✅ CORRECT: References environment variable
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]

# ❌ WRONG: Hardcoded secret (security risk!)
signing_secret: whsec_abc123...

# ❌ WRONG: Ruby code won't be evaluated
signing_secret: <%= ENV['STRIPE_WEBHOOK_SECRET'] %>
```

**How it works**:
1. YAML file stores: `ENV[STRIPE_WEBHOOK_SECRET]`
2. ProviderConfig detects pattern: `/\AENV\[(\w+)\]\z/`
3. At runtime, resolves to: `ENV.fetch('STRIPE_WEBHOOK_SECRET', nil)`

### Database-Synced Fields

The `active`, `rate_limit_requests`, and `rate_limit_period` fields have special behavior:

**For New Providers**:
- If specified in YAML: Used as initial value
- If omitted from YAML: Uses defaults (`active: true`, `rate_limit_requests: 100`, `rate_limit_period: 60`)

**For Existing Providers**:
- If specified in YAML: **Overwrites** database value on every restart
- If omitted from YAML: **Preserves** database value (manual changes persist)

**Best Practice**:
```yaml
# For production: Omit these fields to allow runtime changes
name: stripe
display_name: Stripe
verifier_file: stripe.rb
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
# active: true               # Omit to preserve DB value
# rate_limit_requests: 100   # Omit to preserve DB value
# rate_limit_period: 60      # Omit to preserve DB value
```

## Discovery Locations

### 1. Application Directory (Highest Priority)

```
Rails.root/captain_hook/<provider>/<provider>.yml
```

**Example**: `/app/captain_hook/stripe/stripe.yml`

- Checked first during discovery
- Always takes precedence over gem providers
- Best for app-specific integrations

### 2. Loaded Gems (Lower Priority)

```
Gem.loaded_specs[*].full_gem_path/captain_hook/<provider>/<provider>.yml
```

**Example**: `/gems/payment_gem-1.0.0/captain_hook/stripe/stripe.yml`

- Scanned after application directory
- Provides reusable webhook integrations
- Overridden by application providers

### Discovery Order

```ruby
# 1. Application (highest priority)
Rails.root/captain_hook/stripe/stripe.yml

# 2. Gems (in load order)
gem_a/captain_hook/stripe/stripe.yml
gem_b/captain_hook/stripe/stripe.yml

# Result: Application wins, gem_a and gem_b ignored for "stripe"
```

## Provider Deduplication

### How Deduplication Works

When multiple sources provide the same provider name:

1. **Collect All Sources**: Discovery finds all definitions
2. **Priority Resolution**: Application > Gem A > Gem B
3. **Warning Issued**: Logs duplicate provider warning
4. **Single Provider Synced**: Only highest-priority definition used

### Example Scenario

**Application defines**:
```yaml
# Rails.root/captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe (Application)
signing_secret: ENV[APP_STRIPE_SECRET]
```

**Gem defines**:
```yaml
# payment_gem/captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe (via PaymentGem)
signing_secret: ENV[GEM_STRIPE_SECRET]
```

**Result**:
- Application version is used
- Gem version is ignored
- Warning logged:

```
⚠️  DUPLICATE PROVIDER DETECTED: 'stripe'
   Found in multiple sources: application, gem:payment_gem
   
   If you're using the SAME webhook URL:
   → Just register your actions for the existing 'stripe' provider
   → Remove the duplicate provider configuration
   
   If you need DIFFERENT webhook URLs (multi-tenant):
   → Rename one provider (e.g., 'stripe_primary' and 'stripe_secondary')
   → Each provider gets its own webhook endpoint and secret
```

### Handling Duplicates

**Option 1: Same Webhook URL**

If you want one Stripe webhook endpoint:
```yaml
# Application: Use existing provider
name: stripe
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]

# Gem: Remove provider YAML, just provide actions in gem
# (Actions will register to existing 'stripe' provider)
```

**Option 2: Multiple Webhook URLs (Multi-Tenant)**

If you need separate endpoints:
```yaml
# Application: Primary account
name: stripe_primary
display_name: Stripe (Primary Account)
signing_secret: ENV[STRIPE_PRIMARY_SECRET]

# Gem: Secondary account
name: stripe_secondary
display_name: Stripe (Secondary Account)
signing_secret: ENV[STRIPE_SECONDARY_SECRET]
```

Each gets a unique webhook URL:
- `https://app.com/captain_hook/stripe_primary/:token`
- `https://app.com/captain_hook/stripe_secondary/:token`

## Configuration Hierarchy

CaptainHook uses a three-tier configuration system:

### Configuration Priority (Highest to Lowest)

1. **`config/captain_hook.yml` Provider Override** (highest)
   - Per-provider overrides: `providers.stripe.timestamp_tolerance_seconds`
   
2. **Provider YAML File**
   - Provider-specific file: `captain_hook/stripe/stripe.yml`
   
3. **`config/captain_hook.yml` Global Defaults** (lowest)
   - Global defaults: `defaults.timestamp_tolerance_seconds`

### Example Configuration Resolution

**Provider YAML**:
```yaml
# captain_hook/stripe/stripe.yml
name: stripe
timestamp_tolerance_seconds: 300
max_payload_size_bytes: 1048576
```

**Global Config**:
```yaml
# config/captain_hook.yml
defaults:
  timestamp_tolerance_seconds: 600
  max_payload_size_bytes: 2097152

providers:
  stripe:
    timestamp_tolerance_seconds: 900
```

**Resolved Configuration**:
- `timestamp_tolerance_seconds`: **900** (provider override wins)
- `max_payload_size_bytes`: **1048576** (provider YAML value used)

### Fields Affected by Hierarchy

Only these fields use the configuration hierarchy:
- `timestamp_tolerance_seconds`
- `max_payload_size_bytes`

All other fields come solely from the provider YAML file.

## Database Synchronization

### What Gets Synced

**To Database**:
- `name` - Provider identifier
- `token` - Auto-generated unique token (if not exists)
- `active` - Active/inactive status
- `rate_limit_requests` - Request limit
- `rate_limit_period` - Time period for limit

**NOT Synced to Database**:
- `display_name` - Only in YAML
- `description` - Only in YAML
- `verifier_file` - Only in YAML
- `signing_secret` - Only in YAML (security)
- `timestamp_tolerance_seconds` - Only in YAML
- `max_payload_size_bytes` - Only in YAML

### Sync Behavior

**New Provider**:
```ruby
# Before: No database record
# YAML: name: stripe, active: true

# After sync:
Provider.create!(
  name: "stripe",
  token: "abc123...",  # Auto-generated
  active: true,
  rate_limit_requests: 100,
  rate_limit_period: 60
)
```

**Existing Provider**:
```ruby
# Database: active: false (manually changed)
# YAML: active not specified

# After sync:
# active: false (preserved!)

# YAML: active: true

# After sync:
# active: true (overwritten by YAML)
```

### Manual Database Changes

To preserve manual changes:

**Option 1: Omit from YAML** (recommended)
```yaml
name: stripe
# active: true  # Omit to preserve DB value
```

**Option 2: Manage via Admin UI**
```
Navigate to /captain_hook/admin/providers
Edit provider settings
Changes persist across restarts (if not in YAML)
```

**Option 3: Rails Console**
```ruby
provider = CaptainHook::Provider.find_by(name: "stripe")
provider.update!(active: false)
# Persists if YAML doesn't specify 'active'
```

## Provider Configuration Object

### ProviderConfig Structure

After discovery and sync, providers are represented as `ProviderConfig` objects:

```ruby
config = CaptainHook.configuration.provider("stripe")

# Registry fields (from YAML)
config.name                          # => "stripe"
config.display_name                  # => "Stripe Payments"
config.description                   # => "Stripe webhook integration"
config.verifier_file                 # => "stripe.rb"
config.verifier_class                # => "CaptainHook::Verifiers::Stripe"
config.signing_secret                # => "whsec_..." (resolved from ENV)
config.timestamp_tolerance_seconds   # => 300
config.max_payload_size_bytes        # => 1048576
config.source                        # => "application" or "gem:gem_name"
config.source_file                   # => "/app/captain_hook/stripe/stripe.yml"

# Database fields
config.token                         # => "abc123..." (from DB)
config.active                        # => true (from DB)
config.rate_limit_requests           # => 100 (from DB)
config.rate_limit_period             # => 60 (from DB)

# Helper methods
config.active?                       # => true
config.rate_limiting_enabled?        # => true
config.timestamp_validation_enabled? # => true
config.payload_size_limit_enabled?   # => true
config.verifier                      # => #<CaptainHook::Verifiers::Stripe>
```

### Accessing Provider Configs

**Via Configuration API**:
```ruby
# Single provider
config = CaptainHook.configuration.provider("stripe")

# Check if exists
if config
  puts config.webhook_url
end
```

**Via Database Model**:
```ruby
# Get database record
provider = CaptainHook::Provider.find_by(name: "stripe")

# Get combined config (DB + registry)
config = CaptainHook.configuration.provider(provider.name)
```

## Triggering Manual Discovery

### Rescan Providers

Force a full re-scan and database sync:

```ruby
# In Rails console or rake task
CaptainHook::Engine.sync_providers
```

**This will**:
- Scan application and gems
- Load all provider YAMLs
- Sync to database
- Log results

**Output**:
```
🔍 CaptainHook: Found 3 provider(s)
✅ Created provider: github (from application)
🔄 Updated provider: stripe (from application)
⏭️  Skipped existing provider: custom_api (update_existing=false)
✅ CaptainHook: Synced providers - Created: 1, Updated: 1, Skipped: 1
```

### Low-Level Discovery (No Sync)

For inspection without database changes:

```ruby
# Discover without syncing
discovery = CaptainHook::Services::ProviderDiscovery.new
providers = discovery.call

providers.each do |definition|
  puts "Found: #{definition['name']} from #{definition['source']}"
  puts "  File: #{definition['source_file']}"
  puts "  Display: #{definition['display_name']}"
  puts "  Verifier: #{definition['verifier_file']}"
end

# Output:
# Found: stripe from application
#   File: /app/captain_hook/stripe/stripe.yml
#   Display: Stripe Payments
#   Verifier: stripe.rb
```

### When to Trigger Manual Discovery

- After adding new provider YAML files
- After modifying provider configurations
- After installing gems with providers
- When troubleshooting missing providers
- During deployment/initialization scripts

## Verifier Loading

### Automatic Verifier Loading

During discovery, CaptainHook automatically loads verifier files:

```ruby
# If captain_hook/stripe/stripe.rb exists:
# 1. File is loaded via `load verifier_file`
# 2. Class is extracted (e.g., StripeVerifier)
# 3. Class is cached for later use
```

### Built-in Verifiers

CaptainHook includes built-in verifiers:

```yaml
# Use built-in Stripe verifier
verifier_file: stripe.rb
# → Uses CaptainHook::Verifiers::Stripe
```

**Available built-in verifiers**:
- `stripe.rb` → `CaptainHook::Verifiers::Stripe`

### Custom Verifiers

Create custom verifiers in `captain_hook/<provider>/<provider>.rb`:

```ruby
# captain_hook/custom_api/custom_api.rb
class CustomApiVerifier
  include CaptainHook::VerifierHelpers

  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, "X-Custom-Signature")
    expected = generate_hmac(provider_config.signing_secret, payload)
    secure_compare(signature, expected)
  end
end
```

```yaml
# captain_hook/custom_api/custom_api.yml
name: custom_api
verifier_file: custom_api.rb
signing_secret: ENV[CUSTOM_API_SECRET]
```

### Verifier Class Detection

CaptainHook detects verifier classes by:

1. **File name convention**: `stripe.rb` → `StripeVerifier`
2. **Module inclusion**: Classes including `CaptainHook::VerifierHelpers`
3. **Name suffix**: Classes ending in `Verifier`

## Action Loading

### Automatic Action Discovery

Actions in `captain_hook/<provider>/actions/` are automatically loaded:

```
captain_hook/stripe/actions/
├── payment_intent_action.rb        # Loaded
├── charge_action.rb                # Loaded
└── subscriptions/
    └── subscription_action.rb       # Loaded (subdirectories supported)
```

**During discovery**:
1. All `.rb` files in `actions/` are loaded via `load`
2. Action classes are discovered by ActionDiscovery service
3. Actions are synced to database via ActionSync service

### Action-Provider Relationship

Actions must be namespaced with the provider:

```ruby
# captain_hook/stripe/actions/payment_action.rb
module Stripe  # Must match provider name
  class PaymentAction
    def self.details
      { event_type: "payment.succeeded" }
    end

    def webhook_action(event:, payload:, metadata: {})
      # Process webhook
    end
  end
end
```

See [Action Discovery](ACTION_DISCOVERY.md) for complete action documentation.

## Admin UI

### Viewing Providers

Navigate to `/captain_hook/admin/providers` to see:

- All discovered providers
- Provider status (active/inactive)
- Webhook URLs with tokens
- Configuration sources (application vs gems)
- Recent webhook events
- Associated actions

### Provider Details Page

Click a provider to see:

**Registry Configuration**:
- Display name and description
- Verifier file and class
- Security settings (timestamp tolerance, payload size)
- Source file location

**Database Configuration**:
- Active status (toggle)
- Rate limiting settings
- Unique token
- Webhook URL

**Configuration Hierarchy**:
- Shows which values come from YAML, global config, or overrides
- Displays resolved values vs file values
- Highlights environment variable status

**Associated Data**:
- Recent webhook events
- Registered actions
- Event statistics

### Managing Providers

**Activate/Deactivate**:
```
Edit provider → Toggle "Active" checkbox → Save
```

**Update Rate Limits**:
```
Edit provider → Change rate_limit_requests/period → Save
```

**View Webhook URL**:
```
Provider detail page → Copy webhook URL
```

**Regenerate Token** (advanced):
```ruby
# Rails console
provider = CaptainHook::Provider.find_by(name: "stripe")
provider.update!(token: SecureRandom.urlsafe_base64(32))
# Update webhook URL in provider dashboard!
```

## Complete Setup Example

### Step-by-Step: Adding a New Provider

**1. Create directory structure**:
```bash
mkdir -p captain_hook/github
```

**2. Create provider YAML**:
```yaml
# captain_hook/github/github.yml
name: github
display_name: GitHub Webhooks
description: Receive and process GitHub repository events
verifier_file: github.rb

signing_secret: ENV[GITHUB_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300
max_payload_size_bytes: 5242880  # 5MB for GitHub
```

**3. Create custom verifier**:
```ruby
# captain_hook/github/github.rb
class GithubVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Hub-Signature-256"

  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, SIGNATURE_HEADER)
    return false if signature.blank?

    # GitHub format: "sha256=abc123..."
    signature = signature.sub(/^sha256=/, "")
    
    expected = generate_hmac(provider_config.signing_secret, payload)
    secure_compare(signature, expected)
  end
end
```

**4. Create actions** (optional):
```ruby
# captain_hook/github/actions/push_action.rb
module Github
  class PushAction
    def self.details
      {
        event_type: "push",
        description: "Process GitHub push events",
        priority: 100,
        async: true
      }
    end

    def webhook_action(event:, payload:, metadata: {})
      repo = payload["repository"]["full_name"]
      branch = payload["ref"].sub("refs/heads/", "")
      commits = payload["commits"].length
      
      Rails.logger.info "GitHub: #{commits} commit(s) pushed to #{repo}:#{branch}"
      
      # Your business logic here
    end
  end
end
```

**5. Set environment variable**:
```bash
# .env
GITHUB_WEBHOOK_SECRET=your_github_secret
```

**6. Restart application**:
```bash
rails restart
```

**7. Verify discovery**:
```
Navigate to /captain_hook/admin/providers
Should see "GitHub Webhooks" listed
Copy webhook URL
```

**8. Configure GitHub**:
```
In GitHub repo settings:
→ Webhooks → Add webhook
→ Payload URL: https://your-app.com/captain_hook/github/:token
→ Secret: your_github_secret
→ Events: Select events
→ Save
```

**Done!** Webhooks will now be received and processed.

## Troubleshooting

### Provider Not Discovered

**Problem**: Provider YAML exists but doesn't appear in admin UI

**Diagnosis**:
```ruby
# Check if file is found
discovery = CaptainHook::Services::ProviderDiscovery.new
providers = discovery.call
providers.map { |p| p["name"] }
# Should include your provider name
```

**Common causes**:
1. **Wrong directory structure**: Must be `captain_hook/<provider>/<provider>.yml`
2. **File name mismatch**: YAML file must match directory name
3. **Invalid YAML syntax**: Check for parsing errors in logs
4. **Missing required fields**: `name` and `verifier_file` are required
5. **Application not restarted**: Discovery runs at boot

**Solutions**:
```bash
# 1. Verify file structure
ls -la captain_hook/stripe/
# Should show: stripe.yml

# 2. Validate YAML syntax
ruby -e "require 'yaml'; puts YAML.load_file('captain_hook/stripe/stripe.yml')"

# 3. Check Rails logs for errors
tail -f log/development.log | grep CaptainHook

# 4. Trigger manual discovery
rails console
> CaptainHook::Engine.sync_providers

# 5. Restart application
rails restart
```

### Provider Not Syncing to Database

**Problem**: Provider appears in discovery but not in database

**Diagnosis**:
```ruby
# Check discovery
discovery = CaptainHook::Services::ProviderDiscovery.new
providers = discovery.call
provider = providers.find { |p| p["name"] == "stripe" }
# Should return hash

# Check database
CaptainHook::Provider.find_by(name: "stripe")
# Should return record
```

**Common causes**:
1. **Validation errors**: Check logs for error messages
2. **Invalid provider name**: Must be lowercase, numbers, underscores only
3. **Database migration not run**: Run `rails db:migrate`

**Solutions**:
```ruby
# Manually sync with error details
definitions = CaptainHook::Services::ProviderDiscovery.new.call
sync = CaptainHook::Services::ProviderSync.new(definitions)
results = sync.call

puts "Created: #{results[:created].map(&:name)}"
puts "Errors: #{results[:errors]}"
```

### Environment Variable Not Resolved

**Problem**: Signature verification fails with "missing signing secret"

**Diagnosis**:
```ruby
config = CaptainHook.configuration.provider("stripe")
config.signing_secret
# Should return secret value, not "ENV[...]"
```

**Common causes**:
1. **Environment variable not set**: Secret not in `.env` or environment
2. **Wrong variable name**: Typo in YAML or environment
3. **Pattern mismatch**: Not using exact `ENV[VARIABLE_NAME]` format

**Solutions**:
```bash
# 1. Check environment variable
echo $STRIPE_WEBHOOK_SECRET
# Should output secret

# 2. Verify .env file (if using dotenv-rails)
cat .env | grep STRIPE_WEBHOOK_SECRET

# 3. Test in Rails console
ENV['STRIPE_WEBHOOK_SECRET']
# Should return secret

# 4. Verify YAML pattern
cat captain_hook/stripe/stripe.yml | grep signing_secret
# Should be: signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

### Duplicate Provider Warnings

**Problem**: Getting warnings about duplicate providers

**Warning message**:
```
⚠️  DUPLICATE PROVIDER DETECTED: 'stripe'
   Found in multiple sources: application, gem:payment_gem
```

**Solutions**:

**If using same webhook URL** (recommended):
```bash
# Remove duplicate YAML file from application or gem
# Keep actions in both places if needed
# They'll register to the single provider
rm captain_hook/stripe/stripe.yml  # Remove from app
# Keep gem's stripe.yml
```

**If need separate webhook URLs** (multi-tenant):
```yaml
# Rename one provider
name: stripe_primary  # In application
name: stripe_gem      # In gem
```

### Verifier Not Loading

**Problem**: "Verifier not found" errors

**Diagnosis**:
```ruby
config = CaptainHook.configuration.provider("stripe")
config.verifier
# Should return verifier instance
```

**Common causes**:
1. **Verifier file doesn't exist**: Missing `.rb` file
2. **Class name mismatch**: Class doesn't follow convention
3. **Syntax errors**: Ruby file has errors
4. **Not including VerifierHelpers**: Class missing module include

**Solutions**:
```ruby
# 1. Check file exists
File.exist?(Rails.root.join("captain_hook/stripe/stripe.rb"))

# 2. Verify class definition
# File should define: StripeVerifier or *Verifier class

# 3. Test loading manually
load Rails.root.join("captain_hook/stripe/stripe.rb")
StripeVerifier.new
# Should instantiate

# 4. Check for syntax errors
ruby -c captain_hook/stripe/stripe.rb
```

### Actions Not Discovered

See [Action Discovery Troubleshooting](ACTION_DISCOVERY.md#troubleshooting) for action-specific issues.

## Best Practices

### 1. Use Environment Variables for Secrets

```yaml
# ✅ GOOD: Environment variable
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]

# ❌ BAD: Hardcoded secret
signing_secret: whsec_abc123...
```

### 2. Omit Database Fields for Production

```yaml
# ✅ GOOD: Omit to allow runtime changes
name: stripe
display_name: Stripe
verifier_file: stripe.rb
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]

# ❌ BAD: Hardcoded values overwrite DB changes
name: stripe
active: true              # Will overwrite manual deactivation
rate_limit_requests: 100  # Will overwrite admin UI changes
```

### 3. Use Descriptive Display Names

```yaml
# ✅ GOOD: Clear, descriptive
display_name: Stripe Payments (Production)
description: Live Stripe payment webhooks

# ❌ BAD: Generic or unclear
display_name: Stripe
description: Webhooks
```

### 4. Set Appropriate Payload Limits

```yaml
# ✅ GOOD: Based on provider
max_payload_size_bytes: 5242880  # 5MB for GitHub
max_payload_size_bytes: 1048576  # 1MB for Stripe

# ❌ BAD: Too restrictive or too permissive
max_payload_size_bytes: 1024      # Too small
max_payload_size_bytes: 104857600 # 100MB, too large
```

### 5. Version Your Provider Configs

```yaml
# Add comments for tracking
# Version: 1.2.0
# Last updated: 2026-01-27
# Updated by: Your Name
name: stripe
display_name: Stripe Payments
```

### 6. Document Environment Variables

```markdown
# README.md or .env.example

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `STRIPE_WEBHOOK_SECRET` | Yes | Stripe webhook signing secret (from Stripe Dashboard) |
| `GITHUB_WEBHOOK_SECRET` | No | GitHub webhook secret (if using GitHub integration) |
```

### 7. Test Discovery After Changes

```ruby
# After changing YAML files:
# 1. Trigger discovery
CaptainHook::Engine.sync_providers

# 2. Verify provider exists
CaptainHook::Provider.find_by(name: "stripe")

# 3. Check configuration
config = CaptainHook.configuration.provider("stripe")
config.signing_secret  # Should not be nil
```

### 8. Monitor Discovery Logs

```ruby
# Set log level to debug for detailed discovery info
config.log_level = :debug

# Discovery will log:
# ✅ Created provider: stripe (from application)
# 🔄 Updated provider: github (from gem:github_integration)
# ⚠️  Duplicate provider: stripe (application vs gem)
```

## Advanced Topics

### Multi-Tenant Provider Setup

Support multiple accounts of the same provider:

```yaml
# captain_hook/stripe_primary/stripe_primary.yml
name: stripe_primary
display_name: Stripe (Primary Account)
verifier_file: stripe.rb  # Uses built-in Stripe verifier
signing_secret: ENV[STRIPE_PRIMARY_SECRET]

# captain_hook/stripe_secondary/stripe_secondary.yml
name: stripe_secondary
display_name: Stripe (Secondary Account)
verifier_file: stripe.rb  # Reuses built-in verifier
signing_secret: ENV[STRIPE_SECONDARY_SECRET]
```

Each gets unique webhook URLs:
- `https://app.com/captain_hook/stripe_primary/:token`
- `https://app.com/captain_hook/stripe_secondary/:token`

### Dynamic Provider Registration

Programmatically register providers (rare, typically use YAML):

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  config.register_provider(
    "custom_api",
    display_name: "Custom API",
    verifier_class: "CustomApiVerifier",
    signing_secret: ENV["CUSTOM_API_SECRET"]
  )
end
```

### Conditional Provider Loading

Load providers based on environment:

```yaml
# captain_hook/stripe/stripe.yml
name: stripe
display_name: <%= Rails.env.production? ? "Stripe (Production)" : "Stripe (Staging)" %>
signing_secret: ENV[<%= Rails.env.production? ? "STRIPE_PROD_SECRET" : "STRIPE_DEV_SECRET" %>]
```

**Note**: ERB is not supported in YAML files. Use environment-specific configs instead:

```
captain_hook/
├── production/
│   └── stripe/
│       └── stripe.yml
└── development/
    └── stripe/
        └── stripe.yml
```

## See Also

- [Action Discovery](ACTION_DISCOVERY.md) - How actions are discovered
- [Verifier Helpers](VERIFIER_HELPERS.md) - Creating custom verifiers
- [GEM_WEBHOOK_SETUP.md](GEM_WEBHOOK_SETUP.md) - Creating gems with providers
- [TECHNICAL_PROCESS.md](../TECHNICAL_PROCESS.md) - Complete technical documentation
