# Verifier Helpers

## Overview

`CaptainHook::VerifierHelpers` is a module that provides reusable security and utility methods for webhook signature verification. Any custom verifier class can include this module to access battle-tested implementations of common cryptographic operations, header parsing, timestamp validation, and more.

This document explains all available helper methods, their use cases, and best practices for building secure webhook verifiers.

## Key Concepts

- **Verifier**: Class responsible for validating webhook signatures and extracting event data
- **Verifier Helpers**: Shared utility methods for signature verification
- **Constant-Time Comparison**: Prevents timing attacks by comparing strings in fixed time
- **HMAC**: Hash-based Message Authentication Code for signature generation
- **Timestamp Tolerance**: Clock skew allowance for timestamp validation

## Including Verifier Helpers

### Basic Usage

```ruby
# captain_hook/custom_api/custom_api.rb
class CustomApiVerifier
  include CaptainHook::VerifierHelpers

  def verify_signature(payload:, headers:, provider_config:)
    # Now you have access to all helper methods
    signature = extract_header(headers, "X-Signature")
    expected = generate_hmac(provider_config.signing_secret, payload)
    secure_compare(signature, expected)
  end
end
```

### Base Class Inheritance

All verifiers should inherit from `CaptainHook::Verifiers::Base`, which already includes `VerifierHelpers`:

```ruby
module CaptainHook
  module Verifiers
    class MyVerifier < Base
      # VerifierHelpers already included via Base
      
      def verify_signature(payload:, headers:, provider_config:)
        signature = extract_header(headers, "X-My-Signature")
        expected = generate_hmac(provider_config.signing_secret, payload)
        secure_compare(signature, expected)
      end
    end
  end
end
```

## Available Helper Methods

### Security Methods

#### `secure_compare(a, b)`

Constant-time string comparison to prevent timing attacks.

**Purpose**: Compare two strings (typically signatures) in a way that takes the same amount of time regardless of where they differ. This prevents attackers from using response timing to guess valid signatures character by character.

**Parameters**:
- `a` (String): First string to compare
- `b` (String): Second string to compare

**Returns**: `Boolean` - `true` if strings match, `false` otherwise

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  received_signature = extract_header(headers, "X-Signature")
  expected_signature = generate_hmac(provider_config.signing_secret, payload)
  
  # ✅ GOOD: Constant-time comparison
  secure_compare(received_signature, expected_signature)
  
  # ❌ BAD: Regular comparison vulnerable to timing attacks
  # received_signature == expected_signature
end
```

**Behavior**:
- Returns `false` if either string is blank
- Returns `false` if strings have different byte sizes
- Compares byte-by-byte using XOR operations
- Always takes the same time regardless of differences

**Implementation Details**:
```ruby
def secure_compare(a, b)
  return false if a.blank? || b.blank?
  return false if a.bytesize != b.bytesize

  l = a.unpack("C*")  # Convert to byte arrays
  r = b.unpack("C*")

  result = 0
  l.zip(r) { |x, y| result |= x ^ y }  # XOR comparison
  result.zero?
end
```

---

#### `skip_verification?(signing_secret)`

Check if signature verification should be skipped.

**Purpose**: Determine if verification is impossible or unnecessary due to missing/unresolved secrets.

**Parameters**:
- `signing_secret` (String): The signing secret to check

**Returns**: `Boolean` - `true` if verification should be skipped

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  # Skip if secret not configured
  return true if skip_verification?(provider_config.signing_secret)
  
  # Perform actual verification
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

**Behavior**:
- Returns `true` if `signing_secret` is blank (`nil` or empty string)
- Returns `true` if `signing_secret` contains unresolved ENV placeholder (e.g., `"ENV[STRIPE_SECRET]"`)

**Use Cases**:
- Development/testing environments where secrets aren't configured
- Graceful degradation when environment variables aren't set
- Avoiding crashes when secrets are missing

**Warning**: Only use in development. Production should always verify signatures!

---

### HMAC Generation

#### `generate_hmac(secret, data)`

Generate HMAC-SHA256 signature (hex-encoded).

**Purpose**: Create a hexadecimal HMAC signature for webhook verification.

**Parameters**:
- `secret` (String): Signing secret key
- `data` (String): Data to sign (typically raw request body)

**Returns**: `String` - Hex-encoded HMAC signature (64 characters)

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  
  secure_compare(signature, expected)
end
```

