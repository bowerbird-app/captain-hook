# Verifier Helpers Guide

The `CaptainHook::VerifierHelpers` module provides reusable helper methods for webhook signature verification, header extraction, HMAC generation, and timestamp validation. These helpers can be used in:

1. Custom webhook verifiers (provider-specific)
2. Host application code
3. Other gems that need webhook verification logic

## Usage in Custom Verifiers

When creating a custom verifier in your provider directory, include the helpers module:

```ruby
# captain_hook/providers/my_provider/my_provider.rb
class MyProviderVerifier
  include CaptainHook::VerifierHelpers
  
  def verify_signature(payload:, headers:, provider_config:)
    # Extract signature from custom header
    signature = extract_header(headers, "X-MyProvider-Signature")
    return false if signature.blank?
    
    # Skip verification if not configured
    return true if skip_verification?(provider_config.signing_secret)
    
    # Generate expected signature
    expected = generate_hmac(provider_config.signing_secret, payload)
    
    # Secure comparison
    secure_compare(signature, expected)
  end
  
  def extract_event_id(payload)
    payload["id"]
  end
  
  def extract_event_type(payload)
    payload["type"]
  end
end
```

## Usage in Host Application

You can use the helpers directly in your Rails application:

```ruby
class WebhookVerificationService
  include CaptainHook::VerifierHelpers
  
  def verify_custom_webhook(request)
    signature = extract_header(request.headers, "X-Custom-Signature")
    timestamp = extract_header(request.headers, "X-Timestamp")
    
    # Validate timestamp
    return false unless timestamp_within_tolerance?(timestamp.to_i, 300)
    
    # Generate and compare signature
    expected = generate_hmac(ENV['WEBHOOK_SECRET'], request.raw_post)
    secure_compare(signature, expected)
  end
end
```

## Usage in Other Gems

Other gems can include and use the helpers:

```ruby
# In your gem
require 'captain_hook'

module MyGem
  class WebhookAction
    include CaptainHook::VerifierHelpers
    
    def process_webhook(payload, headers)
      # Use helper methods
      signature = extract_header(headers, "X-Signature")
      timestamp = parse_timestamp(headers["X-Timestamp"])
      
      if timestamp_within_tolerance?(timestamp, 300)
        # Process webhook
      end
    end
  end
end
```

## Available Helper Methods

### Signature Verification

#### `secure_compare(a, b)`
Constant-time string comparison to prevent timing attacks.

```ruby
secure_compare("abc123", signature) # => true/false
```

#### `generate_hmac(secret, data)`
Generate HMAC-SHA256 signature (hexadecimal).

```ruby
signature = generate_hmac("my_secret", "payload_data")
# => "a1b2c3d4..."
```

#### `generate_hmac_base64(secret, data)`
Generate HMAC-SHA256 signature (Base64-encoded). Used by Square and similar providers.

```ruby
signature = generate_hmac_base64("my_secret", "payload_data")
# => "SGVsbG8gV29ybGQ="
```

#### `generate_hmac_sha1(secret, data)`
Generate HMAC-SHA1 signature (hexadecimal). Used by older providers.

```ruby
signature = generate_hmac_sha1("my_secret", "payload_data")
```

### Header Extraction

#### `extract_header(headers, key)`
Extract header value with multiple fallback strategies. Handles various formats:
- Direct key lookup
- Case variations (downcase, upcase)
- HTTP_ prefix variations

```ruby
signature = extract_header(headers, "X-Webhook-Signature")
# Works with: "X-Webhook-Signature", "x-webhook-signature", 
#            "HTTP_X_WEBHOOK_SIGNATURE", etc.
```

### Timestamp Validation

#### `timestamp_within_tolerance?(timestamp, tolerance = 300)`
Check if timestamp is within tolerance window (default: 5 minutes).

```ruby
timestamp_within_tolerance?(1234567890, 300) # => true/false
```

#### `parse_timestamp(timestamp_str)`
Parse ISO 8601 timestamp string to Unix timestamp.

```ruby
timestamp = parse_timestamp("2024-01-16T12:00:00Z")
# => 1705406400
```

### Configuration Helpers

#### `skip_verification?(secret)`
Check if signature verification should be skipped (blank or "skip").

```ruby
skip_verification?("") # => true
skip_verification?("skip") # => true
skip_verification?("real_secret") # => false
```

### URL Building

#### `build_webhook_url(path, provider_token: nil)`
Build full webhook URL. Auto-detects environment (Codespaces, production, local).

```ruby
url = build_webhook_url("/webhooks/stripe", provider_token: "abc123")
# => "https://myapp.com/webhooks/stripe/abc123"
```

#### `detect_base_url`
Detect the base URL of the application.

```ruby
base = detect_base_url
# => "https://myapp.com" or "http://localhost:3000"
```

### Header Parsing

#### `parse_kv_header(header, separator: "=")`
Parse comma-separated key-value pairs from header (e.g., Stripe format).

