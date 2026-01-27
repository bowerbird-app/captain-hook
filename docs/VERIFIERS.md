# Verifiers

## Overview

Verifiers are classes responsible for validating webhook signatures and extracting event data from webhook payloads. Every provider in CaptainHook must have a verifier that implements signature verification according to that provider's webhook specification.

This document provides a comprehensive guide to understanding, creating, and testing webhook verifiers in CaptainHook.

## Key Concepts

- **Verifier**: Class that validates webhook signatures and extracts event metadata
- **Signature Verification**: Cryptographic validation that webhook came from legitimate source
- **Event Extraction**: Parsing event ID, type, and timestamp from webhook payload
- **Base Verifier**: Parent class providing default implementations
- **Verifier Helpers**: Module with security utilities for signature verification
- **Built-in Verifiers**: Pre-built verifiers for common providers (e.g., Stripe)

## Verifier Responsibilities

### 1. Signature Verification

Validate that the webhook request is authentic using cryptographic signatures:

```ruby
def verify_signature(payload:, headers:, provider_config:)
  # Extract signature from headers
  # Generate expected signature using secret
  # Compare signatures using constant-time comparison
  # Return true if valid, false otherwise
end
```

**Purpose**: Prevent unauthorized webhook requests and man-in-the-middle attacks.

### 2. Event ID Extraction

Extract unique event identifier from payload:

```ruby
def extract_event_id(payload)
  # Return unique event ID (e.g., "evt_123", "whk_abc")
  # Used for idempotency and deduplication
end
```

**Purpose**: Ensure duplicate webhooks aren't processed multiple times.

### 3. Event Type Extraction

Extract event type from payload:

```ruby
def extract_event_type(payload)
  # Return event type (e.g., "payment.succeeded", "customer.created")
  # Used for routing to appropriate actions
end
```

**Purpose**: Route webhooks to correct action handlers.

### 4. Timestamp Extraction (Optional)

Extract timestamp for replay attack prevention:

```ruby
def extract_timestamp(headers)
  # Return Unix timestamp if provider includes it
  # Return nil if not supported
end
```

**Purpose**: Reject old webhooks that might be replayed by attackers.

## Base Verifier

All verifiers should inherit from `CaptainHook::Verifiers::Base`:

```ruby
module CaptainHook
  module Verifiers
    class Base
      include CaptainHook::VerifierHelpers

      def verify_signature(payload:, headers:, provider_config:)
        # Default: accepts all webhooks (no verification)
        true
      end

      def extract_timestamp(headers)
        # Default: no timestamp support
        nil
      end

      def extract_event_id(payload)
        # Default: tries common fields, falls back to UUID
        payload["id"] || payload["event_id"] || SecureRandom.uuid
      end

      def extract_event_type(payload)
        # Default: tries common fields, falls back to generic type
        payload["type"] || payload["event_type"] || "webhook.received"
      end
    end
  end
end
```

**Key Features**:
- Includes `VerifierHelpers` for security utilities
- Provides sensible defaults for all methods
- Always returns `true` for signature verification (override in subclasses!)
- Attempts to extract common fields from payloads

## Built-in Verifiers

### Stripe Verifier

CaptainHook includes a production-ready Stripe verifier:

**Location**: `lib/captain_hook/verifiers/stripe.rb`

**Implementation**:
```ruby
module CaptainHook
  module Verifiers
    class Stripe < Base
      SIGNATURE_HEADER = "Stripe-Signature"
      TIMESTAMP_TOLERANCE = 300 # 5 minutes

      def verify_signature(payload:, headers:, provider_config:)
        signature_header = extract_header(headers, SIGNATURE_HEADER)
        return false if signature_header.blank?

        # Parse: "t=1234567890,v1=sig1,v0=sig2"
        parsed = parse_kv_header(signature_header)
        timestamp = parsed["t"]
        signatures = [parsed["v1"], parsed["v0"]].flatten.compact

        return false if timestamp.blank? || signatures.empty?

        # Validate timestamp tolerance
        if provider_config.timestamp_validation_enabled?
          tolerance = provider_config.timestamp_tolerance_seconds || TIMESTAMP_TOLERANCE
          return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
        end

        # Generate expected signature
        signed_payload = "#{timestamp}.#{payload}"
        expected_signature = generate_hmac(provider_config.signing_secret, signed_payload)

        # Check if any signature matches (Stripe sends v1 and v0)
        signatures.any? { |sig| secure_compare(sig, expected_signature) }
      end

      def extract_timestamp(headers)
        signature_header = extract_header(headers, SIGNATURE_HEADER)
        return nil if signature_header.blank?

        parsed = parse_kv_header(signature_header)
        parsed["t"]&.to_i
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

**Usage in Provider YAML**:
```yaml
# captain_hook/stripe/stripe.yml
name: stripe
display_name: Stripe
verifier_file: stripe.rb  # References built-in verifier
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