**Output Format**:
```ruby
generate_hmac("secret", "data")
# => "5031fe3d989c6d1537a013fa6e739da23463fdaec3b70137d828e36ace221bd0"
```

**Common Providers Using Hex HMAC**:
- GitHub (sha256=...)
- Shopify
- Slack
- Most custom webhooks

---

#### `generate_hmac_base64(secret, data)`

Generate HMAC-SHA256 signature (Base64-encoded).

**Purpose**: Create a Base64-encoded HMAC signature for providers that use Base64 encoding.

**Parameters**:
- `secret` (String): Signing secret key
- `data` (String): Data to sign

**Returns**: `String` - Base64-encoded HMAC signature

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac_base64(provider_config.signing_secret, payload)
  
  secure_compare(signature, expected)
end
```

**Output Format**:
```ruby
generate_hmac_base64("secret", "data")
# => "UDH+PZicbRU3oBP6bnOdojRj/a7Dtw"
```

**Common Providers Using Base64 HMAC**:
- Twilio
- SendGrid
- Mailgun
- Some payment processors

**Difference from Hex**:
```ruby
# Same signature, different encodings:
hex    = generate_hmac("secret", "data")
base64 = generate_hmac_base64("secret", "data")

puts hex    # => "5031fe3d989c6d1537a013fa6e739da23463fdaec3b70137d828e36ace221bd0"
puts base64 # => "UDH+PZicbRU3oBP6bnOdojRj/a7Dtw=="
```

---

### Header Extraction

#### `extract_header(headers, *keys)`

Extract header value with case-insensitive matching.

**Purpose**: Reliably extract headers regardless of capitalization (e.g., `X-Signature`, `x-signature`, `X-SIGNATURE` all work).

**Parameters**:
- `headers` (Hash): Request headers hash
- `*keys` (Array<String>): Header keys to try (in order)

**Returns**: `String | nil` - First non-blank header value found, or `nil`

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  # Try multiple possible header names
  signature = extract_header(
    headers,
    "X-Hub-Signature-256",  # Try this first
    "X-Hub-Signature",      # Fall back to this
    "HTTP_X_HUB_SIGNATURE"  # Then try this
  )
  
  return false if signature.blank?
  
  # Verify signature...
end
```

**Case Handling**:
```ruby
headers = {
  "X-Signature" => "abc123",
  "x-custom" => "xyz789"
}

extract_header(headers, "X-Signature")  # => "abc123"
extract_header(headers, "x-signature")  # => "abc123"
extract_header(headers, "X-SIGNATURE")  # => "abc123"
extract_header(headers, "X-Custom")     # => "xyz789"
```

**Multiple Keys**:
```ruby
# Tries keys in order, returns first match
extract_header(headers, "X-Primary", "X-Fallback", "X-Legacy")
```

**Use Cases**:
- Handling different header casing from different frameworks
- Supporting multiple header names for backward compatibility
- Gracefully handling provider header changes

---

### Header Parsing

#### `parse_kv_header(header_value)`

Parse key-value header format (e.g., `"t=123,v1=abc,v0=xyz"`).

**Purpose**: Parse headers that contain multiple key-value pairs separated by commas.

**Parameters**:
- `header_value` (String): Header value to parse

**Returns**: `Hash` - Parsed key-value pairs

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature_header = extract_header(headers, "Stripe-Signature")
  
  # Parse: "t=1609459200,v1=abc123,v0=xyz789"
  parsed = parse_kv_header(signature_header)
  
  timestamp = parsed["t"]           # => "1609459200"
  current_sig = parsed["v1"]        # => "abc123"
  previous_sig = parsed["v0"]       # => "xyz789"
  
  # Verify using timestamp and signature...
end
```

**Format Support**:
```ruby
# Simple key-value pairs
parse_kv_header("key1=value1,key2=value2")
# => {"key1" => "value1", "key2" => "value2"}