```ruby
parsed = parse_kv_header("t=123,v1=abc,v0=def")
# => {"t" => "123", "v1" => "abc", "v0" => "def"}

# Supports multiple values for same key
parsed = parse_kv_header("v1=abc,v1=def")
# => {"v1" => ["abc", "def"]}
```

### Payload Parsing

#### `extract_event_fields(payload)`
Extract common event fields from payload.

```ruby
fields = extract_event_fields(payload)
# => {id: "evt_123", type: "payment.success", timestamp: 1234567890}
```

### Debugging

#### `log_verification(provider, details = {})`
Log signature verification details (development/test only).

```ruby
log_verification("stripe", 
  "Signature" => "present",
  "Timestamp" => "1234567890",
  "Result" => "✓ Passed")
```

## Example: Custom Webhook Provider

Here's a complete example of creating a custom verifier using the helpers:

```ruby
module CaptainHook
  module Verifiers
    class Shopify < Base
      SIGNATURE_HEADER = "X-Shopify-Hmac-Sha256"
      
      def verify_signature(payload:, headers:)
        # Extract signature using helper
        signature = extract_header(headers, SIGNATURE_HEADER)
        
        # Log for debugging
        log_verification("shopify", "Verifying" => "started")
        
        # Skip if not configured
        return true if skip_verification?(provider_config.signing_secret)
        
        return false if signature.blank?
        
        # Shopify uses Base64-encoded HMAC
        expected = generate_hmac_base64(provider_config.signing_secret, payload)
        
        # Secure comparison
        result = secure_compare(signature, expected)
        log_verification("shopify", "Result" => result ? "✓" : "✗")
        result
      end
      
      def extract_event_type(payload)
        # Use helper for common patterns
        extract_event_fields(payload)[:type] || "shopify.webhook"
      end
    end
  end
end
```

## Example: Standalone Usage

Use helpers outside of verifiers:

```ruby
class MyWebhookService
  include CaptainHook::VerifierHelpers
  
  def verify_github_webhook(request)
    signature = extract_header(request.headers, "X-Hub-Signature-256")
    signature = signature.sub("sha256=", "") if signature.present?
    
    expected = generate_hmac(ENV["GITHUB_WEBHOOK_SECRET"], request.raw_post)
    
    if secure_compare(signature, expected)
      process_webhook(request.body)
    else
      Rails.logger.warn "GitHub webhook signature verification failed"
      false
    end
  end
  
  def verify_twilio_webhook(request)
    # Twilio includes timestamp in signature
    timestamp = extract_header(request.headers, "X-Twilio-Timestamp")
    
    # Check timestamp freshness
    return false unless timestamp_within_tolerance?(timestamp.to_i, 600)
    
    # Verify signature with timestamp
    signature = extract_header(request.headers, "X-Twilio-Signature")
    data = "#{request.url}#{timestamp}#{request.raw_post}"
    expected = generate_hmac(ENV["TWILIO_AUTH_TOKEN"], data)
    
    secure_compare(signature, expected)
  end
end
```

## Best Practices

1. **Always use `secure_compare`** for signature comparison to prevent timing attacks
2. **Use `skip_verification?`** to handle missing configuration gracefully
3. **Use `extract_header`** for robust header extraction across different environments
4. **Validate timestamps** when providers include them to prevent replay attacks
5. **Use `log_verification`** during development to debug signature issues
6. **Choose the right HMAC method**:
   - `generate_hmac`: Most common (hex-encoded SHA256)
   - `generate_hmac_base64`: For providers like Square
   - `generate_hmac_sha1`: For older providers

## Testing with Helpers

```ruby
RSpec.describe MyWebhookService do
  include CaptainHook::VerifierHelpers
  
  let(:secret) { "test_secret" }
  let(:payload) { '{"event": "test"}' }
  
  it "generates valid HMAC signature" do
    signature = generate_hmac(secret, payload)
    expect(signature).to match(/^[a-f0-9]{64}$/)
  end
  
  it "performs secure comparison" do
    sig1 = generate_hmac(secret, payload)
    sig2 = generate_hmac(secret, payload)
    
    expect(secure_compare(sig1, sig2)).to be true
  end
  
  it "validates timestamps" do
    current = Time.current.to_i
    old = current - 600
    
    expect(timestamp_within_tolerance?(current, 300)).to be true
    expect(timestamp_within_tolerance?(old, 300)).to be false
  end
end
```

## Environment Variables

The helpers respect these environment variables:

- `APP_URL`: Explicit base URL for webhooks
- `CODESPACES`: Enables Codespaces URL detection
- `CODESPACE_NAME`: Codespace identifier
- `HEROKU_APP_NAME`: Heroku app name
- `PORT`: Server port (default: 3000)
- `RAILS_ENV`: Environment (affects logging)

## Thread Safety

All helper methods are thread-safe and can be used in multi-threaded environments like Puma or Sidekiq.
