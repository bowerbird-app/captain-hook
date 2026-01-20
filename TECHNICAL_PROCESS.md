# CaptainHook Technical Documentation - Part 1: Providers & Verifiers

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Provider Setup & Configuration](#provider-setup--configuration)
4. [File Structure](#file-structure)
5. [Provider Discovery Process](#provider-discovery-process)
6. [Webhook Request Flow](#webhook-request-flow)
7. [Signature Verification](#signature-verification)
8. [Signing Secrets Management](#signing-secrets-management)
9. [Built-in Verifiers](#built-in-verifiers)
10. [Custom Verifiers](#custom-verifiers)
11. [Examples](#examples)

---

## Overview

CaptainHook is a Rails engine for receiving and processing webhooks from external providers. It uses a **registry-based architecture** where provider configurations are stored in YAML files and automatically discovered at application boot.

### Key Concepts

- **Provider**: An external service that sends webhooks (e.g., Stripe, PayPal, Square)
- **Verifier**: A Ruby class that handles signature verification for a specific provider
- **Registry**: YAML-based configuration files that define provider settings
- **Discovery**: Automatic scanning of `captain_hook/` directories for provider configurations
- **Signing Secret**: A secret key used to verify webhook signatures (stored as ENV variable references)

### Design Philosophy

1. **Configuration as Code**: Provider settings live in YAML files, not the database
2. **Convention over Configuration**: Standard file structure (`captain_hook/<provider>/<provider>.yml`)
3. **Zero Database Configuration**: Database only stores runtime data (tokens, active status)
4. **ENV-based Secrets**: Signing secrets reference environment variables, never committed to version control
5. **Auto-Discovery**: Providers automatically detected from host app and gems

---

## Architecture

### Registry vs Database

CaptainHook uses a **two-layer architecture**:

**Registry (YAML Files)** - Source of Truth:
- Provider name, display name, description
- Verifier class and file location
- Signing secret (as ENV reference)
- Security settings (timestamp tolerance, payload limits, rate limits)
- Active/inactive status
- Source metadata (where the config was loaded from)

**Database (Runtime Data Only)**:
- Unique token (auto-generated for webhook URLs)
- Active/inactive toggle (can be changed at runtime)
- Rate limiting overrides (optional)
- Creation/update timestamps

### Data Flow

```
YAML Files (captain_hook/<provider>/)
    ↓
Provider Discovery Service (on boot)
    ↓
Provider Configs (in-memory structs)
    ↓
Database Sync (tokens, active status)
    ↓
Incoming Webhooks (use both registry + DB)
```

---

## Provider Setup & Configuration

### For Host Applications

Host applications can add webhook providers by creating configuration files in their `captain_hook/` directory.

#### Step 1: Create Directory Structure

```bash
# In your Rails app root
mkdir -p captain_hook/stripe
```

#### Step 2: Create Provider YAML File

Create `captain_hook/stripe/stripe.yml`:

```yaml
# Stripe webhook provider configuration
name: stripe
display_name: Stripe
description: Stripe payment webhooks
verifier_file: stripe.rb
active: true

# Security settings
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300

# Rate limiting (optional)
rate_limit_requests: 100
rate_limit_period: 60

# Payload size limit (optional, in bytes)
max_payload_size_bytes: 1048576
```

#### Step 3: Create Verifier File

Create `captain_hook/stripe/stripe.rb`:

```ruby
# frozen_string_literal: true

class StripeVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "Stripe-Signature"
  TIMESTAMP_TOLERANCE = 300

  def verify_signature(payload:, headers:, provider_config:)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return false if signature_header.blank?

    # Parse signature header: t=timestamp,v1=signature
    parsed = parse_kv_header(signature_header)
    timestamp = parsed["t"]
    signatures = [parsed["v1"], parsed["v0"]].flatten.compact

    return false if timestamp.blank? || signatures.empty?

    # Check timestamp tolerance
    if provider_config.timestamp_validation_enabled?
      tolerance = provider_config.timestamp_tolerance_seconds || TIMESTAMP_TOLERANCE
      return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
    end

    # Generate expected signature
    signed_payload = "#{timestamp}.#{payload}"
    expected_signature = generate_hmac(provider_config.signing_secret, signed_payload)

    # Check if any signature matches
    signatures.any? { |sig| secure_compare(sig, expected_signature) }
  end
end
```

#### Step 4: Set Environment Variable

```bash
# .env (use dotenv-rails gem)
STRIPE_WEBHOOK_SECRET=whsec_your_stripe_webhook_secret_here

# Or set directly in environment
export STRIPE_WEBHOOK_SECRET=whsec_your_stripe_webhook_secret_here
```

#### Step 5: Restart Application

```bash
rails server
# Provider will be automatically discovered and synced to database
```

### For Gem Authors

Gems can provide webhook integrations by including `captain_hook/` directories.

#### Directory Structure in Gem

```
your_gem/
├── lib/
│   └── your_gem.rb
├── captain_hook/
│   ├── stripe/
│   │   ├── stripe.yml
│   │   ├── stripe.rb
│   │   └── actions/
│   │       └── payment_succeeded_action.rb
│   └── paypal/
│       ├── paypal.yml
│       ├── paypal.rb
│       └── actions/
│           └── payment_captured_action.rb
└── your_gem.gemspec
```

#### Example Gem Integration

```ruby
# your_gem/captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe (via YourGem)
description: Stripe webhooks provided by YourGem
verifier_file: stripe.rb
active: true
signing_secret: ENV[YOUR_GEM_STRIPE_SECRET]
timestamp_tolerance_seconds: 300
```

**Note**: When a provider exists in both the host app and a gem, the **host app version takes precedence**.

---

## File Structure

### Standard Provider Structure

```
captain_hook/
└── <provider_name>/
    ├── <provider_name>.yml       # Required: Provider configuration
    ├── <provider_name>.rb         # Required: Verifier class
    └── actions/                   # Optional: Action classes
        ├── event_type_one_action.rb
        └── event_type_two_action.rb
```

### YAML Configuration Schema

```yaml
# Required fields
name: string                          # Provider identifier (lowercase, underscores)
verifier_file: string                 # Verifier Ruby file name

# Optional fields
display_name: string                  # Human-readable name
description: string                   # Provider description
active: boolean                       # Default: true

# Security settings
signing_secret: string                # ENV[VARIABLE_NAME] or literal value
timestamp_tolerance_seconds: integer  # Seconds to allow for clock skew
max_payload_size_bytes: integer       # Maximum webhook payload size

# Rate limiting
rate_limit_requests: integer          # Number of requests allowed
rate_limit_period: integer            # Time period in seconds
```

### Example: Complete Provider Setup

```
captain_hook/
└── stripe/
    ├── stripe.yml
    ├── stripe.rb
    └── actions/
        ├── payment_intent_succeeded_action.rb
        ├── charge_refunded_action.rb
        └── customer_subscription_updated_action.rb
```

---

## Provider Discovery Process

### When Discovery Happens

Provider discovery runs automatically during:
1. **Application Boot** (via Rails engine initializer)
2. **Manual Trigger** (via `CaptainHook.scan_providers` or admin UI)

### Discovery Algorithm

```ruby
# Step 1: Scan Application Directory
# Looks in Rails.root/captain_hook/*
def scan_application_providers
  app_captain_hook_path = Rails.root.join("captain_hook")
  return unless File.directory?(app_captain_hook_path)
  
  scan_directory(app_captain_hook_path, source: "application")
end

# Step 2: Scan All Loaded Gems
# Uses Bundler to find gems with captain_hook/ directories
def scan_gem_providers
  Bundler.load.specs.each do |spec|
    gem_captain_hook_path = File.join(spec.gem_dir, "captain_hook")
    next unless File.directory?(gem_captain_hook_path)
    
    scan_directory(gem_captain_hook_path, source: "gem:#{spec.name}")
  end
end

# Step 3: Scan Directory for Provider Configs
def scan_directory(directory_path, source:)
  Dir.glob(File.join(directory_path, "*")).each do |subdir|
    next unless File.directory?(subdir)
    
    provider_name = File.basename(subdir)
    next if provider_name.start_with?(".")
    
    # Look for YAML file matching provider name
    yaml_file = Dir.glob(File.join(subdir, "#{provider_name}.{yml,yaml}")).first
    next unless yaml_file
    
    # Load provider configuration
    provider_def = load_provider_file(yaml_file, source: source)
    next unless provider_def
    
    # Autoload verifier file if exists
    verifier_file = File.join(subdir, "#{provider_name}.rb")
    load verifier_file if File.exist?(verifier_file)
    
    # Autoload actions from actions/ directory
    actions_dir = File.join(subdir, "actions")
    load_actions_from_directory(actions_dir) if File.directory?(actions_dir)
    
    @discovered_providers << provider_def
  end
end

# Step 4: Deduplicate Providers
# Application providers take precedence over gem providers
def deduplicate_providers
  seen = {}
  @discovered_providers.each do |provider|
    name = provider["name"]
    next unless name
    
    # Priority: application > gem
    if !seen[name] || (provider["source"] == "application" && seen[name]["source"] != "application")
      seen[name] = provider
    end
  end
  
  @discovered_providers = seen.values
end
```

### Discovery Flow Diagram

```
Application Boot
    ↓
Engine Initializer Runs
    ↓
ProviderDiscovery.new.call
    ↓
┌─────────────────────────────────┐
│ Scan Rails.root/captain_hook/   │
│ - Find stripe/stripe.yml        │
│ - Load stripe.rb                │
│ - Load stripe/actions/*.rb      │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│ Scan All Gems                   │
│ - Check each gem for            │
│   captain_hook/ directory       │
│ - Load provider configs         │
│ - Load verifiers and actions    │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│ Deduplicate                     │
│ - Remove duplicate providers    │
│ - Prioritize app over gems      │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│ Sync to Database                │
│ - Create/update Provider records│
│ - Generate tokens if needed     │
│ - Preserve active status        │
└─────────────────────────────────┘
    ↓
Providers Ready to Receive Webhooks
```

### Discovery Service Usage

```ruby
# Manual discovery (in console or code)
discovery = CaptainHook::Services::ProviderDiscovery.new
provider_definitions = discovery.call

# Returns array of hashes:
# [
#   {
#     "name" => "stripe",
#     "display_name" => "Stripe",
#     "description" => "Stripe payment webhooks",
#     "verifier_file" => "stripe.rb",
#     "verifier_class" => "StripeVerifier",
#     "active" => true,
#     "signing_secret" => "ENV[STRIPE_WEBHOOK_SECRET]",
#     "timestamp_tolerance_seconds" => 300,
#     "rate_limit_requests" => 100,
#     "rate_limit_period" => 60,
#     "max_payload_size_bytes" => 1048576,
#     "source_file" => "/app/captain_hook/stripe/stripe.yml",
#     "source" => "application"
#   },
#   # ... more providers
# ]

# Create ProviderConfig structs
configs = provider_definitions.map do |definition|
  CaptainHook::ProviderConfig.new(definition)
end
```

---

## Webhook Request Flow

### Complete Request Lifecycle

```
External Provider (Stripe, PayPal, etc.)
    ↓
POST /captain_hook/:provider/:token
    ↓
┌──────────────────────────────────────────┐
│ 1. Route Matching                        │
│    - Match provider name from URL        │
│    - Extract token                       │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 2. Provider Lookup (Database)            │
│    - Find provider by name               │
│    - Return 404 if not found             │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 3. Token Verification                    │
│    - Compare URL token with DB token     │
│    - Return 401 if mismatch              │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 4. Rate Limiting Check                   │
│    - Check requests per time period      │
│    - Return 429 if exceeded              │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 5. Payload Size Check                    │
│    - Verify payload within limits        │
│    - Return 413 if too large             │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 6. Load Provider Config (Registry)       │
│    - Discover providers from YAML        │
│    - Find matching provider config       │
│    - Resolve signing secret from ENV     │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 7. Signature Verification                │
│    - Load verifier class                 │
│    - Call verify_signature method        │
│    - Return 401 if verification fails    │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 8. Timestamp Validation (Optional)       │
│    - Check webhook timestamp             │
│    - Verify within tolerance window      │
│    - Prevents replay attacks             │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 9. Store IncomingEvent                   │
│    - Parse external_id from payload      │
│    - Check for duplicates (idempotency)  │
│    - Save event to database              │
│    - Return 200 if duplicate             │
└──────────────────────────────────────────┘
    ↓
┌──────────────────────────────────────────┐
│ 10. Action Discovery                     │
│     - Look up actions for event_type     │
│     - Create action execution records    │
│     - Enqueue background jobs            │
└──────────────────────────────────────────┘
    ↓
Return 200 OK
    ↓
Background Jobs Process Actions
```

### Controller Code Flow

```ruby
# app/controllers/captain_hook/incoming_controller.rb
def create
  # 1. Provider lookup (database)
  provider = Provider.find_by(name: params[:provider])
  return render_not_found unless provider
  
  # 2. Token verification
  return render_unauthorized unless provider.token == params[:token]
  
  # 3. Rate limiting
  return render_rate_limited if rate_limit_exceeded?(provider)
  
  # 4. Read raw payload
  raw_payload = request.raw_post
  headers = extract_headers(request)
  
  # 5. Payload size check
  if provider_config.payload_size_limit_enabled?
    max_size = provider_config.max_payload_size_bytes
    return render_payload_too_large if raw_payload.bytesize > max_size
  end
  
  # 6. Load provider config from registry
  provider_definitions = ProviderDiscovery.new.call
  provider_def = provider_definitions.find { |p| p["name"] == provider.name }
  provider_config = ProviderConfig.new(provider_def)
  
  # 7. Signature verification
  verifier = provider_config.verifier
  unless verifier.verify_signature(
    payload: raw_payload,
    headers: headers,
    provider_config: provider_config
  )
    return render_unauthorized
  end
  
  # 8. Parse payload
  payload = parse_payload(raw_payload)
  event_type = extract_event_type(payload, provider)
  external_id = extract_external_id(payload, provider)
  
  # 9. Create incoming event (with idempotency)
  event = IncomingEvent.create_with(
    event_type: event_type,
    payload: payload,
    headers: headers,
    status: "received"
  ).find_or_create_by(
    provider: provider.name,
    external_id: external_id
  )
  
  # Return early if duplicate
  if event.previously_persisted?
    event.update(dedup_state: "duplicate")
    return render json: { status: "ok", message: "Duplicate event" }, status: :ok
  end
  
  # 10. Enqueue actions
  IncomingActionService.new(event).enqueue_actions
  
  render json: { status: "ok" }, status: :ok
end
```

---

## Signature Verification

### How Signature Verification Works

Webhook providers sign their requests to prove authenticity. Each provider uses different algorithms and header formats.

### Common Signature Schemes

**HMAC-SHA256 (Stripe, Square, PayPal)**:
1. Provider creates signature: `HMAC-SHA256(secret_key, payload_data)`
2. Signature sent in HTTP header
3. Receiver recomputes signature with same secret
4. Compare signatures using constant-time comparison

**Example Flow**:
```
Provider Side:
  payload = '{"event":"payment.succeeded"}'
  secret = "whsec_abc123"
  timestamp = "1234567890"
  signed_payload = "#{timestamp}.#{payload}"
  signature = HMAC-SHA256(secret, signed_payload)
  # => "a1b2c3d4..."
  
  Send HTTP POST with header:
    Stripe-Signature: t=1234567890,v1=a1b2c3d4...

Receiver Side (CaptainHook):
  1. Extract signature and timestamp from header
  2. Reconstruct signed payload: "#{timestamp}.#{payload}"
  3. Load signing secret from ENV: ENV["STRIPE_WEBHOOK_SECRET"]
  4. Compute expected signature: HMAC-SHA256(secret, signed_payload)
  5. Compare using secure_compare(received_sig, expected_sig)
  6. Accept if match, reject if mismatch
```

### Verifier Interface

All verifiers must implement the `verify_signature` method:

```ruby
def verify_signature(payload:, headers:, provider_config:)
  # payload:         Raw request body (String)
  # headers:         Request headers (Hash)
  # provider_config: ProviderConfig struct with settings
  
  # Returns: Boolean (true if valid, false otherwise)
end
```

### VerifierHelpers Module

CaptainHook provides helper methods for common verification tasks:

```ruby
module CaptainHook::VerifierHelpers
  # Generate HMAC-SHA256 signature (hex-encoded)
  def generate_hmac(secret, data)
    OpenSSL::HMAC.hexdigest("SHA256", secret, data)
  end
  
  # Generate HMAC-SHA256 signature (base64-encoded)
  def generate_hmac_base64(secret, data)
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, data))
  end
  
  # Extract header value (case-insensitive)
  def extract_header(headers, *keys)
    keys.each do |key|
      value = headers[key] || headers[key.downcase] || headers[key.upcase]
      return value if value.present?
    end
    nil
  end
  
  # Parse key-value header (e.g., "t=123,v1=abc")
  def parse_kv_header(header_value)
    return {} if header_value.blank?
    
    header_value.split(",").each_with_object({}) do |pair, hash|
      key, value = pair.split("=", 2)
      next if key.blank? || value.blank?
      
      key = key.strip
      value = value.strip
      
      if hash[key]
        hash[key] = [hash[key]].flatten << value
      else
        hash[key] = value
      end
    end
  end
  
  # Constant-time string comparison (prevents timing attacks)
  def secure_compare(a, b)
    return false if a.blank? || b.blank?
    return false if a.bytesize != b.bytesize
    
    l = a.unpack("C*")
    r = b.unpack("C*")
    
    result = 0
    l.zip(r) { |x, y| result |= x ^ y }
    result == 0
  end
  
  # Check if timestamp is within tolerance
  def timestamp_within_tolerance?(timestamp, tolerance)
    now = Time.current.to_i
    (now - timestamp).abs <= tolerance
  end
  
  # Check if signing secret is missing
  def missing_signing_secret?(provider_config)
    provider_config.signing_secret.blank? ||
      provider_config.signing_secret.start_with?("ENV[")
  end
end
```

---

## Signing Secrets Management

### ENV Variable Pattern

CaptainHook uses a special pattern to reference environment variables in YAML files:

```yaml
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

This pattern:
- Never commits secrets to version control
- Allows different secrets per environment
- Supports multiple providers with unique secrets
- Enables secret rotation without code changes

### How ENV Resolution Works

```ruby
# In YAML file
signing_secret: "ENV[STRIPE_WEBHOOK_SECRET]"

# ProviderConfig resolution
def signing_secret
  raw_secret = instance_variable_get(:@raw_signing_secret)
  return nil if raw_secret.blank?
  
  # Check if it matches ENV[VARIABLE_NAME] pattern
  if raw_secret.match?(/\AENV\[(\w+)\]\z/)
    # Extract variable name
    var_name = raw_secret.match(/\AENV\[(\w+)\]\z/)[1]
    # => "STRIPE_WEBHOOK_SECRET"
    
    # Fetch from environment
    ENV.fetch(var_name, nil)
    # => "whsec_abc123..." or nil if not set
  else
    # Return literal value
    raw_secret
  end
end
```

### Setting Environment Variables

**Development (dotenv-rails)**:
```bash
# .env file
STRIPE_WEBHOOK_SECRET=whsec_abc123
PAYPAL_WEBHOOK_SECRET=paypal_secret_456
SQUARE_WEBHOOK_SECRET=square_secret_789
```

**Production**:
```bash
# Heroku
heroku config:set STRIPE_WEBHOOK_SECRET=whsec_abc123

# Docker
docker run -e STRIPE_WEBHOOK_SECRET=whsec_abc123 myapp

# Kubernetes Secret
kubectl create secret generic webhook-secrets \
  --from-literal=STRIPE_WEBHOOK_SECRET=whsec_abc123
```

**Rails Credentials (Alternative)**:
```yaml
# config/credentials.yml.enc
stripe_webhook_secret: whsec_abc123
paypal_webhook_secret: paypal_secret_456

# Access in initializer
ENV["STRIPE_WEBHOOK_SECRET"] = Rails.application.credentials.stripe_webhook_secret
```

### Multi-Tenant Scenarios

For apps with multiple accounts of the same provider:

```yaml
# captain_hook/stripe_account_a/stripe_account_a.yml
name: stripe_account_a
display_name: Stripe (Account A)
signing_secret: ENV[STRIPE_SECRET_ACCOUNT_A]

# captain_hook/stripe_account_b/stripe_account_b.yml  
name: stripe_account_b
display_name: Stripe (Account B)
signing_secret: ENV[STRIPE_SECRET_ACCOUNT_B]
```

```bash
# .env
STRIPE_SECRET_ACCOUNT_A=whsec_account_a_secret
STRIPE_SECRET_ACCOUNT_B=whsec_account_b_secret
```

### Security Best Practices

1. **Never commit `.env` files**: Add to `.gitignore`
2. **Use different secrets per environment**: dev, staging, production
3. **Rotate secrets periodically**: Update ENV and provider dashboard
4. **Restrict secret access**: Use secret management systems (Vault, AWS Secrets Manager)
5. **Validate secrets on boot**: Check that required ENV variables are set

```ruby
# config/initializers/captain_hook.rb
required_secrets = %w[
  STRIPE_WEBHOOK_SECRET
  PAYPAL_WEBHOOK_SECRET
]

required_secrets.each do |secret|
  if ENV[secret].blank?
    Rails.logger.warn("Missing webhook secret: #{secret}")
  end
end
```

---

## Built-in Verifiers

CaptainHook includes verifiers for popular webhook providers.

### Stripe Verifier

**Signature Format**: `Stripe-Signature: t=1234567890,v1=abc123...`

```ruby
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
    
    # Timestamp validation
    if provider_config.timestamp_validation_enabled?
      tolerance = provider_config.timestamp_tolerance_seconds
      return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
    end
    
    # Signature validation
    signed_payload = "#{timestamp}.#{payload}"
    expected_signature = generate_hmac(provider_config.signing_secret, signed_payload)
    
    signatures.any? { |sig| secure_compare(sig, expected_signature) }
  end
end
```

### Square Verifier

**Signature Format**: `X-Square-Signature: abc123...` or `X-Square-HmacSha256-Signature: abc123...`

```ruby
class SquareVerifier
  include CaptainHook::VerifierHelpers
  
  SIGNATURE_HEADER = "X-Square-Signature"
  SIGNATURE_HMACSHA256_HEADER = "X-Square-HmacSha256-Signature"
  
  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, SIGNATURE_HMACSHA256_HEADER, SIGNATURE_HEADER)
    return false if signature.blank?
    
    # Generate signature: HMAC-SHA256(webhook_url + payload)
    webhook_url = extract_webhook_url(headers, provider_config)
    data_to_sign = "#{webhook_url}#{payload}"
    
    expected_signature = generate_hmac_base64(provider_config.signing_secret, data_to_sign)
    
    secure_compare(signature, expected_signature)
  end
  
  private
  
  def extract_webhook_url(headers, provider_config)
    # Try to get from header first
    url = extract_header(headers, "X-Square-Webhook-Url")
    return url if url.present?
    
    # Fallback to configured URL
    ENV["SQUARE_WEBHOOK_URL"] || provider_config.webhook_url
  end
end
```

### PayPal Verifier

**Signature Format**: Multiple headers with transmission ID, timestamp, certificate, etc.

```ruby
class PaypalVerifier
  include CaptainHook::VerifierHelpers
  
  SIGNATURE_HEADER = "Paypal-Transmission-Sig"
  CERT_URL_HEADER = "Paypal-Cert-Url"
  TRANSMISSION_ID_HEADER = "Paypal-Transmission-Id"
  TRANSMISSION_TIME_HEADER = "Paypal-Transmission-Time"
  AUTH_ALGO_HEADER = "Paypal-Auth-Algo"
  WEBHOOK_ID_HEADER = "Paypal-Webhook-Id"
  
  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, SIGNATURE_HEADER)
    transmission_id = extract_header(headers, TRANSMISSION_ID_HEADER)
    transmission_time = extract_header(headers, TRANSMISSION_TIME_HEADER)
    webhook_id = provider_config.signing_secret
    
    return false if signature.blank? || transmission_id.blank? || transmission_time.blank?
    
    # Timestamp validation
    if provider_config.timestamp_validation_enabled?
      time = Time.parse(transmission_time).to_i rescue nil
      return false if time.nil?
      
      tolerance = provider_config.timestamp_tolerance_seconds
      return false unless timestamp_within_tolerance?(time, tolerance)
    end
    
    # Build expected payload
    expected_payload = "#{transmission_id}|#{transmission_time}|#{webhook_id}|#{crc32(payload)}"
    expected_signature = generate_hmac_base64(webhook_id, expected_payload)
    
    secure_compare(signature, expected_signature)
  end
  
  private
  
  def crc32(data)
    Zlib.crc32(data).to_s
  end
end
```

### WebhookSite Verifier

**No Signature**: Used for testing, always returns true.

```ruby
class WebhookSiteVerifier
  def verify_signature(payload:, headers:, provider_config:)
    # No signature verification for webhook.site
    true
  end
end
```

---

## Custom Verifiers

### Creating a Custom Verifier

```ruby
# captain_hook/custom_provider/custom_provider.rb
class CustomProviderVerifier
  include CaptainHook::VerifierHelpers
  
  def verify_signature(payload:, headers:, provider_config:)
    # 1. Extract signature from headers
    signature = extract_header(headers, "X-Custom-Signature")
    return false if signature.blank?
    
    # 2. Extract other required data
    timestamp = extract_header(headers, "X-Custom-Timestamp")
    request_id = extract_header(headers, "X-Custom-Request-Id")
    
    # 3. Validate timestamp (optional)
    if provider_config.timestamp_validation_enabled? && timestamp.present?
      return false unless timestamp_within_tolerance?(timestamp.to_i, provider_config.timestamp_tolerance_seconds)
    end
    
    # 4. Build data to sign (provider-specific)
    data_to_sign = "#{request_id}:#{timestamp}:#{payload}"
    
    # 5. Compute expected signature
    expected_signature = generate_hmac(provider_config.signing_secret, data_to_sign)
    
    # 6. Compare signatures
    secure_compare(signature, expected_signature)
  end
end
```

### Verifier with API Validation

Some providers require API calls to validate webhooks:

```ruby
class ApiValidatingVerifier
  include CaptainHook::VerifierHelpers
  
  def verify_signature(payload:, headers:, provider_config:)
    webhook_id = extract_header(headers, "X-Webhook-Id")
    return false if webhook_id.blank?
    
    # Call provider API to validate webhook
    begin
      response = HTTP.get(
        "https://api.provider.com/webhooks/#{webhook_id}/verify",
        headers: { "Authorization" => "Bearer #{provider_config.signing_secret}" }
      )
      
      response.code == 200 && JSON.parse(response.body)["valid"] == true
    rescue => e
      Rails.logger.error("Webhook verification failed: #{e.message}")
      false
    end
  end
end
```

---

## Examples

### Example 1: Complete Stripe Setup

**File: `captain_hook/stripe/stripe.yml`**
```yaml
name: stripe
display_name: Stripe Payments
description: Stripe payment and subscription webhooks
verifier_file: stripe.rb
active: true

signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300
rate_limit_requests: 100
rate_limit_period: 60
max_payload_size_bytes: 2097152  # 2MB
```

**File: `captain_hook/stripe/stripe.rb`**
```ruby
class StripeVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "Stripe-Signature"
  TIMESTAMP_TOLERANCE = 300

  def verify_signature(payload:, headers:, provider_config:)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return false if signature_header.blank?

    parsed = parse_kv_header(signature_header)
    timestamp = parsed["t"]
    signatures = [parsed["v1"], parsed["v0"]].flatten.compact

    return false if timestamp.blank? || signatures.empty?

    if provider_config.timestamp_validation_enabled?
      tolerance = provider_config.timestamp_tolerance_seconds || TIMESTAMP_TOLERANCE
      return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
    end

    signed_payload = "#{timestamp}.#{payload}"
    expected_signature = generate_hmac(provider_config.signing_secret, signed_payload)

    signatures.any? { |sig| secure_compare(sig, expected_signature) }
  end
end
```

**Environment Setup:**
```bash
# .env
STRIPE_WEBHOOK_SECRET=whsec_abc123xyz789
```

**Webhook URL:**
```
https://yourapp.com/captain_hook/stripe/ABC123TOKEN
```

### Example 2: Custom Provider

**File: `captain_hook/github/github.yml`**
```yaml
name: github
display_name: GitHub
description: GitHub repository webhooks
verifier_file: github.rb
active: true

signing_secret: ENV[GITHUB_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 0  # GitHub doesn't use timestamps
rate_limit_requests: 200
rate_limit_period: 60
```

**File: `captain_hook/github/github.rb`**
```ruby
class GithubVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Hub-Signature-256"

  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, SIGNATURE_HEADER)
    return false if signature.blank?

    # GitHub format: "sha256=abc123..."
    signature = signature.sub(/^sha256=/, '')

    expected_signature = generate_hmac(provider_config.signing_secret, payload)

    secure_compare(signature, expected_signature)
  end
end
```

### Example 3: Multi-Account Setup

**File: `captain_hook/stripe_main/stripe_main.yml`**
```yaml
name: stripe_main
display_name: Stripe (Main Account)
description: Main Stripe account webhooks
verifier_file: stripe.rb
active: true
signing_secret: ENV[STRIPE_MAIN_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300
```

**File: `captain_hook/stripe_partner/stripe_partner.yml`**
```yaml
name: stripe_partner
display_name: Stripe (Partner Account)
description: Partner Stripe account webhooks
verifier_file: stripe.rb
active: true
signing_secret: ENV[STRIPE_PARTNER_WEBHOOK_SECRET]
timestamp_tolerance_seconds: 300
```

**File: `captain_hook/stripe_main/stripe.rb` and `captain_hook/stripe_partner/stripe.rb`**
```ruby
# Same verifier can be used for both
class StripeVerifier
  include CaptainHook::VerifierHelpers
  # ... (same implementation)
end
```

**Environment Setup:**
```bash
# .env
STRIPE_MAIN_WEBHOOK_SECRET=whsec_main_account_secret
STRIPE_PARTNER_WEBHOOK_SECRET=whsec_partner_account_secret
```

---

# Part 2: Actions & Event Processing

## Table of Contents

1. [Actions Overview](#actions-overview)
2. [Action Architecture](#action-architecture)
3. [Action Registration](#action-registration)
4. [Action Discovery](#action-discovery)
5. [Action Configuration](#action-configuration)
6. [Event Processing Lifecycle](#event-processing-lifecycle)
7. [Background Job Execution](#background-job-execution)
8. [Retry Logic & Error Handling](#retry-logic--error-handling)
9. [Action Examples](#action-examples)
10. [Testing Actions](#testing-actions)
11. [Best Practices](#best-practices)

---

## Actions Overview

Actions are Ruby classes that process webhook events. When a webhook is received and verified, CaptainHook looks up registered actions for that event type and executes them.

### Key Concepts

- **Action**: A Ruby class that processes a specific event type
- **Event Type**: A string identifier for the webhook event (e.g., `payment_intent.succeeded`)
- **Execution**: An individual action execution tracked in the database
- **Priority**: Determines the order in which actions are executed
- **Async/Sync**: Whether actions run in background jobs or inline
- **Retry Policy**: Configuration for retrying failed actions

### Action Lifecycle

```
Webhook Received & Verified
    ↓
IncomingEvent Created
    ↓
Action Lookup (by provider + event_type)
    ↓
Action Execution Records Created
    ↓
Jobs Enqueued (if async) OR Execute Inline (if sync)
    ↓
Background Job Processes Action
    ↓
Action#perform Called with Event
    ↓
Success → Mark Complete | Failure → Retry
```

---

## Action Architecture

### Action Registry

CaptainHook uses a **thread-safe in-memory registry** for actions, synced to the database on boot.

```ruby
# Global action registry
CaptainHook::ActionRegistry.register(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::PaymentIntentSucceededAction",
  async: true,
  priority: 100,
  max_attempts: 5,
  retry_delays: [30, 60, 300, 900, 3600]
)
```

### Action vs Execution

**Action (Database Record)**:
- Defines the handler for a provider + event_type combination
- Stored once in `captain_hook_actions` table
- Configuration: async, priority, retry settings
- Soft-deletable (deleted_at timestamp)

**IncomingEventAction (Execution Record)**:
- Tracks individual execution of an action
- One per action per incoming event
- Status: pending, processing, completed, failed
- Tracks attempts, errors, locking

### Database Schema

```ruby
# captain_hook_actions table
create_table :captain_hook_actions do |t|
  t.string :provider, null: false
  t.string :event_type, null: false
  t.string :action_class, null: false
  t.boolean :async, default: true, null: false
  t.integer :priority, default: 100, null: false
  t.integer :max_attempts, default: 5, null: false
  t.jsonb :retry_delays, default: [30, 60, 300, 900, 3600], null: false
  t.datetime :deleted_at
  t.timestamps
  
  t.index [:provider, :event_type, :action_class], unique: true, name: "idx_captain_hook_actions_unique"
  t.index :deleted_at
end

# captain_hook_incoming_event_actions table
create_table :captain_hook_incoming_event_actions do |t|
  t.uuid :incoming_event_id, null: false
  t.string :action_class, null: false
  t.integer :priority, default: 100, null: false
  t.string :status, default: "pending", null: false
  t.integer :attempt_count, default: 0, null: false
  t.datetime :last_attempt_at
  t.text :error_message
  t.integer :lock_version, default: 0, null: false
  t.datetime :locked_at
  t.string :locked_by
  t.timestamps
  
  t.index [:status, :priority, :action_class], name: "idx_captain_hook_handlers_processing_order"
  t.index :locked_at
end
```

### Action Class Interface

```ruby
class BaseAction
  # Required: Process the event
  def perform(event)
    # event: IncomingEvent instance
    # Implement your business logic here
  end
  
  # Optional: Determine if action should run
  def should_process?(event)
    true
  end
  
  # Optional: Handle errors
  def on_error(event, error)
    Rails.logger.error("Action failed: #{error.message}")
  end
  
  # Optional: Handle success
  def on_success(event)
    Rails.logger.info("Action succeeded")
  end
end
```

---

## Action Registration

### Registration Methods

**Method 1: Initializer (Recommended)**

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  # Register Stripe actions
  config.register_action(
    provider: "stripe",
    event_type: "payment_intent.succeeded",
    action_class: "Stripe::PaymentIntentSucceededAction",
    async: true,
    priority: 100,
    max_attempts: 5,
    retry_delays: [30, 60, 300, 900, 3600]
  )
  
  config.register_action(
    provider: "stripe",
    event_type: "charge.refunded",
    action_class: "Stripe::ChargeRefundedAction",
    async: true,
    priority: 50
  )
  
  # Register PayPal actions
  config.register_action(
    provider: "paypal",
    event_type: "PAYMENT.CAPTURE.COMPLETED",
    action_class: "Paypal::PaymentCapturedAction"
  )
end
```

**Method 2: Auto-Discovery from Files**

Create action files in `captain_hook/<provider>/actions/` directory:

```ruby
# captain_hook/stripe/actions/payment_intent_succeeded_action.rb
module Stripe
  class PaymentIntentSucceededAction
    def self.event_type
      "payment_intent.succeeded"
    end
    
    def self.provider
      "stripe"
    end
    
    def perform(event)
      # Process the event
    end
  end
end
```

When placed in the actions directory, these are automatically:
1. Loaded by ProviderDiscovery service
2. Registered in ActionRegistry
3. Synced to database

**Method 3: Direct Registry Access**

```ruby
# Anywhere in your code (before server starts)
CaptainHook::ActionRegistry.register(
  provider: "github",
  event_type: "push",
  action_class: "Github::PushAction",
  async: true,
  priority: 100
)
```

### Registration Flow

```ruby
# 1. Application Boot
# config/initializers/captain_hook.rb runs

CaptainHook.configure do |config|
  config.register_action(...)
end

# 2. Engine Initializer Runs
# lib/captain_hook/engine.rb

initializer "captain_hook.sync_actions" do
  ActiveSupport.on_load(:active_record) do
    # Discover providers and load action files
    provider_definitions = CaptainHook::Services::ProviderDiscovery.new.call
    
    # Actions are now registered in ActionRegistry
    # Sync registry to database
    CaptainHook::Services::ActionSync.new.call
  end
end

# 3. ActionSync Service
# Compares registry with database
# Creates/updates/soft-deletes action records

def sync
  registry_actions = ActionRegistry.all
  db_actions = Action.all.index_by { |a| [a.provider, a.event_type, a.action_class] }
  
  registry_actions.each do |reg_action|
    key = [reg_action[:provider], reg_action[:event_type], reg_action[:action_class]]
    
    if db_action = db_actions[key]
      # Update existing
      db_action.update!(
        async: reg_action[:async],
        priority: reg_action[:priority],
        max_attempts: reg_action[:max_attempts],
        retry_delays: reg_action[:retry_delays],
        deleted_at: nil  # Restore if soft-deleted
      )
    else
      # Create new
      Action.create!(reg_action)
    end
  end
  
  # Soft-delete actions not in registry
  orphaned_actions = db_actions.values - synced_actions
  orphaned_actions.each { |action| action.update(deleted_at: Time.current) }
end
```

---

## Action Discovery

### Auto-Discovery from Action Files

CaptainHook automatically discovers action files in provider directories:

```
captain_hook/
└── stripe/
    └── actions/
        ├── payment_intent_succeeded_action.rb
        ├── payment_intent_failed_action.rb
        ├── charge_refunded_action.rb
        └── customer_subscription_updated_action.rb
```

### Discovery Rules

1. **File Location**: `captain_hook/<provider>/actions/**/*.rb`
2. **Naming Convention**: `<event_type>_action.rb` (optional, but recommended)
3. **Class Definition**: Must respond to `event_type` and `provider` class methods
4. **Auto-Loading**: Files are `load`ed (not `require`d) during provider discovery

### Action Class Conventions

**Option 1: Class Methods (Explicit)**

```ruby
module Stripe
  class PaymentIntentSucceededAction
    def self.provider
      "stripe"
    end
    
    def self.event_type
      "payment_intent.succeeded"
    end
    
    def self.async
      true
    end
    
    def self.priority
      100
    end
    
    def perform(event)
      # Implementation
    end
  end
end
```

**Option 2: DSL Style**

```ruby
module Stripe
  class PaymentIntentSucceededAction
    include CaptainHook::ActionDSL
    
    provider "stripe"
    event_type "payment_intent.succeeded"
    async true
    priority 100
    max_attempts 3
    retry_delays [60, 300, 1800]
    
    def perform(event)
      # Implementation
    end
  end
end
```

**Option 3: Inherit from Base**

```ruby
module Stripe
  class PaymentIntentSucceededAction < CaptainHook::BaseAction
    self.provider = "stripe"
    self.event_type = "payment_intent.succeeded"
    
    def perform(event)
      # Implementation
    end
  end
end
```

### Discovery Process

```ruby
# During provider discovery
def scan_directory(directory_path, source:)
  # ... provider discovery code ...
  
  # Autoload actions from actions/ directory
  actions_dir = File.join(subdir, "actions")
  if File.directory?(actions_dir)
    load_actions_from_directory(actions_dir)
  end
end

def load_actions_from_directory(directory)
  Dir.glob(File.join(directory, "**", "*.rb")).each do |action_file|
    load action_file
    Rails.logger.debug("Loaded action from #{action_file}")
    
    # Action class should self-register via inherited hook or class method
  rescue StandardError => e
    Rails.logger.error("Failed to load action #{action_file}: #{e.message}")
  end
end
```

---

## Action Configuration

### Configuration Options

```ruby
CaptainHook::ActionRegistry.register(
  # Required
  provider: "stripe",              # Provider name
  event_type: "payment_intent.succeeded",  # Event type string
  action_class: "Stripe::PaymentIntentSucceededAction",  # Fully qualified class name
  
  # Optional (with defaults)
  async: true,                     # Run in background job (default: true)
  priority: 100,                   # Execution priority (lower = higher priority, default: 100)
  max_attempts: 5,                 # Maximum retry attempts (default: 5)
  retry_delays: [30, 60, 300, 900, 3600]  # Seconds between retries (default: exponential)
)
```

### Async vs Sync Execution

**Async (Default)**:
- Action runs in background job (Sidekiq, Solid Queue, etc.)
- Webhook returns 200 OK immediately
- Action execution tracked in database
- Supports retries and error handling
- Recommended for most use cases

```ruby
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::PaymentIntentSucceededAction",
  async: true  # Background job
)
```

**Sync**:
- Action runs inline before webhook response
- Webhook waits for action to complete
- Slower webhook response time
- Errors bubble up to webhook response
- Use for critical actions that must complete before acknowledgment

```ruby
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::CriticalAction",
  async: false  # Inline execution
)
```

### Priority

Lower numbers = higher priority (executed first):

```ruby
# High priority (runs first)
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::RecordPaymentAction",
  priority: 10
)

# Normal priority
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::SendEmailAction",
  priority: 100
)

# Low priority (runs last)
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::AnalyticsAction",
  priority: 500
)
```

### Retry Configuration

```ruby
# Quick retries
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::QuickAction",
  max_attempts: 3,
  retry_delays: [10, 30, 60]  # Retry after 10s, 30s, 60s
)

# Exponential backoff (default)
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::StandardAction",
  max_attempts: 5,
  retry_delays: [30, 60, 300, 900, 3600]  # 30s, 1m, 5m, 15m, 1h
)

# Aggressive retries
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::ImportantAction",
  max_attempts: 10,
  retry_delays: [60, 120, 300, 600, 1800, 3600, 7200, 14400, 28800, 86400]
)

# No retries
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::OneTimeAction",
  max_attempts: 1,
  retry_delays: []
)
```

---

## Event Processing Lifecycle

### Complete Flow

```
1. Webhook Received
   POST /captain_hook/stripe/abc123token
   ↓

2. Security Validation
   - Token check
   - Rate limiting
   - Payload size
   - Signature verification
   - Timestamp validation
   ↓

3. IncomingEvent Created
   - Parse event_type, external_id
   - Store payload, headers
   - Check idempotency (unique: provider + external_id)
   - Status: "received"
   ↓

4. Action Lookup
   IncomingActionService.new(event).enqueue_actions
   ↓
   - Query: Action.where(provider: "stripe", event_type: "payment_intent.succeeded")
   - Filter: active actions (deleted_at: nil)
   - Order by: priority ASC
   ↓

5. Create Execution Records
   For each action:
   - Create IncomingEventAction record
   - Status: "pending"
   - priority: from action config
   - attempt_count: 0
   ↓

6. Enqueue Jobs (if async)
   For each action:
   - IncomingActionJob.perform_later(execution.id)
   - Job scheduled immediately or after delay
   ↓

7. Job Processing
   IncomingActionJob#perform(execution_id)
   ↓
   - Load execution record
   - Check if already processed (status != "pending")
   - Acquire optimistic lock (lock_version)
   - Update status: "processing"
   - Load action class
   - Call action.perform(event)
   ↓

8. Action Execution
   Stripe::PaymentIntentSucceededAction.new.perform(event)
   ↓
   Business Logic:
   - Access event.payload (parsed JSON)
   - Access event.headers
   - Call application models/services
   - Make API calls
   - Update database
   ↓

9. Success or Failure
   
   SUCCESS:
   - Update execution status: "completed"
   - Set completed_at timestamp
   - Clear error_message
   - Call action.on_success(event) if defined
   
   FAILURE:
   - Increment attempt_count
   - Store error_message
   - Set last_attempt_at
   - Calculate retry delay
   - If attempts < max_attempts:
     - Enqueue job with delay
     - Status remains "pending"
   - Else:
     - Status: "failed"
     - Call action.on_error(event, error) if defined
   ↓

10. Retry (if needed)
    wait retry_delays[attempt_count - 1] seconds
    ↓
    Enqueue job again
    ↓
    Repeat from step 7
```

### IncomingActionService

```ruby
class IncomingActionService
  def initialize(event)
    @event = event
  end
  
  def enqueue_actions
    # Find actions for this provider + event_type
    actions = Action.where(
      provider: @event.provider,
      event_type: @event.event_type
    ).where(deleted_at: nil).order(priority: :asc)
    
    return if actions.empty?
    
    # Create execution records
    actions.each do |action|
      execution = @event.incoming_event_actions.create!(
        action_class: action.action_class,
        priority: action.priority,
        status: "pending",
        attempt_count: 0
      )
      
      if action.async
        # Enqueue background job
        IncomingActionJob.perform_later(execution.id)
      else
        # Execute inline
        IncomingActionJob.perform_now(execution.id)
      end
    end
  end
end
```

### Event Data Access

```ruby
class MyAction
  def perform(event)
    # Event attributes
    event.id                # UUID
    event.provider          # "stripe"
    event.event_type        # "payment_intent.succeeded"
    event.external_id       # Provider's event ID
    event.status            # "received", "processing", "completed", "failed"
    event.created_at        # When webhook was received
    
    # Event data
    event.payload           # Parsed JSON hash
    event.headers           # Request headers hash
    event.metadata          # Custom metadata (editable)
    
    # Related records
    event.incoming_event_actions  # All action executions
    event.provider_record         # Provider database record (if needed)
    
    # Example: Access nested payload data
    payment_intent_id = event.payload.dig("data", "object", "id")
    amount = event.payload.dig("data", "object", "amount")
    customer_id = event.payload.dig("data", "object", "customer")
    
    # Example: Check headers
    idempotency_key = event.headers["Idempotency-Key"]
    
    # Your business logic
    Payment.find_by(stripe_payment_intent_id: payment_intent_id).update!(
      status: "succeeded",
      amount: amount / 100.0  # Convert cents to dollars
    )
  end
end
```

---

## Background Job Execution

### IncomingActionJob

```ruby
class IncomingActionJob < ApplicationJob
  queue_as :captain_hook
  
  def perform(execution_id)
    execution = IncomingEventAction.find(execution_id)
    
    # Skip if already processed
    return if execution.completed? || execution.failed?
    
    # Optimistic locking
    execution.with_lock do
      execution.update!(
        status: "processing",
        locked_at: Time.current,
        locked_by: "#{Socket.gethostname}-#{Process.pid}"
      )
    end
    
    # Load action class
    action_class = execution.action_class.constantize
    action = action_class.new
    
    # Load event
    event = execution.incoming_event
    
    # Execute action
    action.perform(event)
    
    # Mark as completed
    execution.update!(
      status: "completed",
      error_message: nil
    )
    
    # Call success callback
    action.on_success(event) if action.respond_to?(:on_success)
    
  rescue StandardError => e
    handle_error(execution, action, event, e)
  end
  
  private
  
  def handle_error(execution, action, event, error)
    # Increment attempt counter
    execution.increment!(:attempt_count)
    execution.update!(
      error_message: "#{error.class}: #{error.message}\n#{error.backtrace.first(5).join("\n")}",
      last_attempt_at: Time.current
    )
    
    # Load retry config
    action_config = Action.find_by(
      provider: event.provider,
      event_type: event.event_type,
      action_class: execution.action_class
    )
    
    max_attempts = action_config&.max_attempts || 5
    retry_delays = action_config&.retry_delays || [30, 60, 300, 900, 3600]
    
    if execution.attempt_count < max_attempts
      # Schedule retry
      delay_index = [execution.attempt_count - 1, retry_delays.length - 1].min
      retry_delay = retry_delays[delay_index]
      
      IncomingActionJob.set(wait: retry_delay.seconds).perform_later(execution.id)
      
      Rails.logger.warn(
        "Action failed, will retry in #{retry_delay}s " \
        "(attempt #{execution.attempt_count}/#{max_attempts}): #{error.message}"
      )
    else
      # Max attempts reached
      execution.update!(status: "failed")
      
      # Call error callback
      action.on_error(event, error) if action.respond_to?(:on_error)
      
      Rails.logger.error(
        "Action failed permanently after #{execution.attempt_count} attempts: #{error.message}"
      )
      
      # Optional: Send alert/notification
      ActionFailureNotifier.notify(execution, error)
    end
  end
end
```

### Job Queue Configuration

```ruby
# config/application.rb
config.active_job.queue_adapter = :sidekiq  # or :solid_queue, :delayed_job, etc.

# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  config.job_queue = :captain_hook  # Custom queue name
  config.job_priority = 5           # Job priority (if adapter supports)
end
```

### Monitoring Jobs

```ruby
# Check pending executions
pending = IncomingEventAction.where(status: "pending").count

# Check failed executions
failed = IncomingEventAction.where(status: "failed").count

# Recent errors
recent_errors = IncomingEventAction
  .where(status: "failed")
  .where("created_at > ?", 1.hour.ago)
  .includes(:incoming_event)
  .map { |e| { event: e.incoming_event.event_type, error: e.error_message } }

# Retry failed actions manually
failed_execution = IncomingEventAction.find(id)
failed_execution.update!(status: "pending", attempt_count: 0)
IncomingActionJob.perform_later(failed_execution.id)
```

---

## Retry Logic & Error Handling

### Retry Strategy

CaptainHook uses **exponential backoff** with configurable delays:

```ruby
# Attempt 1: Immediate (fails)
# Attempt 2: Wait 30 seconds
# Attempt 3: Wait 60 seconds (1 minute)
# Attempt 4: Wait 300 seconds (5 minutes)
# Attempt 5: Wait 900 seconds (15 minutes)
# Attempt 6: Wait 3600 seconds (1 hour)
# Max attempts reached → Mark as failed
```

### Custom Retry Logic

```ruby
class CustomAction
  def perform(event)
    # Your logic that might fail
    external_api_call(event.payload)
  rescue ExternalAPI::RateLimitError => e
    # Custom retry for specific error
    if should_retry_rate_limit?(e)
      raise RetryableError.new("Rate limited, will retry", wait: 60)
    else
      # Don't retry, mark as failed
      raise PermanentError.new("Rate limit exceeded, giving up")
    end
  rescue ExternalAPI::NotFoundError => e
    # Don't retry for 404s
    Rails.logger.warn("Resource not found: #{e.message}")
    return  # Success (no error raised)
  end
  
  private
  
  def should_retry_rate_limit?(error)
    retry_after = error.response.headers["Retry-After"]
    retry_after.present? && retry_after.to_i < 300  # Only retry if < 5 minutes
  end
end
```

### Error Callbacks

```ruby
class NotificationAction
  def perform(event)
    send_notification(event.payload)
  end
  
  def on_error(event, error)
    # Called when action fails permanently (max attempts reached)
    ErrorTracker.report(error, context: {
      event_id: event.id,
      provider: event.provider,
      event_type: event.event_type
    })
    
    SlackNotifier.alert(
      "Action failed: #{error.message}",
      event_id: event.id
    )
  end
  
  def on_success(event)
    # Called when action completes successfully
    Rails.logger.info("Successfully processed event #{event.id}")
  end
end
```

### Conditional Execution

```ruby
class ConditionalAction
  def should_process?(event)
    # Return false to skip execution entirely
    # Useful for filtering events based on payload
    
    amount = event.payload.dig("data", "object", "amount")
    return false if amount.nil? || amount < 1000  # Skip small amounts
    
    customer = event.payload.dig("data", "object", "customer")
    return false unless customer.present?  # Skip without customer
    
    true
  end
  
  def perform(event)
    # Only runs if should_process? returns true
    process_large_payment(event)
  end
end
```

### Idempotency in Actions

```ruby
class IdempotentAction
  def perform(event)
    # Extract unique identifier from payload
    payment_intent_id = event.payload.dig("data", "object", "id")
    
    # Use find_or_create_by for idempotency
    payment = Payment.find_or_create_by(stripe_payment_intent_id: payment_intent_id) do |p|
      p.amount = event.payload.dig("data", "object", "amount") / 100.0
      p.currency = event.payload.dig("data", "object", "currency")
      p.status = "succeeded"
      p.customer_id = find_customer(event)
    end
    
    # Update is idempotent
    payment.update!(
      webhook_processed_at: Time.current,
      webhook_event_id: event.external_id
    )
  end
end
```

---

## Action Examples

### Example 1: Simple Payment Recording

```ruby
# captain_hook/stripe/actions/payment_intent_succeeded_action.rb
module Stripe
  class PaymentIntentSucceededAction
    def self.provider
      "stripe"
    end
    
    def self.event_type
      "payment_intent.succeeded"
    end
    
    def perform(event)
      payment_intent = event.payload["data"]["object"]
      
      payment = Payment.find_by(stripe_payment_intent_id: payment_intent["id"])
      
      if payment
        payment.update!(
          status: "succeeded",
          captured_at: Time.current,
          stripe_charge_id: payment_intent["charges"]["data"].first["id"]
        )
        
        # Send confirmation email
        PaymentMailer.success_notification(payment).deliver_later
      else
        Rails.logger.warn("Payment not found for payment_intent: #{payment_intent['id']}")
      end
    end
    
    def on_error(event, error)
      # Alert team of payment processing failure
      Bugsnag.notify(error) do |report|
        report.add_metadata(:webhook, {
          event_id: event.id,
          external_id: event.external_id,
          payment_intent_id: event.payload.dig("data", "object", "id")
        })
      end
    end
  end
end
```

### Example 2: Subscription Management

```ruby
# captain_hook/stripe/actions/customer_subscription_updated_action.rb
module Stripe
  class CustomerSubscriptionUpdatedAction
    def self.provider
      "stripe"
    end
    
    def self.event_type
      "customer.subscription.updated"
    end
    
    def perform(event)
      subscription_data = event.payload["data"]["object"]
      previous_attributes = event.payload["data"]["previous_attributes"]
      
      # Find subscription
      subscription = Subscription.find_by(
        stripe_subscription_id: subscription_data["id"]
      )
      
      return unless subscription
      
      # Update subscription
      subscription.update!(
        status: subscription_data["status"],
        current_period_start: Time.at(subscription_data["current_period_start"]),
        current_period_end: Time.at(subscription_data["current_period_end"]),
        cancel_at_period_end: subscription_data["cancel_at_period_end"]
      )
      
      # Handle specific changes
      if previous_attributes&.key?("status")
        handle_status_change(subscription, previous_attributes["status"], subscription_data["status"])
      end
      
      if subscription_data["cancel_at_period_end"]
        handle_cancellation_scheduled(subscription)
      end
    end
    
    private
    
    def handle_status_change(subscription, old_status, new_status)
      case new_status
      when "active"
        SubscriptionMailer.activated(subscription).deliver_later
      when "past_due"
        SubscriptionMailer.payment_failed(subscription).deliver_later
      when "canceled"
        SubscriptionMailer.canceled(subscription).deliver_later
        subscription.user.downgrade_to_free!
      end
    end
    
    def handle_cancellation_scheduled(subscription)
      SubscriptionMailer.cancellation_scheduled(
        subscription,
        end_date: subscription.current_period_end
      ).deliver_later
    end
  end
end
```

### Example 3: Multi-Step Processing

```ruby
# captain_hook/stripe/actions/invoice_payment_succeeded_action.rb
module Stripe
  class InvoicePaymentSucceededAction
    def self.provider
      "stripe"
    end
    
    def self.event_type
      "invoice.payment_succeeded"
    end
    
    def perform(event)
      invoice_data = event.payload["data"]["object"]
      
      # Step 1: Record invoice payment
      invoice = record_invoice_payment(invoice_data)
      
      # Step 2: Update subscription
      update_subscription_status(invoice)
      
      # Step 3: Fulfill order (if applicable)
      fulfill_pending_orders(invoice)
      
      # Step 4: Send receipt
      send_receipt(invoice)
      
      # Step 5: Update analytics
      track_revenue(invoice)
    end
    
    private
    
    def record_invoice_payment(invoice_data)
      Invoice.find_or_create_by(stripe_invoice_id: invoice_data["id"]) do |inv|
        inv.customer_id = find_customer_id(invoice_data["customer"])
        inv.subscription_id = find_subscription_id(invoice_data["subscription"])
        inv.amount = invoice_data["amount_paid"] / 100.0
        inv.status = "paid"
        inv.paid_at = Time.at(invoice_data["status_transitions"]["paid_at"])
      end
    end
    
    def update_subscription_status(invoice)
      return unless invoice.subscription
      
      invoice.subscription.update!(
        last_invoice_id: invoice.id,
        last_payment_at: invoice.paid_at,
        status: "active"
      )
    end
    
    def fulfill_pending_orders(invoice)
      invoice.orders.pending.each do |order|
        OrderFulfillmentJob.perform_later(order.id)
      end
    end
    
    def send_receipt(invoice)
      InvoiceMailer.receipt(invoice).deliver_later
    end
    
    def track_revenue(invoice)
      AnalyticsService.track(
        event: "revenue_received",
        properties: {
          amount: invoice.amount,
          customer_id: invoice.customer_id,
          subscription_id: invoice.subscription_id,
          invoice_id: invoice.id
        }
      )
    end
    
    def find_customer_id(stripe_customer_id)
      Customer.find_by(stripe_customer_id: stripe_customer_id)&.id
    end
    
    def find_subscription_id(stripe_subscription_id)
      return nil unless stripe_subscription_id
      Subscription.find_by(stripe_subscription_id: stripe_subscription_id)&.id
    end
  end
end
```

### Example 4: External API Integration

```ruby
# captain_hook/github/actions/push_action.rb
module Github
  class PushAction
    def self.provider
      "github"
    end
    
    def self.event_type
      "push"
    end
    
    def perform(event)
      payload = event.payload
      
      repository = payload["repository"]["full_name"]
      ref = payload["ref"]
      commits = payload["commits"]
      
      # Only process pushes to main branch
      return unless ref == "refs/heads/main"
      
      # Trigger deployment
      deployment = Deployment.create!(
        repository: repository,
        branch: "main",
        commit_sha: payload["after"],
        pusher: payload["pusher"]["name"],
        status: "pending"
      )
      
      # Call deployment service
      DeploymentService.deploy(
        repository: repository,
        commit_sha: payload["after"],
        deployment_id: deployment.id
      )
      
      # Notify Slack
      SlackNotifier.send_message(
        channel: "#deployments",
        text: "🚀 Deploying #{repository} to production",
        attachments: [{
          color: "good",
          fields: [
            { title: "Branch", value: "main", short: true },
            { title: "Commits", value: commits.length, short: true },
            { title: "Pusher", value: payload["pusher"]["name"], short: true }
          ]
        }]
      )
    end
    
    def on_error(event, error)
      repository = event.payload["repository"]["full_name"]
      
      SlackNotifier.send_message(
        channel: "#deployments",
        text: "❌ Deployment failed for #{repository}",
        attachments: [{
          color: "danger",
          text: error.message
        }]
      )
    end
  end
end
```

### Example 5: Batch Processing

```ruby
# captain_hook/stripe/actions/payment_intent_succeeded_batch_action.rb
module Stripe
  class PaymentIntentSucceededBatchAction
    def self.provider
      "stripe"
    end
    
    def self.event_type
      "payment_intent.succeeded"
    end
    
    def self.priority
      500  # Low priority (runs after other actions)
    end
    
    def perform(event)
      payment_intent = event.payload["data"]["object"]
      
      # Add to batch processing queue
      BatchProcessor.add_to_queue(:payment_analytics, {
        payment_intent_id: payment_intent["id"],
        amount: payment_intent["amount"],
        currency: payment_intent["currency"],
        customer_id: payment_intent["customer"],
        created_at: Time.at(payment_intent["created"])
      })
      
      # Process batch if threshold reached
      BatchProcessor.process_if_ready(:payment_analytics, threshold: 100)
    end
  end
end
```

---

## Testing Actions

### RSpec Example

```ruby
# spec/actions/stripe/payment_intent_succeeded_action_spec.rb
require "rails_helper"

RSpec.describe Stripe::PaymentIntentSucceededAction do
  describe "#perform" do
    let(:payment) { create(:payment, stripe_payment_intent_id: "pi_123") }
    
    let(:event) do
      create(:incoming_event,
        provider: "stripe",
        event_type: "payment_intent.succeeded",
        payload: {
          "data" => {
            "object" => {
              "id" => "pi_123",
              "amount" => 5000,
              "currency" => "usd",
              "status" => "succeeded",
              "charges" => {
                "data" => [{ "id" => "ch_123" }]
              }
            }
          }
        }
      )
    end
    
    it "updates payment status" do
      described_class.new.perform(event)
      
      expect(payment.reload).to have_attributes(
        status: "succeeded",
        stripe_charge_id: "ch_123"
      )
    end
    
    it "sends confirmation email" do
      expect {
        described_class.new.perform(event)
      }.to have_enqueued_mail(PaymentMailer, :success_notification)
    end
    
    context "when payment not found" do
      it "logs warning" do
        allow(Payment).to receive(:find_by).and_return(nil)
        
        expect(Rails.logger).to receive(:warn).with(/Payment not found/)
        
        described_class.new.perform(event)
      end
    end
  end
  
  describe "#on_error" do
    let(:event) { create(:incoming_event, provider: "stripe") }
    let(:error) { StandardError.new("Test error") }
    
    it "reports error to Bugsnag" do
      expect(Bugsnag).to receive(:notify).with(error)
      
      described_class.new.on_error(event, error)
    end
  end
end
```

### Minitest Example

```ruby
# test/actions/stripe/payment_intent_succeeded_action_test.rb
require "test_helper"

class Stripe::PaymentIntentSucceededActionTest < ActiveSupport::TestCase
  setup do
    @payment = payments(:pending_payment)
    @event = captain_hook_incoming_events(:stripe_payment_succeeded)
  end
  
  test "updates payment status to succeeded" do
    action = Stripe::PaymentIntentSucceededAction.new
    action.perform(@event)
    
    assert_equal "succeeded", @payment.reload.status
    assert_not_nil @payment.captured_at
  end
  
  test "sends confirmation email" do
    action = Stripe::PaymentIntentSucceededAction.new
    
    assert_enqueued_email_with PaymentMailer, :success_notification do
      action.perform(@event)
    end
  end
  
  test "logs warning when payment not found" do
    @event.payload["data"]["object"]["id"] = "pi_nonexistent"
    
    action = Stripe::PaymentIntentSucceededAction.new
    
    assert_logged "Payment not found" do
      action.perform(@event)
    end
  end
end
```

### Integration Test

```ruby
# spec/integration/webhook_processing_spec.rb
require "rails_helper"

RSpec.describe "Webhook Processing", type: :request do
  let(:provider) { create(:provider, name: "stripe") }
  let(:action) { create(:action, provider: "stripe", event_type: "payment_intent.succeeded") }
  
  let(:payload) do
    {
      id: "evt_123",
      type: "payment_intent.succeeded",
      data: {
        object: {
          id: "pi_123",
          amount: 5000,
          status: "succeeded"
        }
      }
    }.to_json
  end
  
  let(:signature) do
    timestamp = Time.current.to_i
    signed_payload = "#{timestamp}.#{payload}"
    hmac = OpenSSL::HMAC.hexdigest("SHA256", ENV["STRIPE_WEBHOOK_SECRET"], signed_payload)
    "t=#{timestamp},v1=#{hmac}"
  end
  
  it "processes webhook end-to-end" do
    expect {
      post "/captain_hook/stripe/#{provider.token}",
        params: payload,
        headers: {
          "Content-Type" => "application/json",
          "Stripe-Signature" => signature
        }
    }.to change { IncomingEvent.count }.by(1)
      .and change { IncomingEventAction.count }.by(1)
    
    expect(response).to have_http_status(:ok)
    
    # Process background job
    perform_enqueued_jobs
    
    event = IncomingEvent.last
    execution = event.incoming_event_actions.last
    
    expect(execution.status).to eq("completed")
    expect(execution.error_message).to be_nil
  end
end
```

---

## Best Practices

### 1. Keep Actions Focused

**Good**: Single responsibility
```ruby
class RecordPaymentAction
  def perform(event)
    payment_intent = event.payload["data"]["object"]
    Payment.find_by(stripe_payment_intent_id: payment_intent["id"])
           .update!(status: "succeeded")
  end
end
```

**Bad**: Too many responsibilities
```ruby
class DoEverythingAction
  def perform(event)
    # Updates payment, sends email, tracks analytics,
    # updates subscription, generates invoice, etc.
    # (100+ lines of code)
  end
end
```

### 2. Use Multiple Actions Instead

```ruby
# Register multiple focused actions
config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "RecordPaymentAction",
  priority: 10  # Run first
)

config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "SendReceiptAction",
  priority: 20  # Run second
)

config.register_action(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "TrackAnalyticsAction",
  priority: 100  # Run last
)
```

### 3. Handle Missing Data Gracefully

```ruby
def perform(event)
  payment_intent_id = event.payload.dig("data", "object", "id")
  return unless payment_intent_id  # Guard clause
  
  payment = Payment.find_by(stripe_payment_intent_id: payment_intent_id)
  return unless payment  # Skip if not found
  
  # Process payment
end
```

### 4. Use Idempotent Operations

```ruby
def perform(event)
  # Use find_or_create_by
  payment = Payment.find_or_create_by(stripe_payment_intent_id: payment_intent_id) do |p|
    p.amount = amount
    p.status = "succeeded"
  end
  
  # Use update! (idempotent)
  payment.update!(processed_at: Time.current)
end
```

### 5. Log Meaningful Messages

```ruby
def perform(event)
  Rails.logger.info("Processing payment_intent.succeeded for #{event.external_id}")
  
  # ... processing ...
  
  Rails.logger.info("Successfully updated payment #{payment.id}")
end

def on_error(event, error)
  Rails.logger.error(
    "Failed to process payment: #{error.message}\n" \
    "Event ID: #{event.id}\n" \
    "Payment Intent: #{event.payload.dig('data', 'object', 'id')}"
  )
end
```

### 6. Use should_process? for Filtering

```ruby
def should_process?(event)
  # Skip test mode events in production
  return false if Rails.env.production? && event.payload.dig("livemode") == false
  
  # Skip events without customer
  return false unless event.payload.dig("data", "object", "customer").present?
  
  true
end
```

### 7. Set Appropriate Priorities

```ruby
# Critical: Update core data first
config.register_action(..., priority: 10)

# Normal: Send notifications
config.register_action(..., priority: 100)

# Low: Analytics, reporting
config.register_action(..., priority: 500)
```

### 8. Configure Retries Based on Action Type

```ruby
# External API calls: Longer delays
config.register_action(
  ...,
  retry_delays: [60, 300, 900, 3600]  # 1m, 5m, 15m, 1h
)

# Database operations: Quick retries
config.register_action(
  ...,
  retry_delays: [10, 30, 60]  # 10s, 30s, 1m
)

# Non-critical: Fewer attempts
config.register_action(
  ...,
  max_attempts: 2
)
```

### 9. Monitor and Alert

```ruby
def on_error(event, error)
  # Report to error tracker
  Sentry.capture_exception(error, extra: {
    event_id: event.id,
    provider: event.provider,
    event_type: event.event_type
  })
  
  # Alert team for critical actions
  if critical_action?
    PagerDuty.alert("Critical webhook action failed", error)
  end
end
```

### 10. Document Event Payloads

```ruby
# captain_hook/stripe/actions/payment_intent_succeeded_action.rb
#
# Stripe payload structure:
# {
#   "id": "evt_123",
#   "type": "payment_intent.succeeded",
#   "data": {
#     "object": {
#       "id": "pi_123",
#       "amount": 5000,
#       "currency": "usd",
#       "customer": "cus_123",
#       ...
#     }
#   }
# }
class PaymentIntentSucceededAction
  def perform(event)
    # ...
  end
end
```

---

**End of Part 2**

This completes the comprehensive technical documentation for CaptainHook's Providers, Verifiers, and Actions systems.