# With whitespace (automatically stripped)
parse_kv_header("key1 = value1 , key2 = value2")
# => {"key1" => "value1", "key2" => "value2"}

# Multiple values for same key
parse_kv_header("v1=abc,v0=xyz,v1=def")
# => {"v1" => ["abc", "def"], "v0" => "xyz"}
```

**Behavior**:
- Returns empty hash if `header_value` is blank
- Strips whitespace from keys and values
- Supports multiple values for the same key (becomes array)
- Ignores malformed pairs (missing key or value)

**Common Providers**:
- **Stripe**: `Stripe-Signature: t=timestamp,v1=signature,v0=old_signature`
- **GitHub**: Similar format for some webhook types
- Custom APIs with complex signature schemes

**Real-World Stripe Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  sig_header = extract_header(headers, "Stripe-Signature")
  return false if sig_header.blank?
  
  parsed = parse_kv_header(sig_header)
  timestamp = parsed["t"]
  signatures = [parsed["v1"], parsed["v0"]].flatten.compact
  
  return false if timestamp.blank? || signatures.empty?
  
  # Verify timestamp tolerance
  return false unless timestamp_within_tolerance?(timestamp.to_i, 300)
  
  # Generate expected signature
  signed_payload = "#{timestamp}.#{payload}"
  expected = generate_hmac(provider_config.signing_secret, signed_payload)
  
  # Check if any signature matches (Stripe sends both v1 and v0)
  signatures.any? { |sig| secure_compare(sig, expected) }
end
```

---

### Timestamp Validation

#### `timestamp_within_tolerance?(timestamp, tolerance)`

Check if timestamp is within acceptable tolerance.

**Purpose**: Verify that webhook timestamp is recent enough to prevent replay attacks.

**Parameters**:
- `timestamp` (Integer): Unix timestamp to check
- `tolerance` (Integer): Maximum age in seconds

**Returns**: `Boolean` - `true` if timestamp is recent enough

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  timestamp = extract_timestamp(headers)
  
  # Verify timestamp is within 5 minutes (300 seconds)
  unless timestamp_within_tolerance?(timestamp, 300)
    return false
  end
  
  # Verify signature...
end
```

**How It Works**:
```ruby
current_time = Time.current.to_i  # => 1706400000
timestamp = 1706399800             # 200 seconds ago

age = (current_time - timestamp).abs  # => 200
timestamp_within_tolerance?(timestamp, 300)  # => true (200 <= 300)

old_timestamp = 1706399000  # 1000 seconds ago
timestamp_within_tolerance?(old_timestamp, 300)  # => false (1000 > 300)
```

**Clock Skew Handling**:
```ruby
# Uses absolute value to handle both past and future timestamps
future_timestamp = Time.current.to_i + 100  # 100 seconds in future
timestamp_within_tolerance?(future_timestamp, 300)  # => true

past_timestamp = Time.current.to_i - 100  # 100 seconds in past  
timestamp_within_tolerance?(past_timestamp, 300)  # => true
```

**Best Practices**:

**Recommended Tolerances**:
- **Stripe**: 300 seconds (5 minutes) - recommended by Stripe
- **GitHub**: 300 seconds (5 minutes) - recommended by GitHub
- **High-security**: 60 seconds (1 minute) - strict but may have false negatives
- **Development**: 3600 seconds (1 hour) - relaxed for testing

**Configuration**:
```yaml
# captain_hook/stripe/stripe.yml
timestamp_tolerance_seconds: 300  # 5 minutes
```

**Use Case - Prevent Replay Attacks**:
```ruby
# Without timestamp validation:
# Attacker captures valid webhook and replays it later
# ❌ System accepts old webhook as new event

# With timestamp validation:
# Attacker replays webhook 10 minutes later
# ✅ System rejects due to old timestamp
unless timestamp_within_tolerance?(timestamp, 300)
  log_verification("provider", { error: "Timestamp too old" })
  return false
end
```

---

#### `parse_timestamp(time_string)`

Parse timestamp from various formats.

**Purpose**: Convert different timestamp formats to Unix timestamp (integer).

**Parameters**:
- `time_string` (String | Integer): Timestamp to parse

**Returns**: `Integer | nil` - Unix timestamp or `nil` if unparseable

**Example**:
```ruby
def extract_timestamp(headers)
  timestamp_header = extract_header(headers, "X-Timestamp", "X-Request-Time")
  parse_timestamp(timestamp_header)
