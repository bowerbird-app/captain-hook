# Verifier Helpers

The `CaptainHook::VerifierHelpers` module provides reusable utility methods for building webhook verifiers. These helpers handle common security operations, header parsing, and timestamp validation.

## Usage

Include the module in your verifier class:

```ruby
class MyProviderVerifier
  include CaptainHook::VerifierHelpers

  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, "X-Signature")
    expected = generate_hmac(provider_config.signing_secret, payload)
    secure_compare(signature, expected)
  end
end
```

## Available Helper Methods

### Security Methods

#### `secure_compare(a, b)`

Constant-time string comparison to prevent timing attacks. Always use this when comparing signatures or secrets.

```ruby
def verify_signature(payload:, headers:, provider_config:)
  received = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  secure_compare(received, expected)
end
```

**Returns:** `true` if strings match, `false` otherwise

**Note:** Returns `false` if either string is blank or if lengths don't match.

#### `skip_verification?(signing_secret)`

Check if signature verification should be skipped. Returns `true` if the signing secret is blank or contains an ENV placeholder (e.g., `ENV[WEBHOOK_SECRET]`).

```ruby
def verify_signature(payload:, headers:, provider_config:)
  return true if skip_verification?(provider_config.signing_secret)
  
  # ... perform verification
end
```

**Use case:** Useful for development/testing environments where you don't have real webhook secrets configured.

### HMAC Generation

#### `generate_hmac(secret, data)`

Generate HMAC-SHA256 signature, hex-encoded.

```ruby
def verify_signature(payload:, headers:, provider_config:)
  expected = generate_hmac(provider_config.signing_secret, payload)
  received = extract_header(headers, "X-Signature")
  secure_compare(expected, received)
end
```

**Parameters:**
- `secret` (String) - The signing secret
- `data` (String) - The data to sign

**Returns:** Hex-encoded HMAC signature (lowercase)

#### `generate_hmac_base64(secret, data)`

Generate HMAC-SHA256 signature, Base64-encoded.

```ruby
def verify_signature(payload:, headers:, provider_config:)
  expected = generate_hmac_base64(provider_config.signing_secret, payload)
  received = extract_header(headers, "X-Signature")
  secure_compare(expected, received)
end
```

**Parameters:**
- `secret` (String) - The signing secret
- `data` (String) - The data to sign

**Returns:** Base64-encoded HMAC signature (strict encoding, no padding)

### Header Parsing

#### `extract_header(headers, *keys)`

Extract header value with case-insensitive matching. Tries multiple keys in order and returns the first non-blank value.

```ruby
def verify_signature(payload:, headers:, provider_config:)
  # Will try "X-Signature", "x-signature", "X-SIGNATURE"
  signature = extract_header(headers, "X-Signature")
  
  # Try multiple header names
  signature = extract_header(headers, "X-Hub-Signature-256", "X-Hub-Signature")
end
```

**Parameters:**
- `headers` (Hash) - Request headers hash
- `keys` (Array<String>) - Header keys to try (variable arguments)

**Returns:** Header value (String) or `nil` if not found

#### `parse_kv_header(header_value)`