**Features**:
- Implements Stripe's signature scheme (HMAC-SHA256 with timestamp)
- Supports both v1 and v0 signatures
- Validates timestamp tolerance (default 5 minutes)
- Parses Stripe's key-value signature header format
- Extracts event ID and type from Stripe payload structure

**Reference**: [Stripe Webhook Signature Verification](https://stripe.com/docs/webhooks/signatures)

## Creating Custom Verifiers

### Directory Structure

Place custom verifiers in your provider directory:

```
captain_hook/
└── <provider_name>/
    ├── <provider_name>.yml       # Provider configuration
    ├── <provider_name>.rb         # Custom verifier
    └── actions/                   # Action classes
```

### Verifier Class Template

```ruby
# captain_hook/custom_api/custom_api.rb
class CustomApiVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Signature"
  TIMESTAMP_HEADER = "X-Timestamp"

  def verify_signature(payload:, headers:, provider_config:)
    # 1. Extract signature from headers
    signature = extract_header(headers, SIGNATURE_HEADER)
    return false if signature.blank?

    # 2. Optional: Validate timestamp
    timestamp = extract_timestamp(headers)
    if timestamp && provider_config.timestamp_validation_enabled?
      tolerance = provider_config.timestamp_tolerance_seconds
      return false unless timestamp_within_tolerance?(timestamp, tolerance)
    end

    # 3. Generate expected signature
    expected = generate_hmac(provider_config.signing_secret, payload)

    # 4. Constant-time comparison
    secure_compare(signature, expected)
  end

  def extract_timestamp(headers)
    timestamp_str = extract_header(headers, TIMESTAMP_HEADER)
    parse_timestamp(timestamp_str)
  end

  def extract_event_id(payload)
    payload["id"] || payload["event_id"]
  end

  def extract_event_type(payload)
    payload["type"] || payload["event"]
  end
end
```

### Naming Conventions

**Class Name**: `<Provider>Verifier` or just `<Provider>`
- `StripeVerifier` ✅
- `GithubVerifier` ✅
- `CustomApiVerifier` ✅
- `Stripe` ✅ (also acceptable)

**File Name**: Must match provider directory name
- Provider: `stripe` → File: `stripe/stripe.rb` ✅
- Provider: `github` → File: `github/github.rb` ✅
- Provider: `custom_api` → File: `custom_api/custom_api.rb` ✅

**Module Namespacing**: Optional but recommended for gems
```ruby
# In gem: payment_gem/captain_hook/stripe/stripe.rb
module PaymentGem
  class StripeVerifier
    include CaptainHook::VerifierHelpers
    # ...
  end
end
```

### Provider YAML Configuration

Reference your verifier in the provider YAML:

```yaml
# captain_hook/custom_api/custom_api.yml
name: custom_api
display_name: Custom API
verifier_file: custom_api.rb
signing_secret: ENV[CUSTOM_API_SECRET]
```

## Verifier Method Reference

### `verify_signature(payload:, headers:, provider_config:)`

**Purpose**: Verify webhook signature authenticity

**Parameters**:
- `payload` (String): Raw request body (unparsed)
- `headers` (Hash): Request headers
- `provider_config` (ProviderConfig): Provider configuration with secret

**Returns**: `Boolean` - `true` if signature valid, `false` otherwise

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Hub-Signature-256")
  return false if signature.blank?
  
  # Remove "sha256=" prefix if present
  signature = signature.sub(/^sha256=/, "")
  
  expected = generate_hmac(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

**Best Practices**:
- Always use `secure_compare` for timing-attack prevention
- Extract raw payload, not parsed JSON
- Return `false` on any validation failure
- Use helper methods from `VerifierHelpers`

---

### `extract_event_id(payload)`

**Purpose**: Extract unique event identifier

**Parameters**:
- `payload` (Hash): Parsed JSON payload

**Returns**: `String` - Unique event ID

**Example**:
```ruby
def extract_event_id(payload)
  payload["id"] || payload["event_id"] || payload["webhook_id"]
end
```

**Best Practices**:
- Return provider's unique event ID
- Provide fallbacks for different field names
- Return `SecureRandom.uuid` as last resort (not recommended)

**Used For**:
- Idempotency (preventing duplicate processing)
- Event tracking and logging
- Database uniqueness constraints

---

### `extract_event_type(payload)`

**Purpose**: Extract event type for action routing

**Parameters**:
- `payload` (Hash): Parsed JSON payload

**Returns**: `String` - Event type identifier

**Example**:
```ruby
def extract_event_type(payload)
  payload["type"] || payload["event"] || payload["event_type"]
end
```

**Best Practices**:
- Return exactly as provider sends (don't transform)
- Provide fallbacks for common field names
- Use consistent format (e.g., `resource.action`)

**Used For**:
- Matching webhooks to action classes
- Event filtering and routing
- Logging and metrics

---

### `extract_timestamp(headers)` (Optional)

**Purpose**: Extract timestamp for replay attack prevention

**Parameters**:
- `headers` (Hash): Request headers

**Returns**: `Integer | nil` - Unix timestamp or `nil` if not supported

**Example**:
```ruby
def extract_timestamp(headers)
  # From header
  timestamp_str = extract_header(headers, "X-Timestamp")
  parse_timestamp(timestamp_str)
  
  # Or from signature header
  sig_header = extract_header(headers, "X-Signature")
  parsed = parse_kv_header(sig_header)
  parsed["t"]&.to_i
end
```

**Best Practices**:
- Return Unix timestamp (seconds since epoch)
- Return `nil` if provider doesn't send timestamp
- Use `parse_timestamp` helper for format flexibility

**Used For**:
- Timestamp validation in `verify_signature`
- Replay attack prevention
- Webhook age tracking

## Common Signature Schemes

### 1. Simple HMAC-SHA256 (Hex)

**Description**: Most common scheme - HMAC signature in header

**Example Providers**: GitHub, Shopify, Slack

**Implementation**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

**Header Format**:
```
X-Signature: a1b2c3d4e5f6...
```

---

### 2. HMAC-SHA256 with Prefix

**Description**: Signature with algorithm prefix

**Example Providers**: GitHub (`sha256=...`)

**Implementation**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  sig_header = extract_header(headers, "X-Hub-Signature-256")
  return false if sig_header.blank?
  
  # Remove "sha256=" prefix
  signature = sig_header.sub(/^sha256=/, "")
  
  expected = generate_hmac(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

**Header Format**:
```
X-Hub-Signature-256: sha256=a1b2c3d4e5f6...
```

---

### 3. HMAC with Timestamp (Stripe-style)

**Description**: Includes timestamp in signed payload

**Example Providers**: Stripe

**Implementation**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  sig_header = extract_header(headers, "Stripe-Signature")
  return false if sig_header.blank?
  
  # Parse: "t=1234567890,v1=sig"
  parsed = parse_kv_header(sig_header)
  timestamp = parsed["t"]
  signature = parsed["v1"]
  
  return false if timestamp.blank? || signature.blank?
  
  # Validate timestamp age
  return false unless timestamp_within_tolerance?(timestamp.to_i, 300)
  
  # Sign with timestamp included
  signed_payload = "#{timestamp}.#{payload}"
  expected = generate_hmac(provider_config.signing_secret, signed_payload)
  
  secure_compare(signature, expected)
end
```

**Header Format**:
```
Stripe-Signature: t=1234567890,v1=a1b2c3d4...,v0=x9y8z7...
```

---

### 4. Base64-Encoded HMAC

**Description**: HMAC signature encoded as Base64

**Example Providers**: Twilio, SendGrid

**Implementation**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac_base64(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

**Header Format**:
```
X-Signature: UDH+PZicbRU3oBP6...
```

---

### 5. JWT-Based Signatures

**Description**: JSON Web Token for verification

**Example Providers**: Some OAuth providers

**Implementation**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  token = extract_header(headers, "Authorization")
  return false if token.blank?
  
  # Remove "Bearer " prefix
  token = token.sub(/^Bearer /, "")
  
  begin
    decoded = JWT.decode(
      token,
      provider_config.signing_secret,
      true,
      algorithm: "HS256"
    )
    true
  rescue JWT::DecodeError
    false
  end
end
```

**Requires**: `gem 'jwt'`

---

## Signature Scheme Examples

### GitHub Webhook Verifier

```ruby
# captain_hook/github/github.rb
class GithubVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Hub-Signature-256"
  EVENT_HEADER = "X-GitHub-Event"
  DELIVERY_HEADER = "X-GitHub-Delivery"

  def verify_signature(payload:, headers:, provider_config:)
    sig_header = extract_header(headers, SIGNATURE_HEADER)
    return false if sig_header.blank?
    
    # GitHub format: "sha256=abc123..."
    signature = sig_header.sub(/^sha256=/, "")
    
    expected = generate_hmac(provider_config.signing_secret, payload)
    secure_compare(signature, expected)
  end

  def extract_event_id(payload)
    # GitHub uses header for delivery ID, not payload
    payload["hook_id"]&.to_s || payload["id"]
  end

  def extract_event_type(payload)
    # GitHub sends event type in header, but also check payload
    payload["action"] ? "#{payload['action']}" : "unknown"
  end

  # Custom method to extract event from headers
  def extract_event_from_headers(headers)
    extract_header(headers, EVENT_HEADER)
  end
end
```

**GitHub Webhook Headers**:
```
X-Hub-Signature-256: sha256=abc123...
X-GitHub-Event: push
X-GitHub-Delivery: 12345678-1234-1234-1234-123456789012
```

---

### Shopify Webhook Verifier

```ruby
# captain_hook/shopify/shopify.rb
class ShopifyVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Shopify-Hmac-SHA256"
  TOPIC_HEADER = "X-Shopify-Topic"

  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, SIGNATURE_HEADER)
    return false if signature.blank?
    
    # Shopify uses Base64-encoded HMAC
    expected = generate_hmac_base64(provider_config.signing_secret, payload)
    secure_compare(signature, expected)
  end

  def extract_event_id(payload)
    payload["id"]&.to_s || payload["admin_graphql_api_id"]
  end

  def extract_event_type(payload)
    # Shopify sends event type in header
    # Format: "orders/create", "products/update"
    payload["topic"] || "webhook.received"
  end

  def extract_topic_from_headers(headers)
    extract_header(headers, TOPIC_HEADER)
  end
end
```

---

### Twilio Webhook Verifier

```ruby
# captain_hook/twilio/twilio.rb
class TwilioVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Twilio-Signature"

  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, SIGNATURE_HEADER)
    return false if signature.blank?
    
    # Twilio signs the full URL + POST parameters
    # This is a simplified version
    expected = generate_hmac_base64(provider_config.signing_secret, payload)
    secure_compare(signature, expected)
  end

  def extract_event_id(payload)
    payload["MessageSid"] || payload["CallSid"] || payload["Sid"]
  end

  def extract_event_type(payload)
    payload["EventType"] || payload["MessageStatus"] || "webhook.received"
  end
end
```

**Note**: Twilio's actual verification is more complex - see Twilio docs for complete implementation.

---

## Testing Verifiers

### Unit Testing

```ruby
# test/verifiers/custom_api_verifier_test.rb
require "test_helper"

class CustomApiVerifierTest < ActiveSupport::TestCase
  setup do
    @verifier = CustomApiVerifier.new
    @secret = "test_secret_key"
    @payload = '{"id":"evt_123","type":"test.event"}'
  end

  test "verifies valid signature" do
    signature = @verifier.generate_hmac(@secret, @payload)
    headers = { "X-Signature" => signature }
    config = build_config(signing_secret: @secret)
    
    result = @verifier.verify_signature(
      payload: @payload,
      headers: headers,
      provider_config: config
    )
    
    assert result, "Should verify valid signature"
  end

  test "rejects invalid signature" do
    headers = { "X-Signature" => "invalid_signature" }
    config = build_config(signing_secret: @secret)
    
    result = @verifier.verify_signature(
      payload: @payload,
      headers: headers,
      provider_config: config
    )
    
    refute result, "Should reject invalid signature"
  end

  test "rejects missing signature" do
    config = build_config(signing_secret: @secret)
    
    result = @verifier.verify_signature(
      payload: @payload,
      headers: {},
      provider_config: config
    )
    
    refute result, "Should reject missing signature"
  end

  test "extracts event ID" do
    payload = { "id" => "evt_123" }
    assert_equal "evt_123", @verifier.extract_event_id(payload)
  end

  test "extracts event type" do
    payload = { "type" => "test.event" }
    assert_equal "test.event", @verifier.extract_event_type(payload)
  end

  test "extracts timestamp" do
    timestamp = Time.current.to_i
    headers = { "X-Timestamp" => timestamp.to_s }
    assert_equal timestamp, @verifier.extract_timestamp(headers)
  end

  private

  def build_config(signing_secret:)
    OpenStruct.new(
      signing_secret: signing_secret,
      timestamp_validation_enabled?: true,
      timestamp_tolerance_seconds: 300
    )
  end
end
```

---

### Integration Testing

```ruby
# test/integration/custom_api_webhook_test.rb
require "test_helper"

class CustomApiWebhookTest < ActionDispatch::IntegrationTest
  setup do
    @provider = captain_hook_providers(:custom_api)
    @secret = ENV["CUSTOM_API_SECRET"]
    @payload = { id: "evt_123", type: "test.event" }.to_json
  end

  test "accepts webhook with valid signature" do
    verifier = CustomApiVerifier.new
    signature = verifier.generate_hmac(@secret, @payload)
    
    post captain_hook.incoming_path(@provider.name, @provider.token),
         params: @payload,
         headers: {
           "X-Signature" => signature,
           "Content-Type" => "application/json"
         }
    
    assert_response :created
    
    event = CaptainHook::IncomingEvent.last
    assert_equal "evt_123", event.external_id
    assert_equal "test.event", event.event_type
  end

  test "rejects webhook with invalid signature" do
    post captain_hook.incoming_path(@provider.name, @provider.token),
         params: @payload,
         headers: {
           "X-Signature" => "invalid_signature",
           "Content-Type" => "application/json"
         }
    
    assert_response :unauthorized
    assert_equal 0, CaptainHook::IncomingEvent.count
  end

  test "rejects webhook with missing signature" do
    post captain_hook.incoming_path(@provider.name, @provider.token),
         params: @payload,
         headers: { "Content-Type" => "application/json" }
    
    assert_response :unauthorized
  end
end
```

---

### Testing with Real Provider Data

```ruby
# test/verifiers/stripe_verifier_test.rb
test "verifies real Stripe webhook" do
  # Actual Stripe webhook payload
  payload = File.read(Rails.root.join("test/fixtures/stripe_webhook.json"))
  
  # Generate signature like Stripe does
  timestamp = Time.current.to_i
  signed_payload = "#{timestamp}.#{payload}"
  signature = @verifier.generate_hmac(@secret, signed_payload)
  
  headers = {
    "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
  }
  
  config = build_config(signing_secret: @secret)
  
  result = @verifier.verify_signature(
    payload: payload,
    headers: headers,
    provider_config: config
  )
  
  assert result, "Should verify real Stripe webhook"
end
```

---

## Verifier Loading and Discovery

### How Verifiers Are Loaded

1. **Provider Discovery**: CaptainHook scans `captain_hook/` directories
2. **File Loading**: Loads `<provider>/<provider>.rb` file via `load`
3. **Class Detection**: Finds classes including `VerifierHelpers` or ending in `Verifier`
4. **Registration**: Associates verifier class with provider configuration

### Automatic Loading

```ruby
# lib/captain_hook/services/provider_discovery.rb
verifier_file = File.join(subdir, "#{provider_name}.rb")
if File.exist?(verifier_file)
  load verifier_file  # Loads the verifier class
end
```

### Manual Registration (Advanced)

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  config.register_verifier("custom_api", CustomApiVerifier)
end
```

---

## Verifier Best Practices

### Security

#### Always Use Constant-Time Comparison

```ruby
# ✅ GOOD: Timing-attack safe
secure_compare(signature, expected)

# ❌ BAD: Vulnerable to timing attacks
signature == expected
```

#### Include Timestamp in Signature

```ruby
# ✅ GOOD: Timestamp is part of signed data
signed_data = "#{timestamp}.#{payload}"
generate_hmac(secret, signed_data)

# ❌ BAD: Timestamp not protected
generate_hmac(secret, payload)
```

#### Validate Timestamp Tolerance

```ruby
# ✅ GOOD: Prevents replay attacks
unless timestamp_within_tolerance?(timestamp, 300)
  return false
end

# ❌ BAD: No timestamp validation
```

---

### Performance

#### Cache Verifier Instances

```ruby
# ProviderConfig caches verifier instance
def verifier
  @verifier ||= verifier_class.constantize.new
end
```

#### Fail Fast

```ruby
# ✅ GOOD: Return early on failures
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  return false if signature.blank?  # Fail fast
  
  # Continue with verification...
end

# ❌ BAD: Unnecessary work before failing
def verify_signature(payload:, headers:, provider_config:)
  expected = generate_hmac(secret, payload)  # Wasted work
  signature = extract_header(headers, "X-Signature")
  return false if signature.blank?
end
```

---

### Code Organization

#### Use Constants for Headers

```ruby
# ✅ GOOD: Clear and maintainable
SIGNATURE_HEADER = "X-Hub-Signature-256"
EVENT_HEADER = "X-GitHub-Event"

def verify_signature(...)
  signature = extract_header(headers, SIGNATURE_HEADER)
end

# ❌ BAD: Magic strings scattered
def verify_signature(...)
  signature = extract_header(headers, "X-Hub-Signature-256")
end
```

#### Document Signature Schemes

```ruby
# ✅ GOOD: Clear documentation
# Stripe webhook verifier
# Implements Stripe's webhook signature verification scheme
# Reference: https://stripe.com/docs/webhooks/signatures
#
# Signature format: "t=<timestamp>,v1=<signature>,v0=<old_signature>"
# Signed payload: "<timestamp>.<raw_body>"
class StripeVerifier
  # ...
end
```

---

### Error Handling

#### Return False, Don't Raise

```ruby
# ✅ GOOD: Returns false on error
def verify_signature(...)
  return false if signature.blank?
  return false unless valid_timestamp?
  secure_compare(signature, expected)
end

# ❌ BAD: Raises exceptions
def verify_signature(...)
  raise ArgumentError, "Missing signature" if signature.blank?
end
```

#### Log Verification Failures

```ruby
# ✅ GOOD: Log for debugging
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  
  if signature.blank?
    log_verification("custom_api", { error: "Missing signature" })
    return false
  end
  
  # Continue...
end
```

---

## Troubleshooting

### Signature Verification Always Fails

**Problem**: Valid webhooks are rejected

**Diagnosis**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  
  # Debug logging
  log_verification("provider", {
    received_signature: signature,
    expected_signature: expected,
    payload_length: payload.bytesize,
    secret_present: provider_config.signing_secret.present?,
    match: secure_compare(signature, expected)
  })
  
  secure_compare(signature, expected)
end
```

**Common Causes**:

1. **Using parsed payload instead of raw**:
```ruby
# ❌ WRONG: Using parsed/modified payload
parsed = JSON.parse(request.body.read)
signature = generate_hmac(secret, parsed.to_json)

# ✅ CORRECT: Using raw payload
raw_payload = request.raw_post
signature = generate_hmac(secret, raw_payload)
```

2. **Wrong secret**:
```yaml
# Check environment variable name
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]  # ← Must match .env
```

3. **Wrong header name**:
```ruby
# Try multiple variations
signature = extract_header(
  headers,
  "X-Signature",
  "HTTP_X_SIGNATURE",
  "X_Signature"
)
```

4. **Wrong encoding (Hex vs Base64)**:
```ruby
# Hex (most common)
generate_hmac(secret, payload)

# Base64 (some providers)
generate_hmac_base64(secret, payload)
```

---

### Verifier Not Loading

**Problem**: Verifier class not found

**Diagnosis**:
```ruby
# Check if file was loaded
Rails.logger.debug("Loaded verifier from #{verifier_file}")

# Check class exists
CustomApiVerifier  # Should not raise NameError
```

**Common Causes**:

1. **File name mismatch**:
```
# ✅ CORRECT
captain_hook/stripe/stripe.rb

# ❌ WRONG
captain_hook/stripe/verifier.rb
captain_hook/stripe/stripe_verifier.rb
```

2. **Class name mismatch**:
```ruby
# ✅ CORRECT: Ends with "Verifier"
class StripeVerifier
  include CaptainHook::VerifierHelpers
end

# ✅ ALSO CORRECT: Matches provider name
class Stripe
  include CaptainHook::VerifierHelpers
end

# ❌ WRONG: Doesn't match convention
class CustomVerifier  # Should be CustomApiVerifier
end
```

3. **Missing VerifierHelpers**:
```ruby
# ✅ CORRECT
class CustomApiVerifier
  include CaptainHook::VerifierHelpers
end

# ❌ WRONG: Missing include
class CustomApiVerifier
end
```

---

### Timestamp Validation Too Strict

**Problem**: Valid webhooks rejected due to timestamp

**Diagnosis**:
```ruby
def verify_signature(...)
  timestamp = extract_timestamp(headers)
  age = Time.current.to_i - timestamp
  
  Rails.logger.debug "Timestamp age: #{age} seconds"
  Rails.logger.debug "Tolerance: #{provider_config.timestamp_tolerance_seconds}"
end
```

**Solutions**:

1. **Increase tolerance**:
```yaml
# captain_hook/provider/provider.yml
timestamp_tolerance_seconds: 600  # 10 minutes (relaxed)
```

2. **Check clock sync**:
```bash
# Verify server time is synchronized
timedatectl status
```

3. **Disable timestamp validation** (development only):
```yaml
timestamp_tolerance_seconds: 0  # Disables validation
```

---

### Event Type Not Matching Actions

**Problem**: Webhooks received but no actions executed

**Diagnosis**:
```ruby
def extract_event_type(payload)
  event_type = payload["type"]
  Rails.logger.debug "Extracted event type: #{event_type}"
  event_type
end
```

**Common Causes**:

1. **Event type transformation**:
```ruby
# ❌ WRONG: Transforming event type
def extract_event_type(payload)
  payload["type"].gsub(".", "_")  # Changes "payment.succeeded" to "payment_succeeded"
end

# ✅ CORRECT: Return as-is
def extract_event_type(payload)
  payload["type"]  # Returns "payment.succeeded"
end
```

2. **Action class event_type mismatch**:
```ruby
# Verifier returns:
"payment_intent.succeeded"

# Action expects:
def self.details
  { event_type: "payment.succeeded" }  # ← Mismatch!
end
```

**Solution**: Ensure verifier returns exact event type from provider.

---

## Advanced Topics

### Multi-Signature Verification

Support multiple signature versions:

```ruby
def verify_signature(payload:, headers:, provider_config:)
  sig_header = extract_header(headers, "X-Signatures")
  parsed = parse_kv_header(sig_header)
  
  # Try v3, v2, v1 in order
  ["v3", "v2", "v1"].each do |version|
    signature = parsed[version]
    next if signature.blank?
    
    expected = generate_signature_for_version(version, payload, provider_config.signing_secret)
    return true if secure_compare(signature, expected)
  end
  
  false
end

def generate_signature_for_version(version, payload, secret)
  case version
  when "v3" then OpenSSL::HMAC.hexdigest("SHA512", secret, payload)
  when "v2" then generate_hmac_base64(secret, payload)
  when "v1" then generate_hmac(secret, payload)
  end
end
```

---

### Custom Header Extraction

Extract data from custom header formats:

```ruby
def extract_event_metadata(headers)
  {
    event_id: extract_header(headers, "X-Event-ID"),
    event_type: extract_header(headers, "X-Event-Type"),
    retry_count: extract_header(headers, "X-Retry-Count")&.to_i || 0,
    correlation_id: extract_header(headers, "X-Correlation-ID")
  }
end
```

---

### Conditional Verification

Skip verification in specific scenarios:

```ruby
def verify_signature(payload:, headers:, provider_config:)
  # Skip verification if secret not configured (development)
  return true if skip_verification?(provider_config.signing_secret)
  
  # Skip verification for specific IP addresses (if whitelisted)
  if provider_config.whitelist_ips.present?
    client_ip = headers["X-Forwarded-For"]
    return true if provider_config.whitelist_ips.include?(client_ip)
  end
  
  # Normal verification
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

**Warning**: Only use in development/testing! Always verify in production.

---

## See Also

- [Verifier Helpers](VERIFIER_HELPERS.md) - Security utility methods
- [Provider Discovery](PROVIDER_DISCOVERY.md) - How verifiers are loaded
- [GEM_WEBHOOK_SETUP.md](GEM_WEBHOOK_SETUP.md) - Creating verifiers in gems
- [Signing Secret Storage](SIGNING_SECRET_STORAGE.md) - Managing webhook secrets
- [TECHNICAL_PROCESS.md](../TECHNICAL_PROCESS.md) - Complete webhook processing flow