end
```

**Supported Formats**:
```ruby
# Unix timestamp (integer)
parse_timestamp(1706400000)
# => 1706400000

# Unix timestamp (string)
parse_timestamp("1706400000")
# => 1706400000

# ISO8601
parse_timestamp("2024-01-28T12:00:00Z")
# => 1706443200

# RFC3339
parse_timestamp("2024-01-28T12:00:00+00:00")
# => 1706443200

# Human-readable
parse_timestamp("2024-01-28 12:00:00 UTC")
# => 1706443200

# Invalid/unparseable
parse_timestamp("not-a-date")
# => nil

parse_timestamp(nil)
# => nil
```

**Use Cases**:
- Extracting timestamps from different provider formats
- Supporting both Unix and ISO8601 timestamps
- Gracefully handling invalid timestamps

**Complete Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  # Extract and parse timestamp
  timestamp_header = extract_header(headers, "X-Timestamp")
  timestamp = parse_timestamp(timestamp_header)
  
  # Skip if no timestamp provided
  return true if timestamp.nil?
  
  # Validate timestamp
  unless timestamp_within_tolerance?(timestamp, 300)
    log_verification("provider", { 
      error: "Timestamp expired",
      timestamp: timestamp,
      age: Time.current.to_i - timestamp
    })
    return false
  end
  
  # Continue with signature verification...
end
```

---

### Debugging

#### `log_verification(provider, details)`

Log signature verification details for debugging.

**Purpose**: Output detailed verification information when debug mode is enabled.

**Parameters**:
- `provider` (String): Provider name
- `details` (Hash): Details to log

**Returns**: `nil`

**Example**:
```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  
  log_verification("custom_api", {
    received_signature: signature,
    expected_signature: expected,
    match: secure_compare(signature, expected),
    payload_length: payload.bytesize,
    secret_length: provider_config.signing_secret.bytesize
  })
  
  secure_compare(signature, expected)
end
```

**Output** (when `debug_mode: true`):
```
[CUSTOM_API] Signature Verification:
  received_signature: abc123def456...
  expected_signature: abc123def456...
  match: true
  payload_length: 1234
  secret_length: 32
```

**Configuration**:
```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  config.debug_mode = Rails.env.development?
end
```

**Behavior**:
- Only logs if `CaptainHook.configuration.debug_mode` is `true`
- Formats output with provider name in caps
- Indents each detail for readability
- Safe to leave in production code (no-op when disabled)

**Security Warning**: Debug logs may contain sensitive data. Only enable in development!

---

### Utility Methods

#### `build_webhook_url(path, provider_token: nil)`

Build full webhook URL.

**Purpose**: Construct complete webhook URLs for documentation or provider registration.

**Parameters**:
- `path` (String): Webhook path (e.g., `"/captain_hook/stripe"`)
- `provider_token` (String, optional): Provider token to append

**Returns**: `String` - Full webhook URL

**Example**:
```ruby
# In documentation or setup scripts
webhook_url = build_webhook_url(
  "/captain_hook/stripe",
  provider_token: "abc123xyz"
)
# => "https://app.example.com/captain_hook/stripe?token=abc123xyz"
```

**URL Construction**:
```ruby
# Uses environment variables for base URL
ENV["WEBHOOK_BASE_URL"] = "https://webhooks.myapp.com"
build_webhook_url("/captain_hook/stripe")
# => "https://webhooks.myapp.com/captain_hook/stripe"

# Falls back to HOST
ENV["HOST"] = "myapp.com"
build_webhook_url("/captain_hook/github", provider_token: "token123")
# => "https://myapp.com/captain_hook/github?token=token123"

# Without token
build_webhook_url("/captain_hook/custom")
# => "https://myapp.com/captain_hook/custom"
```

**Use Cases**:
- Generating URLs for provider dashboard registration
- Documentation generation
- Setup scripts and rake tasks
- Admin UI display

