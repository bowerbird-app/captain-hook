# Technical Process: Providers and Adapters

This document provides a deep technical explanation of how CaptainHook's provider system works, from file discovery to webhook verification.

## Table of Contents

1. [Provider Setup & Discovery](#provider-setup--discovery)
2. [The Scanning Process](#the-scanning-process)
3. [Provider Table Schema](#provider-table-schema)
4. [Webhook Processing Flow](#webhook-processing-flow)
5. [Adapter Verification Methods](#adapter-verification-methods)
6. [Why YAML + Ruby Files](#why-yaml--ruby-files)
7. [Scenarios & Limitations (Providers)](#scenarios--limitations-providers)
8. [Handlers: Business Logic Execution](#handlers-business-logic-execution)
9. [Handler Registration](#handler-registration)
10. [Handler Discovery & Sync](#handler-discovery--sync)
11. [Handler Table Schema](#handler-table-schema)
12. [Handler Execution Flow](#handler-execution-flow)
13. [Handler Scenarios & Limitations](#handler-scenarios--limitations)

---

## Provider Setup & Discovery

### File Hierarchy

Providers can be discovered from two locations:

1. **Host Application**: `Rails.root/captain_hook/providers/`
2. **Loaded Gems**: `<gem_root>/captain_hook/providers/`

Both locations support two file structure patterns:

#### Pattern 1: Flat Structure
```
captain_hook/providers/
├── stripe.yml          # Provider configuration
├── stripe.rb           # Adapter implementation (optional)
├── square.yml
└── square.rb
```

#### Pattern 2: Nested Structure (Recommended)
```
captain_hook/providers/
├── stripe/
│   ├── stripe.yml      # Provider configuration
│   └── stripe.rb       # Adapter implementation
├── square/
│   ├── square.yml
│   └── square.rb
└── paypal/
    ├── paypal.yml
    └── paypal.rb
```

**Nested structure is preferred because:**
- Keeps provider-related files grouped together
- Makes it easy to copy/move entire providers
- Avoids filename conflicts between providers
- Clearer organization when managing multiple providers

### YAML Configuration Structure

Each provider needs a YAML file with these fields:

```yaml
# captain_hook/providers/stripe/stripe.yml
name: stripe                                  # Required: Unique identifier (lowercase, underscores only)
display_name: Stripe                          # Optional: Human-readable name
description: Stripe payment webhooks          # Optional: Description
adapter_file: stripe.rb                       # Optional: Ruby file with adapter class for signature verification
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]    # Optional: HMAC secret (supports ENV[] syntax)
active: true                                  # Optional: Enable/disable (default: true)

# Security settings (optional)
timestamp_tolerance_seconds: 300              # Time window for timestamp validation (default: 300)
max_payload_size_bytes: 1048576              # Max payload size in bytes (default: 1MB)

# Rate limiting (optional)
rate_limit_requests: 100                      # Max requests (default: 100)
rate_limit_period: 60                         # Period in seconds (default: 60)
```

### Ruby Adapter Structure

If your provider needs signature verification, create a corresponding `.rb` file:

```ruby
# captain_hook/providers/stripe/stripe.rb
class StripeAdapter
  include CaptainHook::AdapterHelpers

  # Required: Verify webhook signature
  def verify_signature(payload:, headers:, provider_config:)
    # Provider-specific verification logic
    signature = extract_header(headers, "Stripe-Signature")
    # ... verification code
  end

  # Required: Extract timestamp from headers
  def extract_timestamp(headers)
    # Return Unix timestamp integer
  end

  # Required: Extract unique event ID from payload
  def extract_event_id(payload)
    payload["id"]
  end

  # Required: Extract event type from payload
  def extract_event_type(payload)
    payload["type"]
  end
end
```

---

## The Scanning Process

### What Happens During a Scan

When you click "Scan for Providers" in the admin UI or run the discovery service, here's the detailed flow:

#### Step 1: File Discovery

```ruby
# lib/captain_hook/services/provider_discovery.rb

1. Scan application directory: Rails.root/captain_hook/providers/
   - Find all *.yml and *.yaml files in root
   - Find all subdirectories, then look for matching YAML files
   
2. Scan loaded gems via Bundler
   - Iterate through all gems in Gemfile
   - Check if <gem_root>/captain_hook/providers/ exists
   - Scan using same pattern as application
```

**Discovery Order:**
1. Flat YAML files (`.yml`, `.yaml`) in the providers directory
2. Nested subdirectories matching pattern: `provider_name/provider_name.yml`
3. Nested subdirectories with any YAML file (fallback)

#### Step 2: YAML Parsing

For each discovered YAML file:

```ruby
content = File.read(file_path)
yaml_data = YAML.safe_load(content, 
  permitted_classes: [], 
  permitted_symbols: [], 
  aliases: false
)

# Add metadata
yaml_data.merge!(
  "source_file" => file_path,
  "source" => "application" or "gem:gem_name"
)
```

**Source tracking** helps identify where providers came from:
- `"application"` = Your Rails app
- `"gem:marikit-stripe"` = From a specific gem

#### Step 3: Adapter Auto-loading

If using nested structure, the adapter `.rb` file is automatically loaded:

```ruby
# If stripe/stripe.yml exists, also load stripe/stripe.rb
adapter_file = File.join(subdir, "#{provider_name}.rb")

if File.exist?(adapter_file)
  load adapter_file  # Loads the Ruby class
  Rails.logger.debug("Loaded adapter from #{adapter_file}")
end
```

This happens **during discovery**, so the adapter class is available when needed.

#### Step 4: Database Synchronization

The controller compares discovered providers with database records:

```ruby
# app/controllers/captain_hook/admin/providers_controller.rb

provider_definitions.each do |provider_def|
  existing = Provider.find_by(name: provider_def['name'])
  
  if existing
    # Update existing provider (if using "Full Sync" mode)
    existing.update!(provider_def) if sync_mode == :full
  else
    # Create new provider
    Provider.create!(provider_def.merge(token: SecureRandom.urlsafe_base64(32)))
  end
end
```

**Two Scan Modes:**

1. **Discover New** (default):
   - Only creates providers that don't exist
   - Doesn't modify existing providers
   - Safe for adding new providers without affecting current setup

2. **Full Sync**:
   - Creates new providers
   - Updates existing providers with YAML values
   - Overwrites database with file definitions
   - Use when you've updated YAML configs

#### Step 5: Token Generation

Each provider gets a unique, cryptographically secure token:

```ruby
self.token = SecureRandom.urlsafe_base64(32)
# Example: "yJ8fK9mNpQrS7tUvWxYz-A2B3C4D5E6F"
```

This token becomes part of the webhook URL: `/captain_hook/stripe/yJ8fK9mNpQrS7tUvWxYz-A2B3C4D5E6F`

---

## Provider Table Schema

### Table: `captain_hook_providers`

```sql
CREATE TABLE captain_hook_providers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Identity fields
  name VARCHAR NOT NULL UNIQUE,              -- Provider identifier (e.g., "stripe")
  display_name VARCHAR,                      -- Human-readable name (e.g., "Stripe")
  description TEXT,                          -- Optional description
  token VARCHAR NOT NULL UNIQUE,             -- Secure URL token
  
  -- Security configuration
  signing_secret VARCHAR,                    -- Encrypted HMAC secret
  adapter_class VARCHAR DEFAULT NULL,        -- Adapter class name (NULL = no verification, auto-extracted)
  adapter_file VARCHAR,                      -- Ruby file containing adapter (added in 20260117000002)
  timestamp_tolerance_seconds INTEGER DEFAULT 300,  -- Replay attack protection
  
  -- Resource limits
  max_payload_size_bytes INTEGER DEFAULT 1048576,   -- DoS protection (1MB default)
  rate_limit_requests INTEGER DEFAULT 100,          -- Rate limit threshold
  rate_limit_period INTEGER DEFAULT 60,             -- Rate limit window (seconds)
  
  -- State management
  active BOOLEAN NOT NULL DEFAULT true,      -- Enable/disable provider
  metadata JSONB DEFAULT '{}',               -- Flexible additional data
  
  -- Timestamps
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Indexes
CREATE UNIQUE INDEX ON captain_hook_providers(name);
CREATE UNIQUE INDEX ON captain_hook_providers(token);
CREATE INDEX ON captain_hook_providers(active);
```

### Column Explanations

#### Identity Fields

**`name`** (VARCHAR, NOT NULL, UNIQUE)
- Primary identifier used in URLs and code
- Must be lowercase with underscores only: `^[a-z0-9_]+$`
- Example: `stripe`, `square`, `paypal_production`
- Used in webhook URL: `/captain_hook/{name}/{token}`
- Used as foreign key in `incoming_events` table

**`display_name`** (VARCHAR, NULLABLE)
- Human-readable name shown in admin UI
- Auto-generated from `name` if not provided (titleized)
- Example: `name: "stripe"` → `display_name: "Stripe"`
- Not used in any logic, purely cosmetic

**`description`** (TEXT, NULLABLE)
- Optional documentation about the provider
- Shown in admin UI for reference
- Useful for multi-instance providers: "Stripe - Production Account"

**`token`** (VARCHAR, NOT NULL, UNIQUE)
- Cryptographically secure random string (32 bytes, base64-encoded)
- Acts as authentication for incoming webhooks
- Generated automatically on provider creation
- Never shown in logs for security
- Cannot be changed after creation (would break provider's webhook config)

#### Security Configuration

**`signing_secret`** (VARCHAR, NULLABLE, ENCRYPTED)
- HMAC secret key used for signature verification
- **Encrypted at rest** using ActiveRecord Encryption (AES-256-GCM)
- Can be `NULL` if provider doesn't support signature verification
- Supports two storage methods:
  1. **Database storage**: Encrypted value stored directly
  2. **Environment variable**: YAML value `ENV[STRIPE_SECRET]` resolved at runtime
- Environment variables override database values
- Model getter checks: `ENV["#{name.upcase}_WEBHOOK_SECRET"]` first

**`adapter_class`** (VARCHAR, NULLABLE)
- **Changed from NOT NULL to NULLABLE in migration 20260117000001**
- **Auto-extracted from adapter_file during provider sync (migration 20260117000002)**
- Class name of adapter (e.g., `"StripeAdapter"`)
- `NULL` means no signature verification (token-only authentication)
- Class must exist and be loadable when webhook arrives
- Auto-detected from adapter_file specified in YAML during provider scan
- Used to instantiate adapter: `adapter_class.constantize.new`

**`timestamp_tolerance_seconds`** (INTEGER, DEFAULT 300)
- Maximum age of webhook timestamps (5 minutes default)
- Prevents replay attacks (attacker resending old webhooks)
- `NULL` or `0` disables timestamp validation
- Checked using adapter's `extract_timestamp(headers)` method
- Formula: `(current_time - timestamp).abs <= tolerance`

#### Resource Limits

**`max_payload_size_bytes`** (INTEGER, DEFAULT 1048576)
- Maximum allowed payload size in bytes (1MB default)
- Protects against DoS attacks with huge payloads
- Checked before JSON parsing: `request.raw_post.bytesize`
- `NULL` or `0` disables limit
- Returns HTTP 413 Payload Too Large if exceeded

**`rate_limit_requests`** (INTEGER, DEFAULT 100)
- Maximum number of requests allowed per period
- Works with `rate_limit_period` for sliding window rate limiting
- `NULL` disables rate limiting
- Tracked in Redis (if available) or memory
- Returns HTTP 429 Too Many Requests if exceeded

**`rate_limit_period`** (INTEGER, DEFAULT 60)
- Time window in seconds for rate limiting
- Default: 100 requests per 60 seconds
- Must be > 0 if rate limiting is enabled
- Sliding window implementation (not fixed buckets)

#### State Management

**`active`** (BOOLEAN, NOT NULL, DEFAULT true)
- Enable/disable webhook reception without deleting provider
- Inactive providers return HTTP 403 Forbidden
- Useful for temporarily pausing webhooks
- Handlers are not deleted when deactivating

**`metadata`** (JSONB, DEFAULT '{}')
- Flexible storage for provider-specific data
- Not used by CaptainHook core
- Available for custom extensions
- Example uses:
  - Last successful webhook timestamp
  - Provider account identifiers
  - Custom configuration flags

---

## Webhook Processing Flow

### Complete Request Lifecycle

```
External Provider → POST → IncomingController → Verification → Event Storage → Handler Dispatch
```

Here's the detailed flow when a webhook arrives at `/captain_hook/stripe/abc123token`:

### 1. Route Matching

```ruby
# config/routes.rb
post "/captain_hook/:provider/:token", to: "captain_hook/incoming#create"

# params[:provider] = "stripe"
# params[:token] = "abc123token"
```

### 2. Provider Lookup

```ruby
# app/controllers/captain_hook/incoming_controller.rb

provider = CaptainHook::Provider.find_by(name: params[:provider])

# Returns HTTP 404 if provider doesn't exist
# Returns HTTP 403 if provider.active == false
```

### 3. Token Verification

```ruby
unless provider.token == params[:token]
  render json: { error: "Invalid token" }, status: :unauthorized
  return
end
```

**Why token-based URLs?**
- Prevents unauthorized webhook submissions
- Each provider gets a unique URL
- No need to check origin IP addresses
- Simple and secure authentication layer

### 4. Rate Limiting Check

```ruby
if provider.rate_limiting_enabled?
  rate_limiter = CaptainHook::Services::RateLimiter.new
  
  rate_limiter.record!(
    provider: provider_name,
    limit: provider.rate_limit_requests,
    period: provider.rate_limit_period
  )
  # Raises RateLimitExceeded if limit hit
end
```

Uses Redis (preferred) or in-memory storage for tracking request counts.

### 5. Payload Size Check

```ruby
if provider.payload_size_limit_enabled?
  payload_size = request.raw_post.bytesize
  
  if payload_size > provider.max_payload_size_bytes
    render json: { error: "Payload too large" }, status: :payload_too_large
    return
  end
end
```

Checked **before** JSON parsing to prevent memory exhaustion attacks.

### 6. Signature Verification (The Critical Step)

```ruby
raw_payload = request.raw_post  # Original body as string
headers = extract_headers(request)  # HTTP headers as hash

adapter = provider.adapter  # Instantiate adapter class

unless adapter.verify_signature(
  payload: raw_payload,
  headers: headers,
  provider_config: provider
)
  render json: { error: "Invalid signature" }, status: :unauthorized
  return
end
```

**What happens in adapter:**

```ruby
# Example: Stripe adapter
def verify_signature(payload:, headers:, provider_config:)
  # 1. Extract signature from headers
  signature_header = extract_header(headers, "Stripe-Signature")
  # => "t=1609459200,v1=abc123def456,v0=older789"
  
  # 2. Parse into components
  parsed = parse_kv_header(signature_header)
  # => {"t" => "1609459200", "v1" => ["abc123def456"], "v0" => ["older789"]}
  
  # 3. Check timestamp
  timestamp = parsed["t"].to_i
  if provider_config.timestamp_validation_enabled?
    return false unless timestamp_within_tolerance?(timestamp, 300)
  end
  
  # 4. Reconstruct signed payload
  signed_payload = "#{timestamp}.#{payload}"
  
  # 5. Calculate expected signature
  expected_signature = generate_hmac(
    provider_config.signing_secret,
    signed_payload
  )
  
  # 6. Constant-time comparison (prevents timing attacks)
  signatures = [parsed["v1"], parsed["v0"]].flatten.compact
  signatures.any? { |sig| secure_compare(sig, expected_signature) }
end
```

**Why signature verification matters:**
- Proves webhook came from the actual provider
- Prevents webhook spoofing/forgery
- Validates payload hasn't been tampered with
- Essential for production security

### 7. JSON Parsing

```ruby
begin
  parsed_payload = JSON.parse(raw_payload)
rescue JSON::ParserError => e
  render json: { error: "Invalid JSON" }, status: :bad_request
  return
end
```

Parsing happens **after** signature verification to ensure we only parse trusted data.

### 8. Metadata Extraction

```ruby
external_id = adapter.extract_event_id(parsed_payload)
# => "evt_1JqXyZ2eZvKYlo2C8"

event_type = adapter.extract_event_type(parsed_payload)
# => "payment_intent.succeeded"

timestamp = adapter.extract_timestamp(headers)
# => 1609459200
```

Adapters normalize provider-specific formats into CaptainHook's standard fields.

### 9. Timestamp Validation

```ruby
if provider.timestamp_validation_enabled? && timestamp
  validator = CaptainHook::TimeWindowValidator.new(
    tolerance_seconds: provider.timestamp_tolerance_seconds
  )
  
  unless validator.valid?(timestamp)
    render json: { error: "Timestamp outside tolerance window" }, 
           status: :bad_request
    return
  end
end
```

Prevents replay attacks where attackers resend old webhooks.

### 10. Event Storage (Idempotency)

```ruby
event = CaptainHook::IncomingEvent.find_or_create_by_external!(
  provider: provider_name,
  external_id: external_id,
  event_type: event_type,
  payload: parsed_payload,
  headers: headers,
  metadata: { received_at: Time.current.iso8601 },
  status: :received,
  dedup_state: :unique
)
```

**Idempotency mechanism:**
```sql
-- Unique index prevents duplicate events
CREATE UNIQUE INDEX idx_captain_hook_incoming_events_idempotency 
  ON captain_hook_incoming_events(provider, external_id);
```

If the same `(provider, external_id)` arrives twice:
- First time: Creates event, returns HTTP 201 Created
- Second time: Finds existing event, marks as duplicate, returns HTTP 200 OK
- **No re-processing happens** (handlers are not re-queued)

### 11. Handler Dispatch

```ruby
if event.previously_new_record?
  # New event - create handler records
  create_handlers_for_event(event)
  
  render json: { id: event.id, status: "received" }, status: :created
else
  # Duplicate event
  event.mark_duplicate!
  render json: { id: event.id, status: "duplicate" }, status: :ok
end
```

**Note:** For complete details on handler creation, registration, and execution flow, see [Handlers: Business Logic Execution](#handlers-business-logic-execution) below.

---

## Adapter Verification Methods

The `CaptainHook::AdapterHelpers` module provides battle-tested security methods for adapters.

### Core Verification Methods

#### 1. `secure_compare(a, b)`

**Purpose:** Constant-time string comparison to prevent timing attacks

```ruby
def secure_compare(a, b)
  return false if a.blank? || b.blank?
  return false if a.bytesize != b.bytesize

  l = a.unpack("C*")  # Convert to byte arrays
  r = b.unpack("C*")

  result = 0
  l.zip(r) { |x, y| result |= x ^ y }  # XOR all bytes
  result.zero?  # True if all bytes matched
end
```

**Why constant-time?**
- Normal string comparison (`==`) returns as soon as a mismatch is found
- Attacker can measure response time to guess signature byte-by-byte
- Constant-time comparison always checks all bytes
- Makes timing attacks impractical

**Usage:**
```ruby
expected = generate_hmac(secret, data)
actual = extract_header(headers, "X-Signature")

secure_compare(expected, actual)  # Safe
actual == expected  # UNSAFE - vulnerable to timing attacks
```

#### 2. `generate_hmac(secret, data)`

**Purpose:** Generate HMAC-SHA256 signature (hex-encoded)

```ruby
def generate_hmac(secret, data)
  OpenSSL::HMAC.hexdigest("SHA256", secret, data)
end
```

**Returns:** Lowercase hex string (64 characters)
**Example:** `"a3b4c5d6e7f8..."`

**Usage:**
```ruby
secret = "whsec_abc123"
payload = "#{timestamp}.#{request_body}"
signature = generate_hmac(secret, payload)
```

#### 3. `generate_hmac_base64(secret, data)`

**Purpose:** Generate HMAC-SHA256 signature (Base64-encoded)

```ruby
def generate_hmac_base64(secret, data)
  Base64.strict_encode64(
    OpenSSL::HMAC.digest("SHA256", secret, data)
  )
end
```

**Returns:** Base64 string (44 characters with padding)
**Example:** `"o7TF1u348...=="`

**When to use:** Some providers (Square, PayPal) use Base64 instead of hex encoding.

#### 4. `extract_header(headers, *keys)`

**Purpose:** Case-insensitive header extraction

```ruby
def extract_header(headers, *keys)
  keys.each do |key|
    value = headers[key] || 
            headers[key.downcase] || 
            headers[key.upcase]
    return value if value.present?
  end
  nil
end
```

**Why needed?**
- HTTP headers are case-insensitive per RFC
- Rails normalizes to `Title-Case`
- Some providers send `lowercase` or `UPPERCASE`
- This method tries all variations

**Usage:**
```ruby
# Try multiple possible header names
sig = extract_header(headers, 
  "X-Square-Signature", 
  "X-Square-Hmacsha256-Signature"
)
```

#### 5. `parse_kv_header(header_value)`

**Purpose:** Parse key-value pair headers (e.g., Stripe's signature format)

```ruby
def parse_kv_header(header_value)
  # Input: "t=1609459200,v1=abc123,v0=def456"
  # Output: {"t" => "1609459200", "v1" => ["abc123"], "v0" => ["def456"]}
  
  header_value.split(",").each_with_object({}) do |pair, hash|
    key, value = pair.split("=", 2)
    next if key.blank? || value.blank?
    
    key = key.strip
    value = value.strip
    
    # Handle multiple values for same key
    if hash.key?(key)
      hash[key] = [hash[key]] unless hash[key].is_a?(Array)
      hash[key] << value
    else
      hash[key] = value
    end
  end
end
```

**Handles:**
- Multiple values: `v1=sig1,v1=sig2` → `{"v1" => ["sig1", "sig2"]}`
- Whitespace: `t = 123 , v1 = abc` → `{"t" => "123", "v1" => "abc"}`
- Empty pairs: `t=123,,v1=abc` → Skips empty pair

#### 6. `timestamp_within_tolerance?(timestamp, tolerance)`

**Purpose:** Check if timestamp is within acceptable age

```ruby
def timestamp_within_tolerance?(timestamp, tolerance)
  return false if timestamp.nil?
  
  current_time = Time.current.to_i
  age = (current_time - timestamp).abs  # Absolute value handles future timestamps
  age <= tolerance
end
```

**Tolerates:**
- Old timestamps (within window)
- Future timestamps (clock skew between servers)
- Uses absolute value to handle both directions

**Example:**
```ruby
# Current time: 2024-01-01 12:00:00 (timestamp: 1704110400)
# Tolerance: 300 seconds (5 minutes)

timestamp_within_tolerance?(1704110100, 300)  # 12:05 ago → true
timestamp_within_tolerance?(1704109000, 300)  # 25 min ago → false
timestamp_within_tolerance?(1704110700, 300)  # 5 min future → true
```

#### 7. `parse_timestamp(time_string)`

**Purpose:** Parse various timestamp formats to Unix timestamp

```ruby
def parse_timestamp(time_string)
  return nil if time_string.blank?
  return time_string.to_i if time_string.is_a?(Integer)
  return time_string.to_i if time_string.to_s.match?(/^\d+$/)
  
  # Try parsing as ISO8601/RFC3339
  Time.parse(time_string).to_i
rescue ArgumentError
  nil
end
```

**Handles:**
- Unix timestamps: `1609459200` → `1609459200`
- String integers: `"1609459200"` → `1609459200`
- ISO8601: `"2024-01-01T12:00:00Z"` → `1704110400`
- Invalid formats: Returns `nil` instead of raising

### Example: Complete Adapter Implementation

```ruby
class StripeAdapter
  include CaptainHook::AdapterHelpers

  SIGNATURE_HEADER = "Stripe-Signature"

  def verify_signature(payload:, headers:, provider_config:)
    # 1. Extract signature header
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return false if signature_header.blank?

    # 2. Parse components
    parsed = parse_kv_header(signature_header)
    timestamp = parsed["t"]
    signatures = [parsed["v1"], parsed["v0"]].flatten.compact
    
    return false if timestamp.blank? || signatures.empty?

    # 3. Validate timestamp
    if provider_config.timestamp_validation_enabled?
      tolerance = provider_config.timestamp_tolerance_seconds || 300
      return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
    end

    # 4. Generate expected signature
    signed_payload = "#{timestamp}.#{payload}"
    expected_signature = generate_hmac(
      provider_config.signing_secret, 
      signed_payload
    )

    # 5. Compare signatures (constant-time)
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

---

## Why YAML + Ruby Files

### The Dual-File Pattern

Every provider requires **two files**:
1. **YAML file** (`.yml` or `.yaml`) - Configuration data
2. **Ruby file** (`.rb`) - Adapter implementation (optional if no verification)

This might seem redundant, but there are important architectural reasons.

### Separation of Concerns

**YAML = Data**
- Configuration values
- Provider settings
- No executable code
- Safe to version control
- Easy to read/edit without Ruby knowledge
- Can be parsed without loading Ruby classes

**Ruby = Behavior**
- Signature verification logic
- Data extraction methods
- Provider-specific algorithms
- Requires Ruby knowledge
- Contains executable code

### Why Not Just Ruby?

**Option 1: Everything in Ruby**
```ruby
# BAD: Mixing data and behavior
class StripeProvider
  def self.config
    {
      name: "stripe",
      display_name: "Stripe",
      signing_secret: ENV["STRIPE_SECRET"],
      timestamp_tolerance: 300
    }
  end
  
  def verify_signature(...)
    # ...
  end
end
```

**Problems:**
- Must load Ruby file to read configuration
- Can't scan configs without executing code
- Hard to override settings per environment
- Mixing data and behavior
- Can't use configs without loading adapters
- Dangerous if adapter has errors or side effects

**Option 2: YAML + Ruby (Current Design)**
```yaml
# GOOD: Data in YAML
name: stripe
display_name: Stripe
signing_secret: ENV[STRIPE_SECRET]
timestamp_tolerance_seconds: 300
```

```ruby
# GOOD: Behavior in Ruby
class StripeAdapter
  def verify_signature(...)
    # ...
  end
end
```

**Benefits:**
- Read configuration without loading Ruby
- Scan all providers quickly
- Override configs per environment (dev vs prod)
- Adapter errors don't break provider discovery
- Clear separation of concerns

### From Third-Party Gems

When a gem like `marikit-stripe` provides webhooks:

```
marikit-stripe/
├── lib/
│   └── marikit/
│       └── stripe.rb               # Main gem code (NOT webhook-related)
└── captain_hook/                   # CaptainHook-specific files (scanned)
    └── providers/
        └── stripe/
            ├── stripe.yml          # Webhook config (scanned)
            └── stripe.rb           # Webhook adapter (loaded by CaptainHook)
```

**Important:** The `lib/marikit/stripe.rb` file is the gem's main business logic (API client, payment processing, etc.) and is NOT scanned by CaptainHook. Only files in the `captain_hook/providers/` directory are discovered during provider scanning.

**Why gems need both locations:**

1. **YAML provides defaults**: Gem can ship sensible defaults
2. **Host can override**: Application can create its own `stripe.yml` with environment-specific settings
3. **Adapter is reusable**: Same adapter class works for all instances
4. **Discovery works automatically**: CaptainHook finds gem providers without configuration

**Discovery precedence:**
```
Application YAML > Gem YAML (per source)
```

If both exist, both are discovered with different `source` values. The admin UI shows which source each provider came from.

### Multi-Instance Providers

For multiple instances of the same provider type:

```
captain_hook/providers/
├── stripe_prod/
│   ├── stripe_prod.yml         # adapter_file: stripe_prod.rb
│   └── stripe_prod.rb
├── stripe_test/
│   ├── stripe_test.yml         # adapter_file: stripe_test.rb
│   └── stripe_test.rb
└── stripe_dev/
    ├── stripe_dev.yml          # adapter_file: stripe_dev.rb
    └── stripe_dev.rb
```

Each gets:
- Unique name (`stripe_prod`, `stripe_test`)
- Own YAML configuration
- Own adapter class (or shared adapter with different class name)
- Separate webhook URLs
- Independent settings

### Providers Without Verification

**Since migration 20260117000001**, `adapter_class` can be `NULL`:

```yaml
# captain_hook/providers/internal_service/internal_service.yml
name: internal_service
display_name: Internal Service
# No adapter_file - relies on token-only auth
signing_secret: null  # No HMAC verification
```

**In this case:**
- YAML file is still required (defines provider)
- Ruby file is not needed (no adapter)
- Only token authentication is used
- Suitable for trusted internal services

---

## Scenarios & Limitations (Providers)

### Supported Provider Scenarios

#### ✅ Host Application Providers

```
your-rails-app/
└── captain_hook/
    └── providers/
        └── custom_provider/
            ├── custom_provider.yml
            └── custom_provider.rb
```

**Works:** Fully supported, auto-discovered on scan

#### ✅ Gem-Bundled Providers

```
# Gemfile
gem 'marikit-stripe'

# Inside marikit-stripe gem:
marikit-stripe/
└── captain_hook/
    └── providers/
        └── stripe/
            ├── stripe.yml
            └── stripe.rb
```

**Works:** Auto-discovered from any gem in Gemfile

#### ✅ Multiple Instances (Same Provider Type)

```
captain_hook/providers/
├── stripe_account_a/
│   ├── stripe_account_a.yml    # adapter_file: stripe_account_a.rb
│   └── stripe_account_a.rb
└── stripe_account_b/
    ├── stripe_account_b.yml    # adapter_file: stripe_account_b.rb
    └── stripe_account_b.rb
```

**Works:** Each gets unique name, URL, and configuration

#### ✅ Shared Adapter Class

```
captain_hook/providers/
├── stripe_prod/
│   ├── stripe_prod.yml         # adapter_file: stripe_adapter.rb
│   └── stripe_adapter.rb       # Shared implementation
└── stripe_test/
    └── stripe_test.yml         # adapter_file: ../stripe_prod/stripe_adapter.rb (reuses)
```

**Works:** Multiple providers can reference the same adapter class

#### ✅ No Verification Providers

```yaml
# captain_hook/providers/internal/internal.yml
name: internal
# adapter_file: (not specified - no verification)
```

**Works:** Token-only authentication, no signature verification

#### ✅ ENV-Based Secrets

```yaml
name: stripe
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

**Works:** Resolved at runtime, not stored in database

#### ✅ Mixed Sources (App + Gems)

```
Application:
  captain_hook/providers/custom/custom.yml

Gem 1 (marikit-stripe):
  captain_hook/providers/stripe/stripe.yml

Gem 2 (marikit-square):
  captain_hook/providers/square/square.yml
```

**Works:** All discovered, tracked by `source` field

### Unsupported Provider Scenarios

#### ❌ Database-Only Providers

```ruby
# Cannot create provider without YAML file
Provider.create!(
  name: "custom",
  adapter_file: "custom.rb"
)
# Discovery won't find this on next scan
```

**Limitation:** Providers must have YAML files for persistence

**Workaround:** Create YAML file, then scan

#### ❌ Dynamic Adapter Loading from Gems

```ruby
# In gem: lib/marikit/stripe_adapter.rb
# Trying to use: adapter_class: "Marikit::StripeAdapter"
```

**Limitation:** Adapter must be in `captain_hook/providers/` directory, not `lib/`

**Reason:** Auto-loading looks in specific provider directories

**Workaround:** Put adapter in `captain_hook/providers/stripe/stripe.rb` inside gem

#### ❌ Adapter Without YAML

```
captain_hook/providers/
└── stripe.rb  # No stripe.yml
```

**Limitation:** YAML file is required for discovery

**Reason:** Discovery scans for YAML files, then loads matching Ruby files

**Workaround:** Create minimal YAML file

#### ❌ Remote/HTTP Provider Configs

```yaml
# Not supported
provider_config_url: https://example.com/stripe.yml
```

**Limitation:** Only local file system scanning

**Reason:** Security (executing remote code is dangerous)

**Workaround:** Fetch remotely, save locally, then scan

#### ❌ Provider Names with Special Characters

```yaml
name: stripe-prod  # Invalid (contains hyphen)
name: Stripe Prod  # Invalid (contains space)
name: stripe.prod  # Invalid (contains dot)
```

**Limitation:** Only `^[a-z0-9_]+$` allowed

**Reason:** Used in URLs and as identifiers

**Valid:** `stripe_prod`, `stripe123`, `stripe`

#### ❌ Changing Token After Creation

```ruby
provider = Provider.find_by(name: "stripe")
provider.update!(token: "new-token")
# Old webhook URL is now broken
```

**Limitation:** Token changes break existing webhook configurations

**Reason:** Provider has already configured old URL

**Workaround:** Don't change tokens; create new provider instead

#### ❌ Duplicate Provider Names

```
App:       captain_hook/providers/stripe/stripe.yml
Gem 1:     captain_hook/providers/stripe/stripe.yml
Gem 2:     captain_hook/providers/stripe/stripe.yml
```

**Limitation:** All discovered, but database unique constraint prevents duplicates

**Warning:** Admin UI shows duplicate warning

**Resolution:** Manual intervention required (disable sources or rename)

### Edge Cases

#### Adapter Class Not Found

```yaml
adapter_class: NonExistentAdapter
```

**Behavior:**
- YAML loads successfully
- Provider created in database
- Error when webhook arrives: `AdapterNotFoundError`

**Solution:** Ensure Ruby file defines the adapter class

#### Signing Secret ENV Variable Missing

```yaml
signing_secret: ENV[MISSING_VAR]
```

**Behavior:**
- Provider created successfully
- Signature verification fails (secret is nil)
- Webhooks return 401 Unauthorized

**Solution:** Set environment variable or update YAML

#### Circular Adapter Dependencies

```ruby
# stripe.rb
class StripeAdapter
  def verify_signature(...)
    PaypalAdapter.new.verify_signature(...)  # BAD: Circular
  end
end
```

**Behavior:** Potential infinite loop or load errors

**Solution:** Keep adapters independent

#### Malformed YAML

```yaml
name: stripe
display_name: Stripe
  description: This is indented wrong
```

**Behavior:**
- YAML parsing fails
- Provider not discovered
- Error logged: `Failed to parse provider YAML`

**Solution:** Validate YAML syntax

#### Very Large Payloads

```yaml
max_payload_size_bytes: 10485760  # 10MB
```

**Behavior:**
- Large payloads accepted
- May cause memory issues
- JSON parsing may be slow

**Recommendation:** Keep limit at 1MB unless required

---

## Handlers: Business Logic Execution

### What Are Handlers?

Handlers are **Ruby classes that contain your business logic** for processing webhooks. While providers and adapters handle the security and verification of incoming webhooks, handlers contain the actual application-specific code that runs in response to webhook events.

**Key Concepts:**

- **Separation of Concerns**: Security (adapters) vs. Business Logic (handlers)
- **Event-Driven**: Handlers react to specific event types
- **Asynchronous by Default**: Execute in background jobs for reliability
- **Retryable**: Automatic retry with exponential backoff on failures
- **Priority-Based**: Multiple handlers can process the same event in order

**Example Use Cases:**
- Update payment status when Stripe sends `payment_intent.succeeded`
- Send notification email when Square sends `order.created`
- Sync customer data when PayPal sends `customer.updated`
- Log analytics events for any webhook
- Trigger internal workflows based on external events

### Handler Anatomy

A handler is a simple Ruby class with a single required method: `handle`

```ruby
# captain_hook/handlers/stripe_payment_succeeded_handler.rb
class StripePaymentSucceededHandler
  # Required method signature
  # @param event [CaptainHook::IncomingEvent] Database record of the webhook
  # @param payload [Hash] Parsed JSON payload from provider
  # @param metadata [Hash] Additional metadata (received_at, headers, etc.)
  def handle(event:, payload:, metadata:)
    # Your business logic here
    payment_intent_id = payload.dig("data", "object", "id")
    amount = payload.dig("data", "object", "amount")
    
    # Update your database
    payment = Payment.find_by(stripe_id: payment_intent_id)
    payment&.mark_succeeded!
    
    # Send notifications
    PaymentMailer.success(payment).deliver_later
    
    # Log analytics
    Analytics.track("payment_succeeded", amount: amount)
  end
end
```

**Method Parameters:**

1. **`event`**: The `CaptainHook::IncomingEvent` record
   - `event.id` - UUID of the event
   - `event.provider` - Provider name (e.g., "stripe")
   - `event.event_type` - Event type (e.g., "payment_intent.succeeded")
   - `event.external_id` - Provider's event ID
   - `event.payload` - Full JSON payload
   - `event.created_at` - When CaptainHook received the webhook

2. **`payload`**: Hash of the parsed JSON
   - Already parsed, no need for `JSON.parse`
   - Provider-specific structure
   - Example (Stripe): `payload.dig("data", "object", "id")`

3. **`metadata`**: Additional information
   - `metadata[:received_at]` - ISO8601 timestamp
   - `metadata[:headers]` - HTTP headers (optional)
   - Custom fields you might add

**Handler Responsibilities:**
- Execute business logic quickly (or enqueue more jobs)
- Raise exceptions on errors (triggers automatic retry)
- Be idempotent (same event might be processed multiple times)
- Log important actions for debugging

**Handler Don'ts:**
- Don't do signature verification (already done)
- Don't parse JSON (already parsed)
- Don't handle retries manually (automatic)
- Don't save the event (already saved)

---

## Handler Registration

### Where to Register Handlers

Handlers must be registered in your application's initializer:

```ruby
# config/initializers/captain_hook.rb

CaptainHook.configure do |config|
  # Configuration options here
end

# IMPORTANT: Must be inside after_initialize block
Rails.application.config.after_initialize do
  # Register handlers here
  
  CaptainHook.register_handler(
    provider: "stripe",
    event_type: "payment_intent.succeeded",
    handler_class: "StripePaymentSucceededHandler",
    priority: 100,
    async: true,
    max_attempts: 3,
    retry_delays: [30, 60, 300]
  )
end
```

**Why `after_initialize`?**
- Ensures CaptainHook engine is fully loaded
- Prevents circular dependency issues
- Guarantees handler registry is available
- Required for proper initialization order

### Registration Options

```ruby
CaptainHook.register_handler(
  # REQUIRED FIELDS
  provider: "stripe",                          # Provider name (must match provider)
  event_type: "payment_intent.succeeded",     # Exact event type or wildcard
  handler_class: "StripePaymentSucceededHandler",  # Class name as string
  
  # OPTIONAL FIELDS (with defaults)
  priority: 100,                               # Execution order (lower = higher priority)
  async: true,                                 # Run in background job (true) or synchronously (false)
  max_attempts: 5,                             # Maximum retry attempts
  retry_delays: [30, 60, 300, 900, 3600]      # Delays between retries (seconds)
)
```

**Field Details:**

**`provider`** (String, required)
- Must match an existing provider name exactly
- Case-sensitive
- Example: `"stripe"`, `"square"`, `"paypal"`

**`event_type`** (String, required)
- Exact event type: `"payment_intent.succeeded"`
- Wildcard patterns: `"payment_intent.*"` (matches all payment_intent events)
- Wildcards use glob matching patterns
- Note: Wildcard matching is currently planned but not fully implemented

**`handler_class`** (String, required)
- Class name as a string (not the actual class)
- Must be loadable via `constantize`
- Example: `"StripePaymentSucceededHandler"`
- Can include namespaces: `"Webhooks::Stripe::PaymentHandler"`

**`priority`** (Integer, default: 100)
- Determines execution order when multiple handlers exist
- Lower numbers = higher priority (execute first)
- Example: priority 10 runs before priority 100
- Handlers with same priority are sorted by class name (alphabetically)

**`async`** (Boolean, default: true)
- `true`: Execute in background job (recommended)
- `false`: Execute synchronously (blocks webhook response)
- Synchronous handlers should be fast (<100ms)
- Async handlers can take minutes (with retries)

**`max_attempts`** (Integer, default: 5)
- Maximum number of execution attempts
- Includes initial attempt + retries
- Example: max_attempts=3 means 1 initial + 2 retries
- After max attempts, handler is marked as "failed"

**`retry_delays`** (Array of Integers, default: [30, 60, 300, 900, 3600])
- Delays in seconds between retry attempts
- Array position = attempt number (0-indexed for retries)
- Example: `[30, 60, 300]` means:
  - After 1st failure: wait 30 seconds
  - After 2nd failure: wait 60 seconds
  - After 3rd failure: wait 300 seconds
- If more attempts than delays, uses last delay value

### Multiple Handlers for One Event

You can register multiple handlers for the same event:

```ruby
# High priority: Update database (runs first)
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "UpdatePaymentHandler",
  priority: 10
)

# Medium priority: Send notification
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "PaymentNotificationHandler",
  priority: 50
)

# Low priority: Analytics (runs last)
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "PaymentAnalyticsHandler",
  priority: 100
)
```

**Execution Order:**
1. `UpdatePaymentHandler` (priority 10)
2. `PaymentNotificationHandler` (priority 50)
3. `PaymentAnalyticsHandler` (priority 100)

**Independence:**
- Each handler runs independently
- If one fails, others still execute
- Each has its own retry logic
- Failures don't cascade

### Wildcard Event Types

Register a single handler for multiple event types:

```ruby
# Handle all payment_intent events
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.*",
  handler_class: "StripePaymentIntentHandler"
)

# Handle all Square bank account events
CaptainHook.register_handler(
  provider: "square",
  event_type: "bank_account.*",
  handler_class: "SquareBankAccountHandler"
)
```

**Handler Implementation:**

```ruby
class StripePaymentIntentHandler
  def handle(event:, payload:, metadata:)
    # Check actual event type
    case event.event_type
    when "payment_intent.succeeded"
      handle_success(payload)
    when "payment_intent.failed"
      handle_failure(payload)
    when "payment_intent.canceled"
      handle_cancellation(payload)
    end
  end
  
  private
  
  def handle_success(payload)
    # Success logic
  end
  
  def handle_failure(payload)
    # Failure logic
  end
  
  def handle_cancellation(payload)
    # Cancellation logic
  end
end
```

**Note:** Wildcard matching is registered in the HandlerRegistry but full glob-pattern matching in event lookups is not yet fully implemented. Currently, exact matches work reliably.

---

## Handler Discovery & Sync

### The Two-Phase System

CaptainHook uses a **hybrid approach** for handler management:

1. **In-Memory Registry** (`HandlerRegistry`)
   - Handlers registered at application startup
   - Stored in memory (RAM)
   - Fast lookups during webhook processing
   - Cleared on application restart

2. **Database Storage** (`captain_hook_handlers` table)
   - Persistent storage of handler configurations
   - Synced from registry during provider scans
   - Visible in admin UI
   - Editable via admin interface
   - Survives application restarts

**Why Both?**

- **Registry** = Fast runtime lookups (milliseconds)
- **Database** = Persistent configuration + Admin UI
- **Sync Process** = Keeps them in sync

### Handler Discovery Process

Discovery happens when you click "Scan for Providers" or "Scan Handlers" in admin UI:

#### Step 1: Registry Inspection

```ruby
# lib/captain_hook/services/handler_discovery.rb

registry = CaptainHook.handler_registry

# Access internal registry structure
registry.instance_variable_get(:@registry).each do |key, configs|
  provider, event_type = key.split(":", 2)
  
  configs.each do |config|
    discovered_handlers << {
      "provider" => provider,
      "event_type" => event_type,
      "handler_class" => config.handler_class.to_s,
      "async" => config.async,
      "max_attempts" => config.max_attempts,
      "priority" => config.priority,
      "retry_delays" => config.retry_delays
    }
  end
end
```

**What's Discovered:**
- All handlers registered via `CaptainHook.register_handler`
- From main application's initializer
- From gems' initializers (if they register handlers)

**Not Discovered:**
- Handlers in the database but not in registry
- Handlers that were registered after initialization
- Commented-out handler registrations

#### Step 2: Provider Matching

For each discovered handler:

```ruby
provider = definition["provider"]

# Check if provider exists in database
db_provider = CaptainHook::Provider.find_by(name: provider)

if db_provider.nil?
  # Handler registered for non-existent provider
  # Skipped or error logged
end
```

**Critical Behavior: Duplicate Provider Names**

If multiple providers have the same name (from different sources):

```
Application:  captain_hook/providers/stripe/stripe.yml
Gem 1:        captain_hook/providers/stripe/stripe.yml
```

**What Happens:**
1. Both YAML files are discovered (different `source` values)
2. Only ONE provider record is created (database unique constraint on `name`)
3. **Handlers are registered to whichever provider exists in the database**
4. Admin UI shows warning about duplicate provider definitions

**Example Scenario:**

```ruby
# In your app initializer
CaptainHook.register_handler(
  provider: "stripe",          # Matches provider name
  event_type: "payment_intent.succeeded",
  handler_class: "AppPaymentHandler"
)

# In gem initializer (e.g., marikit-stripe)
CaptainHook.register_handler(
  provider: "stripe",          # Same provider name
  event_type: "charge.succeeded",
  handler_class: "MariKit::ChargeHandler"
)
```

**Result:**
- Both handlers registered to the same `stripe` provider
- Provider settings come from whichever was created first
- All handlers for "stripe" will work
- No conflicts, handlers are independent

**Best Practice:**
- Use unique provider names if you need separate configurations
- Example: `"stripe_app"` vs `"stripe_gem"`
- Or use same name intentionally to share one provider

#### Step 3: Database Synchronization

```ruby
# lib/captain_hook/services/handler_sync.rb

handler_definitions.each do |definition|
  provider = definition["provider"]
  event_type = definition["event_type"]
  handler_class = definition["handler_class"]
  
  # Find existing handler by unique key
  handler = Handler.find_by(
    provider: provider,
    event_type: event_type,
    handler_class: handler_class
  )
  
  # Check if soft-deleted
  if handler&.deleted?
    # SKIP - User manually deleted this handler
    next
  end
  
  # Create or update handler
  if handler
    handler.update!(definition)  # Update if changed
  else
    Handler.create!(definition)   # Create new
  end
end
```

**Sync Modes:**

1. **Discover New** (default):
   - Creates handlers that don't exist
   - Skips existing handlers (doesn't update)
   - Safe for adding new handlers

2. **Full Sync**:
   - Creates new handlers
   - Updates existing handlers with registry values
   - Overwrites database configuration

**Soft Delete Protection:**

If a handler has `deleted_at` timestamp:
- It's skipped during sync
- Won't be re-created automatically
- User must manually restore via admin UI or delete the timestamp

This prevents:
- Unwanted handler re-addition
- Sync overriding manual deletions
- Forcing users to comment out code

### Where Handlers Live

Handlers can exist in two locations:

#### Option 1: Host Application

```
your-rails-app/
├── captain_hook/
│   └── handlers/
│       ├── stripe_payment_succeeded_handler.rb
│       ├── square_order_created_handler.rb
│       └── paypal_payment_captured_handler.rb
└── config/
    └── initializers/
        └── captain_hook.rb    # Register handlers here
```

**Recommended structure:**
- Handlers in `captain_hook/handlers/` (keeps webhook code together)
- Can also use `app/handlers/` (standard Rails location)

#### Option 2: Third-Party Gems

```
marikit-stripe/
├── lib/
│   └── marikit/
│       └── stripe/
│           └── handlers/
│               ├── charge_handler.rb
│               └── payment_intent_handler.rb
├── captain_hook/
│   └── providers/
│       └── stripe/
│           ├── stripe.yml
│           └── stripe.rb
└── lib/
    └── marikit/
        └── stripe/
            └── engine.rb    # Register handlers in initializer
```

**Gem Registration:**

```ruby
# marikit-stripe/lib/marikit/stripe/engine.rb

module MariKit
  module Stripe
    class Engine < ::Rails::Engine
      initializer "marikit.stripe.register_handlers" do
        Rails.application.config.after_initialize do
          CaptainHook.register_handler(
            provider: "stripe",
            event_type: "charge.succeeded",
            handler_class: "MariKit::Stripe::ChargeHandler"
          )
        end
      end
    end
  end
end
```

**Loading Handlers from Gems:**

Handler classes must be autoloadable:

```ruby
# Option 1: Standard autoload paths
# marikit-stripe/app/handlers/mari_kit/stripe/charge_handler.rb
module MariKit
  module Stripe
    class ChargeHandler
      def handle(event:, payload:, metadata:)
        # ...
      end
    end
  end
end

# Option 2: Manual require in gem
# marikit-stripe/lib/marikit/stripe.rb
require "marikit/stripe/handlers/charge_handler"
```

### Handler Discovery from Gems

**How It Works:**

1. Gem defines initializer with `register_handler` calls
2. Initializer runs during Rails startup
3. Handlers added to in-memory registry
4. User clicks "Scan Handlers" in admin UI
5. Discovery service reads from registry
6. Handlers synced to database

**Example: Full Gem Integration**

```ruby
# marikit-stripe/lib/marikit/stripe/engine.rb

module MariKit
  module Stripe
    class Engine < ::Rails::Engine
      isolate_namespace MariKit::Stripe
      
      initializer "marikit.stripe.register_handlers", after: :load_config_initializers do
        Rails.application.config.after_initialize do
          # Register multiple handlers
          [
            { event: "charge.succeeded", handler: "MariKit::Stripe::ChargeSucceededHandler" },
            { event: "charge.failed", handler: "MariKit::Stripe::ChargeFailedHandler" },
            { event: "payment_intent.*", handler: "MariKit::Stripe::PaymentIntentHandler" }
          ].each do |config|
            CaptainHook.register_handler(
              provider: "stripe",
              event_type: config[:event],
              handler_class: config[:handler],
              priority: 100,
              async: true
            )
          end
        end
      end
    end
  end
end
```

**Host Application Override:**

App can override gem handler behavior:

```ruby
# config/initializers/captain_hook.rb

Rails.application.config.after_initialize do
  # Override gem's handler with your own
  CaptainHook.register_handler(
    provider: "stripe",
    event_type: "charge.succeeded",
    handler_class: "CustomChargeHandler",  # Your custom handler
    priority: 10  # Higher priority than gem's handler
  )
end
```

Both handlers will execute (gem's and yours), prioritized by priority value.

---

## Handler Table Schema

### Table: `captain_hook_handlers`

```sql
CREATE TABLE captain_hook_handlers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Handler identification (unique together)
  provider VARCHAR NOT NULL,              -- Provider name (matches providers.name)
  event_type VARCHAR NOT NULL,            -- Event type (exact or wildcard pattern)
  handler_class VARCHAR NOT NULL,         -- Handler class name
  
  -- Execution configuration
  async BOOLEAN NOT NULL DEFAULT true,    -- Background job (true) or synchronous (false)
  priority INTEGER NOT NULL DEFAULT 100,  -- Execution order (lower = higher priority)
  
  -- Retry configuration
  max_attempts INTEGER NOT NULL DEFAULT 5,                -- Maximum retry attempts
  retry_delays JSONB NOT NULL DEFAULT '[30,60,300,900,3600]',  -- Delay array in seconds
  
  -- Soft delete
  deleted_at TIMESTAMP,                   -- Soft delete timestamp
  
  -- Timestamps
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  
  -- Unique constraint
  CONSTRAINT idx_captain_hook_handlers_unique 
    UNIQUE (provider, event_type, handler_class)
);

-- Indexes
CREATE INDEX idx_captain_hook_handlers_provider ON captain_hook_handlers(provider);
CREATE INDEX idx_captain_hook_handlers_deleted_at ON captain_hook_handlers(deleted_at);
```

### Column Explanations

#### Identification Columns

**`provider`** (VARCHAR, NOT NULL)
- Provider name this handler responds to
- Must match an existing provider's `name` field
- Example: `"stripe"`, `"square"`, `"paypal"`
- Case-sensitive
- Part of unique constraint

**`event_type`** (VARCHAR, NOT NULL)
- Event type this handler processes
- Exact match: `"payment_intent.succeeded"`
- Wildcard pattern: `"payment_intent.*"` (planned feature)
- Provider-specific format
- Part of unique constraint

**`handler_class`** (VARCHAR, NOT NULL)
- Fully-qualified class name as string
- Must be loadable via `"ClassName".constantize`
- Example: `"StripePaymentSucceededHandler"`
- Can include modules: `"Webhooks::StripePaymentHandler"`
- Part of unique constraint

**Unique Constraint**: `(provider, event_type, handler_class)`
- Prevents duplicate handler registrations
- Same handler can't be registered twice for same provider+event
- Different handlers can process same event (multi-handler support)

#### Configuration Columns

**`async`** (BOOLEAN, NOT NULL, DEFAULT true)
- **true**: Execute in background job (via `IncomingHandlerJob`)
- **false**: Execute synchronously (blocks webhook response)

**When to use sync (false):**
- Very fast operations (<50ms)
- Need immediate response to provider
- Side-effect-free operations
- Testing/debugging

**When to use async (true):**
- Database writes
- External API calls
- Email sending
- Any operation >50ms
- Most production handlers

**`priority`** (INTEGER, NOT NULL, DEFAULT 100)
- Determines execution order among multiple handlers
- Lower number = higher priority (executes first)
- Range: typically 1-1000
- Default: 100 (medium priority)

**Example priorities:**
- `1-10`: Critical handlers (payment updates, order creation)
- `50-100`: Normal handlers (notifications, logging)
- `500-1000`: Low priority (analytics, cleanup)

**`max_attempts`** (INTEGER, NOT NULL, DEFAULT 5)
- Maximum execution attempts (initial + retries)
- Must be > 0
- Example: `max_attempts: 3` = 1 try + 2 retries
- After exhaustion, handler marked as "failed"

**`retry_delays`** (JSONB, NOT NULL, DEFAULT [30, 60, 300, 900, 3600])
- Array of integers representing seconds between retries
- Index corresponds to retry attempt (0-based)
- Example: `[30, 60, 300]`
  - After 1st failure: wait 30 seconds before retry
  - After 2nd failure: wait 60 seconds before retry
  - After 3rd failure: wait 300 seconds before retry
- If attempts exceed array length, uses last value
- Implements exponential backoff pattern

**Typical patterns:**
```json
[30, 60, 300, 900, 3600]        // Conservative: 30s, 1m, 5m, 15m, 1h
[10, 30, 60, 120]                // Aggressive: 10s, 30s, 1m, 2m
[60, 300, 1800]                  // Slow: 1m, 5m, 30m
```

#### State Management

**`deleted_at`** (TIMESTAMP, NULLABLE)
- Soft delete timestamp
- `NULL` = active handler
- `NOT NULL` = soft-deleted handler
- Soft-deleted handlers:
  - Not visible in admin UI by default
  - Skipped during handler sync
  - Won't be auto-recreated
  - Can be restored by setting to `NULL`

**Why soft delete?**
- Prevents unwanted re-creation during sync
- Preserves handler history
- Allows restoration if needed
- User intent is preserved

---

## Handler Execution Flow

### Complete Handler Lifecycle

When a webhook arrives and creates an `IncomingEvent`, here's the handler execution process:

### 1. Handler Record Creation

After event is saved to database:

```ruby
# app/controllers/captain_hook/incoming_controller.rb

if event.previously_new_record?
  # New event - create handler execution records
  create_handlers_for_event(event)
end

def create_handlers_for_event(event)
  # Lookup handlers from in-memory registry
  handler_configs = CaptainHook.handler_registry.handlers_for(
    provider: event.provider,
    event_type: event.event_type
  )
  
  # Create execution record for each handler
  handler_configs.each do |config|
    handler = event.incoming_event_handlers.create!(
      handler_class: config.handler_class.to_s,
      status: :pending,
      priority: config.priority,
      attempt_count: 0
    )
    
    # Enqueue job
    if config.async
      CaptainHook::IncomingHandlerJob.perform_later(handler.id)
    else
      CaptainHook::IncomingHandlerJob.new.perform(handler.id)
    end
  end
end
```

**Key points:**
- Uses in-memory registry for fast lookup
- Creates one `IncomingEventHandler` record per handler
- Immediate job enqueue for async handlers
- Synchronous execution for sync handlers

### 2. Job Enqueueing

```ruby
# Async handler
CaptainHook::IncomingHandlerJob.perform_later(handler.id)
# => Queued to :captain_hook_incoming queue
# => Processed by background job worker (Sidekiq, Delayed Job, etc.)

# Sync handler
CaptainHook::IncomingHandlerJob.new.perform(handler.id)
# => Executes immediately in web process
# => Blocks webhook response until complete
```

**Queue**: `:captain_hook_incoming`
- Can be customized in job class
- Allows priority queue management
- Separate from application jobs

### 3. Lock Acquisition (Optimistic Locking)

Job attempts to acquire lock on handler record:

```ruby
# app/jobs/captain_hook/incoming_handler_job.rb

def perform(handler_id, worker_id: SecureRandom.uuid)
  handler = IncomingEventHandler.find(handler_id)
  
  # Try to acquire lock
  return unless handler.acquire_lock!(worker_id)
  
  # Continue processing...
end

# app/models/captain_hook/incoming_event_handler.rb

def acquire_lock!(worker_id)
  update!(
    locked_at: Time.current,
    locked_by: worker_id,
    status: :processing
  )
rescue ActiveRecord::StaleObjectError
  # Someone else got the lock first
  false
end
```

**Optimistic Locking:**
- Uses `lock_version` column (auto-incremented)
- Prevents concurrent execution
- If two workers try simultaneously, only one succeeds
- Other worker silently exits (job succeeds without work)

**Why needed?**
- Multiple job workers might grab same job
- Prevents duplicate processing
- Ensures exactly-once execution
- Race condition protection

### 4. Handler Lookup

Retrieve handler configuration from registry:

```ruby
handler_config = CaptainHook.handler_registry.find_handler_config(
  provider: event.provider,
  event_type: event.event_type,
  handler_class: handler.handler_class
)
```

**Fallback behavior:**
- If not in registry: Job exits silently
- Handler might have been unregistered
- Or application restarted without re-registering

### 5. Handler Execution

```ruby
begin
  # Increment attempt counter
  handler.increment_attempts!
  
  # Load and instantiate handler class
  handler_class = handler.handler_class.constantize
  handler_instance = handler_class.new
  
  # Execute handle method
  handler_instance.handle(
    event: event,
    payload: event.payload,
    metadata: event.metadata
  )
  
  # Mark as successful
  handler.mark_processed!
  
  # Update event status
  event.recalculate_status!
  
rescue StandardError => e
  # Handle failure (see next section)
end
```

**Instrumentation:**
- Start event: `handler_started`
- Success event: `handler_completed` (with duration)
- Failure event: `handler_failed` (with error)

### 6. Failure Handling

```ruby
rescue StandardError => e
  # Mark handler as failed
  handler.mark_failed!(e)
  
  # Check if retries exhausted
  if handler.max_attempts_reached?(handler_config.max_attempts)
    # No more retries
    event.recalculate_status!
  else
    # Schedule retry
    delay = handler_config.delay_for_attempt(handler.attempt_count)
    handler.reset_for_retry!
    
    # Enqueue retry job
    self.class.set(wait: delay.seconds).perform_later(
      handler_id, 
      worker_id: SecureRandom.uuid
    )
  end
  
  # Re-raise exception (marks job as failed)
  raise
end
```

**Retry Logic:**

1. **Mark as failed**: Status set to `failed`, error message saved
2. **Check attempts**: Compare `attempt_count` vs `max_attempts`
3. **Calculate delay**: Use `retry_delays` array, fallback to last value
4. **Reset for retry**: Status back to `pending`, lock released
5. **Schedule retry job**: Use `set(wait: X)` for delayed execution

**Example retry timeline:**
```
Attempt 1: Now          -> Fails -> Wait 30s
Attempt 2: +30s         -> Fails -> Wait 60s
Attempt 3: +90s         -> Fails -> Wait 300s
Attempt 4: +390s        -> Fails -> Wait 900s
Attempt 5: +1290s       -> Fails -> No more retries (max_attempts: 5)
```

### 7. Event Status Recalculation

```ruby
event.recalculate_status!
```

Updates `IncomingEvent.status` based on all handler statuses:

```ruby
# app/models/captain_hook/incoming_event.rb

def recalculate_status!
  return if incoming_event_handlers.empty?
  
  if incoming_event_handlers.all?(&:status_processed?)
    update!(status: :processed)
  elsif incoming_event_handlers.any?(&:status_failed?)
    update!(status: :failed)
  elsif incoming_event_handlers.any?(&:status_processing?)
    update!(status: :processing)
  else
    update!(status: :received)
  end
end
```

**Status meanings:**
- `received`: Event created, handlers not yet started
- `processing`: At least one handler is running
- `processed`: All handlers succeeded
- `failed`: At least one handler exhausted retries

### Complete Flow Diagram

```
Webhook Arrives
    ↓
Event Created (IncomingEvent)
    ↓
Create Handler Records (IncomingEventHandler)
    ↓
┌─────────────────────┬─────────────────────┐
│  Async Handler      │  Sync Handler       │
│  Job Enqueued       │  Execute Now        │
│  Background Worker  │  In Web Process     │
└──────────┬──────────┴──────────┬──────────┘
           ↓                     ↓
      Try Acquire Lock    Try Acquire Lock
           ↓                     ↓
      Got Lock?            Got Lock?
      Yes │   No (Exit)    Yes │   No (Exit)
          ↓                    ↓
    Load Handler Config   Load Handler Config
          ↓                    ↓
    Increment Attempts    Increment Attempts
          ↓                    ↓
    Execute handle()      Execute handle()
          ↓                    ↓
    ┌─────┴─────┐        ┌─────┴─────┐
    │           │        │           │
  Success    Failure   Success    Failure
    │           │        │           │
    ↓           ↓        ↓           ↓
Mark         Mark      Mark        Mark
Processed    Failed    Processed   Failed
    │           │        │           │
    ↓           ↓        ↓           ↓
Release      Check     Release     Check
Lock         Retries   Lock        Retries
    │           │        │           │
    └──────┬────┴────────┴─────┬─────┘
           ↓                   ↓
    Recalculate          Schedule Retry
    Event Status         (if attempts remain)
           │                   │
           └─────────┬─────────┘
                     ↓
              Job Complete
```

---

## Handler Scenarios & Limitations

### Supported Scenarios

#### ✅ Multiple Handlers Per Event

```ruby
# All three handlers execute for payment_intent.succeeded
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "PaymentUpdateHandler",
  priority: 10
)

CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "NotificationHandler",
  priority: 50
)

CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "AnalyticsHandler",
  priority: 100
)
```

**Works:** All three execute independently in priority order

#### ✅ Handlers in Host Application

```
app/
└── captain_hook/
    └── handlers/
        └── my_handler.rb

config/initializers/captain_hook.rb:
  CaptainHook.register_handler(...)
```

**Works:** Standard pattern, fully supported

#### ✅ Handlers in Gems

```ruby
# in gem's engine.rb
Rails.application.config.after_initialize do
  CaptainHook.register_handler(
    provider: "stripe",
    event_type: "charge.succeeded",
    handler_class: "GemNamespace::ChargeHandler"
  )
end
```

**Works:** Gem handlers discovered and synced

#### ✅ Mix of Sync and Async Handlers

```ruby
# Fast sync handler (updates cache)
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "CacheUpdateHandler",
  async: false  # Synchronous
)

# Slow async handler (emails)
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "EmailHandler",
  async: true  # Asynchronous
)
```

**Works:** Sync executes immediately, async queues to background

#### ✅ Duplicate Provider Names (Handlers Register to Database Provider)

```
Application: captain_hook/providers/stripe/stripe.yml
Gem:         captain_hook/providers/stripe/stripe.yml

# In app initializer
CaptainHook.register_handler(provider: "stripe", ...)

# In gem initializer
CaptainHook.register_handler(provider: "stripe", ...)
```

**Works:**
- Both handlers registered to same provider
- Provider configuration from whichever was created first
- Both handlers execute for stripe webhooks
- No conflicts

#### ✅ Wildcard Event Types (Registered)

```ruby
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.*",  # Wildcard
  handler_class: "PaymentIntentHandler"
)
```

**Works (Partially):**
- Handler registered successfully
- Stored in registry and database
- **Note:** Full wildcard matching in event lookups not yet implemented
- Exact matches work reliably

#### ✅ Idempotent Handlers

```ruby
class IdempotentPaymentHandler
  def handle(event:, payload:, metadata:)
    payment_id = payload.dig("data", "object", "id")
    
    # Idempotent operation (safe to repeat)
    payment = Payment.find_or_create_by(stripe_id: payment_id)
    payment.update(status: "succeeded")  # Safe to repeat
  end
end
```

**Works:** Recommended pattern for production handlers

#### ✅ Handler Soft Delete

```ruby
# Via admin UI or directly
handler = CaptainHook::Handler.find_by(handler_class: "UnwantedHandler")
handler.soft_delete!

# Later: Scan handlers
# Handler won't be re-created
```

**Works:** User deletions are respected during sync

### Unsupported Scenarios

#### ❌ Runtime Handler Registration

```ruby
# Inside controller or model
class WebhooksController < ApplicationController
  def create
    CaptainHook.register_handler(...)  # BAD
  end
end
```

**Limitation:** Handlers must be registered during initialization

**Reason:** Registry used for fast lookups, not dynamic

**Workaround:** Use database to enable/disable handlers, not runtime registration

#### ❌ Handler Without Provider

```ruby
CaptainHook.register_handler(
  provider: "nonexistent",  # Provider doesn't exist
  event_type: "some.event",
  handler_class: "MyHandler"
)
```

**Limitation:** Handler appears in registry but won't execute

**Reason:** Provider lookup happens first, webhook rejected before handlers

**Workaround:** Create provider first, then register handler

#### ❌ Handlers Modifying Request/Response

```ruby
class BadHandler
  def handle(event:, payload:, metadata:)
    # Can't access HTTP request
    # Can't modify HTTP response
    # Can't send custom response codes
  end
end
```

**Limitation:** Handlers run after webhook response sent

**Reason:** Async execution, webhook already returned 201 Created

**Workaround:** Use controller hooks if you need request/response access

#### ❌ Handler Return Values

```ruby
class BadHandler
  def handle(event:, payload:, metadata:)
    return { status: "success", data: { ... } }  # Ignored
  end
end
```

**Limitation:** Return values are ignored

**Reason:** Handlers run asynchronously, no caller to receive values

**Workaround:** Update database, raise exceptions for failures

#### ❌ Ordered Execution Guarantee Across Async Handlers

```ruby
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "Handler1",
  priority: 10,
  async: true  # Background job
)

CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "Handler2",
  priority: 20,
  async: true  # Background job
)
```

**Limitation:** Handler2 might execute before Handler1 completes

**Reason:** Both enqueued immediately, job workers process in parallel

**Workaround:** 
- Use synchronous handlers for ordering guarantee
- Or make handlers independent
- Or use job dependencies (Sidekiq Pro, Active Job)

#### ❌ Sharing State Between Handlers

```ruby
class Handler1
  def handle(event:, payload:, metadata:)
    @shared_data = "value"  # Instance variable
  end
end

class Handler2
  def handle(event:, payload:, metadata:)
    puts @shared_data  # Won't see Handler1's value
  end
end
```

**Limitation:** Handlers are separate instances, separate processes

**Reason:** Each handler instantiated independently

**Workaround:** Use database, Redis, or event metadata to share data

#### ❌ Wildcard Full Matching (Not Yet Implemented)

```ruby
# Registered
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.*",
  handler_class: "WildcardHandler"
)

# Incoming webhook
event_type = "payment_intent.succeeded"
```

**Limitation:** Wildcard handler might not match incoming event

**Reason:** Full glob pattern matching not implemented yet

**Current State:** Exact matches work, wildcards stored but not fully functional

**Workaround:** Register handlers for each specific event type

#### ❌ Handler Discovery from Database Only

```ruby
# Database has handler
CaptainHook::Handler.create!(
  provider: "stripe",
  event_type: "charge.succeeded",
  handler_class: "ChargeHandler"
)

# But not registered in initializer
# Handler won't execute
```

**Limitation:** Handlers must be in registry to execute

**Reason:** Lookup uses in-memory registry for performance

**Workaround:** Always register in initializer, database is for admin UI

#### ❌ Conditional Handler Execution

```ruby
class ConditionalHandler
  def handle(event:, payload:, metadata:)
    # Want: Only execute if certain condition
    return if some_condition?  # Handler still marked as "processed"
    
    # Do work...
  end
end
```

**Limitation:** Early return still counts as success

**Reason:** No exception raised = success

**Workaround:** Raise custom exception to trigger retry, or use status tracking

### Edge Cases

#### Handler Class Not Found

```ruby
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment.succeeded",
  handler_class: "NonExistentHandler"  # Class doesn't exist
)
```

**Behavior:**
- Registration succeeds (string stored)
- Handler record created in database
- Job fails when attempting to constantize
- Error: `NameError: uninitialized constant NonExistentHandler`
- Job retries according to retry config

**Solution:** Ensure handler class exists and is loadable

#### Handler Raises Exception

```ruby
class FailingHandler
  def handle(event:, payload:, metadata:)
    raise StandardError, "Something went wrong"
  end
end
```

**Behavior:**
- Exception caught by job
- Handler marked as failed
- Error message saved
- Retry scheduled automatically
- After max_attempts, stays failed

**Intentional:** Exceptions trigger retry mechanism

#### Very Long Handler Execution

```ruby
class SlowHandler
  def handle(event:, payload:, metadata:)
    sleep(600)  # 10 minutes
  end
end
```

**Behavior:**
- Job worker occupied for 10 minutes
- Might timeout (depends on job backend)
- Other handlers delayed (if limited workers)

**Recommendation:** Break into smaller jobs or use separate queue

#### Database Lock Contention

```ruby
# Two handlers updating same record
class Handler1
  def handle(event:, payload:, metadata:)
    order = Order.find(123)
    order.lock!  # Acquire row lock
    order.update(status: "processed")
  end
end

class Handler2
  def handle(event:, payload:, metadata:)
    order = Order.find(123)
    order.lock!  # Blocks waiting for Handler1
    order.update(notes: "Updated")
  end
end
```

**Behavior:**
- Handler2 blocks waiting for Handler1's lock
- Might timeout
- Could cause deadlocks

**Solution:** Design handlers to be lock-independent

#### Handler Execution Order vs Priority

```ruby
# Both handlers for same event
CaptainHook.register_handler(..., handler_class: "A", priority: 100)
CaptainHook.register_handler(..., handler_class: "Z", priority: 100)
```

**Behavior:**
- Same priority = sorted by class name alphabetically
- "A" executes before "Z" (deterministic)
- Ensures consistent ordering

#### Memory Leaks in Handlers

```ruby
class LeakyHandler
  @@data = []  # Class variable
  
  def handle(event:, payload:, metadata:)
    @@data << payload  # Accumulates in memory
  end
end
```

**Behavior:**
- Memory grows with each execution
- Job worker memory bloat
- Eventually crashes

**Solution:** Avoid class variables, use instance variables

---

## Summary

### Key Takeaways (Providers & Handlers)

**Providers:**
1. **Discovery is file-based**: Providers must exist as YAML files in `captain_hook/providers/`
2. **Dual files serve different purposes**: YAML = configuration (required), Ruby = behavior (optional)
3. **Security is layered**: Token authentication, signature verification, timestamp validation, rate limiting
4. **Adapters are isolated**: Each provider's adapter is self-contained with verification logic
5. **Idempotency is automatic**: Same webhook won't be processed twice

**Handlers:**
1. **Business logic layer**: Handlers contain your application-specific webhook processing code
2. **Registry + Database**: Hybrid system for fast lookups and persistent configuration
3. **Async by default**: Background jobs with retry logic ensure reliability
4. **Multiple handlers supported**: Same event can trigger multiple independent handlers
5. **Priority-based execution**: Control handler order with priority values
6. **Soft delete protection**: User deletions respected during sync
7. **Gem integration**: Handlers can come from host app or third-party gems
8. **Duplicate providers**: Handlers register to existing provider, regardless of source

**Critical Design Decisions:**

- **Why two tables?** `providers` for webhook reception, `handlers` for configuration management
- **Why registry + database?** Fast runtime lookups + admin UI management
- **Why soft delete?** Respect user intent, prevent unwanted re-creation
- **Why provider matching?** Handlers can't exist without providers
- **Why job-based execution?** Reliability, retries, and non-blocking webhook responses

### Why Database Storage for Handlers?

**The Problem:** In-memory registry alone isn't enough

**Reasons for database persistence:**

1. **Admin UI Management**
   - View all registered handlers
   - Edit handler configuration (priority, retries, async)
   - Enable/disable handlers without code changes
   - See handler execution history

2. **Configuration Flexibility**
   - Change retry delays without redeploying
   - Adjust priorities based on production needs
   - Toggle async/sync per environment

3. **User Control**
   - Soft delete to remove unwanted handlers
   - Deletions persist across deployments
   - Override gem defaults

4. **Visibility**
   - See what handlers are active
   - Track which handlers exist per provider
   - Audit handler configurations

5. **Consistency**
   - Single source of truth after sync
   - Configuration survives restarts
   - Platform-independent storage

**Why not database only?**

- **Performance**: Registry lookups are O(1) in memory vs database query
- **Webhook speed**: Can't afford database roundtrip for every webhook
- **Reliability**: Works even if database is slow

**Best of both worlds:**
- **Registry** for runtime (speed)
- **Database** for management (flexibility)
- **Sync** keeps them aligned

### Complete Data Flow

```
1. Developer writes handler class
   ↓
2. Developer registers in initializer
   ↓
3. Application starts, registry populated
   ↓
4. Admin clicks "Scan Handlers"
   ↓
5. Discovery reads from registry
   ↓
6. Sync writes to database
   ↓
7. Admin UI shows handlers
   ↓
8. Webhook arrives
   ↓
9. Registry lookup (fast)
   ↓
10. Handler execution record created
   ↓
11. Job enqueued
   ↓
12. Handler executes
   ↓
13. Success/failure tracked in database
```

### References

- [Provider Discovery Documentation](docs/PROVIDER_DISCOVERY.md)
- [Adapter Implementation Guide](docs/ADAPTERS.md)
- [Handler Management Guide](docs/HANDLER_MANAGEMENT.md)
- [Setting Up Webhooks in Gems](docs/GEM_WEBHOOK_SETUP.md)
- [Signing Secret Storage](docs/SIGNING_SECRET_STORAGE.md)

---

## Summary

### Key Takeaways

1. **Discovery is file-based**: Providers must exist as YAML files in `captain_hook/providers/`

2. **Dual files serve different purposes**: 
   - YAML = configuration (required)
   - Ruby = behavior (optional)

3. **Security is layered**:
   - Token authentication (always)
   - Signature verification (optional, via adapter)
   - Timestamp validation (optional)
   - Rate limiting (optional)
   - Payload size limits (optional)

4. **Adapters are isolated**: Each provider's adapter is self-contained with verification logic

5. **Idempotency is automatic**: Same webhook won't be processed twice

6. **Flexibility by design**: Can mix app providers, gem providers, and multiple instances

### References

- [Provider Discovery Documentation](docs/PROVIDER_DISCOVERY.md)
- [Adapter Implementation Guide](docs/ADAPTERS.md)
- [Setting Up Webhooks in Gems](docs/GEM_WEBHOOK_SETUP.md)
- [Signing Secret Storage](docs/SIGNING_SECRET_STORAGE.md)