Parse key-value header format (e.g., Stripe's signature header: `t=123,v1=abc,v0=xyz`).

```ruby
def extract_timestamp(headers)
  signature_header = extract_header(headers, "Stripe-Signature")
  parsed = parse_kv_header(signature_header)
  # => { "t" => "123", "v1" => "abc", "v0" => "xyz" }
  
  timestamp = parsed["t"]
  signatures = [parsed["v1"], parsed["v0"]].compact
end
```

**Parameters:**
- `header_value` (String) - Header value to parse

**Returns:** Hash of key-value pairs. If a key appears multiple times, the value becomes an array.

**Example:**
```ruby
parse_kv_header("t=1234567890,v1=abc123,v0=xyz789")
# => { "t" => "1234567890", "v1" => "abc123", "v0" => "xyz789" }

parse_kv_header("a=1,b=2,a=3")
# => { "a" => ["1", "3"], "b" => "2" }
```

### Timestamp Validation

#### `timestamp_within_tolerance?(timestamp, tolerance)`

Check if a timestamp is within acceptable tolerance to prevent replay attacks.

```ruby
def verify_signature(payload:, headers:, provider_config:)
  timestamp = extract_timestamp(headers).to_i
  tolerance = provider_config.timestamp_tolerance_seconds || 300
  
  unless timestamp_within_tolerance?(timestamp, tolerance)
    return false # Timestamp too old or too far in future
  end
  
  # ... verify signature
end
```

**Parameters:**
- `timestamp` (Integer) - Unix timestamp to check
- `tolerance` (Integer) - Maximum age in seconds

**Returns:** `true` if timestamp is within tolerance, `false` otherwise

**Note:** Checks both past and future timestamps (uses absolute difference).

#### `parse_timestamp(time_string)`

Parse timestamp from various formats. Supports Unix timestamps, ISO8601, and RFC3339.

```ruby
parse_timestamp("1234567890")          # => 1234567890
parse_timestamp(1234567890)            # => 1234567890
parse_timestamp("2024-01-27T12:00:00Z") # => 1706356800
```

**Parameters:**
- `time_string` (String, Integer) - Timestamp in various formats

**Returns:** Unix timestamp (Integer) or `nil` if parsing fails

### Debugging

#### `log_verification(provider, details)`

Log signature verification details when debug mode is enabled.

```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  expected = generate_hmac(provider_config.signing_secret, payload)
  
  log_verification("my_provider", {
    "Received Signature": signature,
    "Expected Signature": expected,
    "Match": secure_compare(signature, expected)
  })
  
  secure_compare(signature, expected)
end
```

**Parameters:**
- `provider` (String) - Provider name
- `details` (Hash) - Details to log

**Output:** Only logs when `CaptainHook.configuration.debug_mode` is enabled.

### URL Building

#### `build_webhook_url(path, provider_token: nil)`

Build full webhook URL from path and optional token.

```ruby
webhook_url = build_webhook_url("/captain_hook/stripe")
# => "https://example.com/captain_hook/stripe"

webhook_url = build_webhook_url("/captain_hook/stripe", provider_token: "abc123")
# => "https://example.com/captain_hook/stripe?token=abc123"
```

**Parameters:**
- `path` (String) - Webhook path
- `provider_token` (String, optional) - Provider token for URL

**Returns:** Full webhook URL (String)

## Complete Example

Here's a complete verifier using multiple helpers:

```ruby
# captain_hook/my_provider/my_provider.rb
class MyProviderVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "X-Provider-Signature"
  TIMESTAMP_HEADER = "X-Provider-Timestamp"
  TIMESTAMP_TOLERANCE = 300 # 5 minutes

  def verify_signature(payload:, headers:, provider_config:)
    # Skip if no secret configured
    return true if skip_verification?(provider_config.signing_secret)

    # Extract headers
    signature = extract_header(headers, SIGNATURE_HEADER)
    timestamp = extract_header(headers, TIMESTAMP_HEADER)
    
    return false if signature.blank? || timestamp.blank?

    # Validate timestamp
    unless timestamp_within_tolerance?(timestamp.to_i, TIMESTAMP_TOLERANCE)
      log_verification("my_provider", {
        "Error": "Timestamp out of tolerance",
        "Timestamp": timestamp,
        "Current Time": Time.current.to_i
      })
      return false
    end

    # Generate expected signature
    signed_payload = "#{timestamp}.#{payload}"
    expected = generate_hmac(provider_config.signing_secret, signed_payload)

    # Compare signatures
    result = secure_compare(signature, expected)
    
    log_verification("my_provider", {
      "Received": signature,
      "Expected": expected,
      "Match": result
    })
    
    result
  end

  def extract_timestamp(headers)
    timestamp = extract_header(headers, TIMESTAMP_HEADER)
    parse_timestamp(timestamp)
  end

  def extract_event_id(payload)
    payload["event_id"] || payload["id"]
  end

  def extract_event_type(payload)
    payload["event_type"] || payload["type"]
  end
end
```

## Best Practices

### 1. Always Use Constant-Time Comparison

❌ **Don't do this:**
```ruby
signature == expected  # Vulnerable to timing attacks
```

✅ **Do this:**
```ruby
secure_compare(signature, expected)  # Safe
```

### 2. Validate Timestamps

Always validate timestamps to prevent replay attacks:

```ruby
def verify_signature(payload:, headers:, provider_config:)
  timestamp = extract_timestamp(headers)
  tolerance = provider_config.timestamp_tolerance_seconds || 300
  
  unless timestamp_within_tolerance?(timestamp, tolerance)
    return false
  end
  
  # ... rest of verification
end
```

### 3. Handle Missing Secrets Gracefully

```ruby
def verify_signature(payload:, headers:, provider_config:)
  # Allow webhooks through in development if secret not configured
  return true if skip_verification?(provider_config.signing_secret)
  
  # ... perform verification
end
```

### 4. Use Case-Insensitive Header Extraction

Headers can arrive in different cases, so always use `extract_header`:

```ruby
# Will find "X-Signature", "x-signature", "X-SIGNATURE", etc.
signature = extract_header(headers, "X-Signature")
```

### 5. Try Multiple Signature Versions

Some providers send multiple signature versions:

```ruby
def verify_signature(payload:, headers:, provider_config:)
  parsed = parse_kv_header(signature_header)
  signatures = [parsed["v1"], parsed["v0"]].flatten.compact
  
  expected = generate_hmac(provider_config.signing_secret, payload)
  
  # Accept if any version matches
  signatures.any? { |sig| secure_compare(sig, expected) }
end
```

## See Also

- [Creating Custom Verifiers](VERIFIERS.md)
- [Provider Discovery](PROVIDER_DISCOVERY.md)
- [Built-in Verifiers Examples](../lib/captain_hook/verifiers/)