**In Admin UI**:
```ruby
# app/views/captain_hook/admin/providers/show.html.erb
<%= build_webhook_url(
  captain_hook.incoming_path(@provider.name),
  provider_token: @provider.token
) %>
```

---

## Complete Verifier Examples

### Example 1: Simple HMAC Verification

```ruby
# captain_hook/simple_api/simple_api.rb
class SimpleApiVerifier
  include CaptainHook::VerifierHelpers

  def verify_signature(payload:, headers:, provider_config:)
    # Skip if secret not configured
    return true if skip_verification?(provider_config.signing_secret)
    
    # Extract signature from header
    signature = extract_header(headers, "X-Signature")
    return false if signature.blank?
    
    # Generate expected signature
    expected = generate_hmac(provider_config.signing_secret, payload)
    
    # Constant-time comparison
    secure_compare(signature, expected)
  end

  def extract_event_id(payload)
    payload["id"]
  end

  def extract_event_type(payload)
    payload["event"]
  end
end
```

---

### Example 2: Timestamp Validation

```ruby
# captain_hook/secure_api/secure_api.rb
class SecureApiVerifier
  include CaptainHook::VerifierHelpers

  TIMESTAMP_HEADER = "X-Request-Timestamp"
  SIGNATURE_HEADER = "X-Request-Signature"

  def verify_signature(payload:, headers:, provider_config:)
    # Extract headers
    timestamp_str = extract_header(headers, TIMESTAMP_HEADER)
    signature = extract_header(headers, SIGNATURE_HEADER)
    
    return false if timestamp_str.blank? || signature.blank?
    
    # Parse and validate timestamp
    timestamp = parse_timestamp(timestamp_str)
    return false if timestamp.nil?
    
    unless timestamp_within_tolerance?(timestamp, 300)
      log_verification("secure_api", {
        error: "Timestamp expired",
        timestamp: timestamp,
        age: Time.current.to_i - timestamp
      })
      return false
    end
    
    # Generate signature including timestamp
    signed_data = "#{timestamp}.#{payload}"
    expected = generate_hmac(provider_config.signing_secret, signed_data)
    
    # Verify signature
    result = secure_compare(signature, expected)
    
    log_verification("secure_api", {
      timestamp: timestamp,
      signature_match: result
    })
    
    result
  end

  def extract_timestamp(headers)
    timestamp_str = extract_header(headers, TIMESTAMP_HEADER)
    parse_timestamp(timestamp_str)
  end

  def extract_event_id(payload)
    payload["event_id"]
  end

  def extract_event_type(payload)
    payload["type"]
  end
end
```

---

### Example 3: Complex Key-Value Header (Stripe-style)

```ruby
# captain_hook/complex_api/complex_api.rb
class ComplexApiVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Complex-Signature"

  def verify_signature(payload:, headers:, provider_config:)
    # Extract and parse signature header
    # Format: "t=1234567890,v1=sig1,v0=sig2"
    sig_header = extract_header(headers, SIGNATURE_HEADER)
    return false if sig_header.blank?
    
    parsed = parse_kv_header(sig_header)
    timestamp = parsed["t"]
    signatures = [parsed["v1"], parsed["v0"]].flatten.compact
    
    return false if timestamp.blank? || signatures.empty?
    
    # Validate timestamp
    unless timestamp_within_tolerance?(timestamp.to_i, 300)
      log_verification("complex_api", { error: "Timestamp too old" })
      return false
    end
    
    # Generate expected signature
    signed_payload = "#{timestamp}.#{payload}"
    expected = generate_hmac(provider_config.signing_secret, signed_payload)
    
    # Check if any signature matches
    result = signatures.any? { |sig| secure_compare(sig, expected) }
    
    log_verification("complex_api", {
      timestamp: timestamp,
      signature_count: signatures.length,
      match: result
    })
    
    result
  end

  def extract_timestamp(headers)
    sig_header = extract_header(headers, SIGNATURE_HEADER)
    return nil if sig_header.blank?
    
    parsed = parse_kv_header(sig_header)
    parsed["t"]&.to_i
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

### Example 4: Base64 HMAC with Multiple Headers

```ruby
# captain_hook/base64_api/base64_api.rb
class Base64ApiVerifier
  include CaptainHook::VerifierHelpers

  def verify_signature(payload:, headers:, provider_config:)
    # Try multiple header names
    signature = extract_header(
      headers,
      "X-Signature",
      "HTTP_X_SIGNATURE",
      "X-Hub-Signature"
    )
    
    return false if signature.blank?
    
    # Generate Base64 HMAC
    expected = generate_hmac_base64(provider_config.signing_secret, payload)
    
    # Verify
    secure_compare(signature, expected)
  end

  def extract_event_id(payload)
    payload["message_id"] || payload["id"]
  end

  def extract_event_type(payload)
    payload["event_type"] || payload["type"]
  end
end
```

---

### Example 5: GitHub-Style Verification

```ruby
# captain_hook/github/github.rb
class GithubVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Hub-Signature-256"

  def verify_signature(payload:, headers:, provider_config:)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return false if signature_header.blank?
    
    # GitHub format: "sha256=abc123..."
    signature = signature_header.sub(/^sha256=/, "")
    
    # Generate expected HMAC
    expected = generate_hmac(provider_config.signing_secret, payload)
    
    # Verify
    result = secure_compare(signature, expected)
    
    log_verification("github", {
      signature_format: signature_header[0..15] + "...",
      match: result
    })
    
    result
  end

  def extract_event_id(headers)
    extract_header(headers, "X-GitHub-Delivery")
  end

  def extract_event_type(headers)
    extract_header(headers, "X-GitHub-Event")
  end
end
```

---

## Security Best Practices

### Always Use Constant-Time Comparison

```ruby
# ✅ GOOD: Prevents timing attacks
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  secure_compare(signature, expected)  # Constant-time
end

# ❌ BAD: Vulnerable to timing attacks
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  signature == expected  # Variable-time comparison!
end
```

**Why It Matters**:
- Regular `==` comparison returns false as soon as it finds a difference
- Attacker can measure response time to guess signature character by character
- `secure_compare` always takes the same time regardless of where strings differ

---

### Validate Timestamps

```ruby
# ✅ GOOD: Prevents replay attacks
def verify_signature(payload:, headers:, provider_config:)
  timestamp = extract_timestamp(headers)
  
  unless timestamp_within_tolerance?(timestamp, 300)
    return false  # Reject old webhooks
  end
  
  # Verify signature...
end

# ❌ BAD: Vulnerable to replay attacks
def verify_signature(payload:, headers:, provider_config:)
  # No timestamp validation
  # Attacker can replay old webhooks indefinitely
end
```

---

### Include Timestamp in Signature

```ruby
# ✅ GOOD: Timestamp is part of signed data
def verify_signature(payload:, headers:, provider_config:)
  timestamp = extract_header(headers, "X-Timestamp")
  signature = extract_header(headers, "X-Signature")
  
  # Include timestamp in HMAC
  signed_data = "#{timestamp}.#{payload}"
  expected = generate_hmac(provider_config.signing_secret, signed_data)
  
  secure_compare(signature, expected)
end

# ❌ BAD: Timestamp separate from signature
def verify_signature(payload:, headers:, provider_config:)
  # Timestamp checked separately
  # Attacker could modify timestamp without breaking signature
  timestamp = extract_header(headers, "X-Timestamp")
  signature = extract_header(headers, "X-Signature")
  
  expected = generate_hmac(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

---

### Use Environment Variables for Secrets

```ruby
# ✅ GOOD: Secret from environment
signing_secret: ENV[WEBHOOK_SECRET]

# ❌ BAD: Hardcoded secret
signing_secret: whsec_abc123...
```

---

### Log Carefully in Production

```ruby
# ✅ GOOD: Conditional debug logging
log_verification("provider", {
  signature_match: result,
  timestamp: timestamp
})  # Only logs if debug_mode enabled

# ❌ BAD: Always logging sensitive data
Rails.logger.info "Signature: #{signature}, Secret: #{secret}"
```

---

### Handle Missing Secrets Gracefully

```ruby
# ✅ GOOD: Skip verification if secret missing (development)
def verify_signature(payload:, headers:, provider_config:)
  return true if skip_verification?(provider_config.signing_secret)
  
  # Perform verification...
end

# ❌ BAD: Crash if secret missing
def verify_signature(payload:, headers:, provider_config:)
  # This will raise NoMethodError if signing_secret is nil
  generate_hmac(provider_config.signing_secret, payload)
end
```

**Note**: Only skip verification in development/test environments!

---

## Testing Verifiers

### Testing with Helper Methods

```ruby
# test/verifiers/custom_api_verifier_test.rb
require "test_helper"

class CustomApiVerifierTest < ActiveSupport::TestCase
  setup do
    @verifier = CustomApiVerifier.new
    @secret = "test_secret_key"
    @payload = '{"event":"test"}'
    @headers = {}
  end

  test "verifies valid signature" do
    # Generate valid signature using helper
    signature = @verifier.generate_hmac(@secret, @payload)
    @headers["X-Signature"] = signature
    
    config = OpenStruct.new(signing_secret: @secret)
    
    result = @verifier.verify_signature(
      payload: @payload,
      headers: @headers,
      provider_config: config
    )
    
    assert result, "Should verify valid signature"
  end

  test "rejects invalid signature" do
    @headers["X-Signature"] = "invalid_signature"
    config = OpenStruct.new(signing_secret: @secret)
    
    result = @verifier.verify_signature(
      payload: @payload,
      headers: @headers,
      provider_config: config
    )
    
    refute result, "Should reject invalid signature"
  end

  test "rejects expired timestamp" do
    old_timestamp = Time.current.to_i - 400  # 400 seconds ago
    @headers["X-Timestamp"] = old_timestamp.to_s
    
    refute @verifier.timestamp_within_tolerance?(old_timestamp, 300),
           "Should reject timestamp older than tolerance"
  end

  test "parses key-value header" do
    header = "t=123,v1=abc,v0=xyz"
    parsed = @verifier.parse_kv_header(header)
    
    assert_equal "123", parsed["t"]
    assert_equal "abc", parsed["v1"]
    assert_equal "xyz", parsed["v0"]
  end
end
```

---

### Integration Testing

```ruby
# test/integration/webhook_verification_test.rb
require "test_helper"

class WebhookVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @provider = captain_hook_providers(:stripe)
    @secret = "test_secret"
    @payload = { event: "test" }.to_json
  end

  test "accepts webhook with valid signature" do
    verifier = StripeVerifier.new
    timestamp = Time.current.to_i
    signed_payload = "#{timestamp}.#{@payload}"
    signature = verifier.generate_hmac(@secret, signed_payload)
    
    post captain_hook.incoming_path(@provider.name, @provider.token),
         params: @payload,
         headers: {
           "Stripe-Signature" => "t=#{timestamp},v1=#{signature}",
           "Content-Type" => "application/json"
         }
    
    assert_response :created
  end

  test "rejects webhook with invalid signature" do
    post captain_hook.incoming_path(@provider.name, @provider.token),
         params: @payload,
         headers: {
           "Stripe-Signature" => "t=#{Time.current.to_i},v1=invalid",
           "Content-Type" => "application/json"
         }
    
    assert_response :unauthorized
  end
end
```

---

## Troubleshooting

### Signature Verification Fails

**Problem**: `verify_signature` returns `false` but signature should be valid

**Diagnosis**:
```ruby
# Enable debug logging
CaptainHook.configure do |config|
  config.debug_mode = true
end

# Add detailed logging to your verifier
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  
  log_verification("provider", {
    received: signature,
    expected: expected,
    match: secure_compare(signature, expected),
    payload_length: payload.bytesize,
    secret_present: provider_config.signing_secret.present?
  })
  
  secure_compare(signature, expected)
end
```

**Common causes**:
1. **Wrong payload encoding**: Raw body vs parsed body
2. **Secret mismatch**: Using wrong environment variable
3. **Header name mismatch**: Wrong header key
4. **Encoding differences**: Hex vs Base64
5. **Whitespace**: Extra newlines or spaces in payload

**Solutions**:
```ruby
# 1. Ensure raw payload (not parsed)
raw_payload = request.raw_post  # ✅ Correct
parsed = JSON.parse(raw_payload)
signature = generate_hmac(secret, parsed.to_json)  # ❌ Wrong

# 2. Check environment variable
puts "Secret: #{ENV['WEBHOOK_SECRET']}"  # Should output secret

# 3. Try multiple header names
signature = extract_header(headers, "X-Signature", "HTTP_X_SIGNATURE")

# 4. Match encoding with provider
generate_hmac(secret, payload)         # Hex
generate_hmac_base64(secret, payload)  # Base64

# 5. Use exact payload from request
payload = request.raw_post  # No modifications!
```

---

### Timing Attacks Still Possible

**Problem**: Not using `secure_compare` correctly

**Diagnosis**:
```ruby
# ❌ BAD: Checks length first (leaks information)
return false if signature.length != expected.length
return signature == expected

# ✅ GOOD: Use secure_compare
secure_compare(signature, expected)
```

**Solution**: Always use `secure_compare` for any signature comparison.

---

### Timestamp Validation Too Strict

**Problem**: Valid webhooks rejected due to clock skew

**Diagnosis**:
```ruby
# Check actual timestamp age
timestamp = extract_timestamp(headers)
age = Time.current.to_i - timestamp
puts "Timestamp age: #{age} seconds"
```

**Common causes**:
- Server clock drift
- Network latency
- Too strict tolerance (< 60 seconds)

**Solutions**:
```yaml
# Increase tolerance for production
timestamp_tolerance_seconds: 300  # 5 minutes (recommended)

# For development
timestamp_tolerance_seconds: 3600  # 1 hour (relaxed)
```

---

### Headers Not Found

**Problem**: `extract_header` returns `nil`

**Diagnosis**:
```ruby
# Log all headers
def verify_signature(payload:, headers:, provider_config:)
  Rails.logger.debug "All headers: #{headers.inspect}"
  
  signature = extract_header(headers, "X-Signature")
  Rails.logger.debug "Extracted signature: #{signature.inspect}"
end
```

**Common causes**:
- Header name mismatch (case-sensitive frameworks)
- Headers not passed correctly
- Provider changed header name

**Solutions**:
```ruby
# Try multiple variations
signature = extract_header(
  headers,
  "X-Signature",
  "HTTP_X_SIGNATURE",
  "x-signature",
  "X_Signature"
)

# Check headers object
pp headers  # Print all available headers
```

---

## Advanced Topics

### Custom HMAC Algorithms

```ruby
# SHA512 instead of SHA256
def generate_hmac_sha512(secret, data)
  OpenSSL::HMAC.hexdigest("SHA512", secret, data)
end

def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature-SHA512")
  expected = generate_hmac_sha512(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

---

### Multi-Signature Verification

```ruby
# Support multiple signature versions
def verify_signature(payload:, headers:, provider_config:)
  sig_header = extract_header(headers, "X-Signatures")
  parsed = parse_kv_header(sig_header)
  
  # Try all signature versions
  ["v3", "v2", "v1"].each do |version|
    signature = parsed[version]
    next if signature.blank?
    
    expected = generate_signature(version, payload, provider_config.signing_secret)
    return true if secure_compare(signature, expected)
  end
  
  false
end

def generate_signature(version, payload, secret)
  case version
  when "v3" then generate_hmac_sha512(secret, payload)
  when "v2" then generate_hmac_base64(secret, payload)
  when "v1" then generate_hmac(secret, payload)
  end
end
```

---

### Rate Limiting Integration

```ruby
def verify_signature(payload:, headers:, provider_config:)
  # Check signature first (cheapest operation)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  
  unless secure_compare(signature, expected)
    # Log failed attempt for rate limiting
    Rails.cache.increment("failed_signatures:#{headers['X-Real-IP']}")
    return false
  end
  
  true
end
```

---

## See Also

- [Provider Discovery](PROVIDER_DISCOVERY.md) - How verifiers are loaded
- [GEM_WEBHOOK_SETUP.md](GEM_WEBHOOK_SETUP.md) - Creating verifiers in gems
- [Verifiers](VERIFIERS.md) - Complete verifier documentation
- [TECHNICAL_PROCESS.md](../TECHNICAL_PROCESS.md) - Webhook processing flow
