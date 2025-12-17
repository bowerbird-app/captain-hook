# Custom Adapters Guide

This guide explains how to create custom webhook adapters for providers not included in CaptainHook's built-in adapters.

## What are Adapters?

Adapters are responsible for:
- **Signature Verification**: Validating that webhooks are authentic
- **Event Type Extraction**: Identifying what type of event occurred
- **Event ID Extraction**: Getting unique identifiers for deduplication
- **Timestamp Extraction**: Getting event timestamps for time-based validation

## Example Adapters

CaptainHook doesn't bundle adapters in the engine. Instead, adapters live in your application or gems. Example adapters are available in the test/dummy app for reference:

- `CaptainHook::Adapters::Stripe` - Stripe webhook verification
- `CaptainHook::Adapters::Square` - Square webhook verification  
- `CaptainHook::Adapters::Paypal` - PayPal webhook verification (simplified)
- `CaptainHook::Adapters::WebhookSite` - webhook.site testing (no verification)
- `CaptainHook::Adapters::Base` - Base class with no-op verification

You can copy these adapters to your application's `app/adapters/captain_hook/adapters/` directory and customize them as needed.

## Creating a Custom Adapter

### Step 1: Create the Adapter Class

Create a file in `app/adapters/captain_hook/adapters/your_provider.rb`:

```ruby
# app/adapters/captain_hook/adapters/your_provider.rb
module CaptainHook
  module Adapters
    class YourProvider < Base
      # Required: Verify webhook signature
      def verify_signature(payload:, headers:)
        signature = headers["X-Your-Provider-Signature"]
        return false if signature.blank?

        expected = generate_signature(payload)
        ActiveSupport::SecurityUtils.secure_compare(signature, expected)
      end

      # Required: Extract event type from payload
      def extract_event_type(payload)
        payload["event_type"] || "unknown"
      end

      # Optional: Extract event ID
      def extract_event_id(payload)
        payload["event_id"]
      end

      # Optional: Extract timestamp
      def extract_timestamp(payload)
        Time.at(payload["timestamp"]) if payload["timestamp"]
      end

      private

      def generate_signature(payload)
        OpenSSL::HMAC.hexdigest("SHA256", signing_secret, payload)
      end
    end
  end
end
```

### Step 2: Create Provider Configuration

Create a YAML file in `captain_hook/providers/your_provider.yml`:

```yaml
name: your_provider
display_name: Your Provider
adapter_class: CaptainHook::Adapters::YourProvider
signing_secret_env: YOUR_PROVIDER_WEBHOOK_SECRET
active: true
```

### Step 3: Scan for Providers

Run the provider scan in the admin UI or via console:

```ruby
CaptainHook::Services::ProviderDiscovery.new.call
CaptainHook::Services::ProviderSync.new.call(provider_definitions)
```

## Adapter Methods Reference

### Required Methods

#### `verify_signature(payload:, headers:)`

Verifies the webhook signature to ensure authenticity.

**Parameters:**
- `payload` (String): Raw request body
- `headers` (Hash): Request headers

**Returns:** Boolean - `true` if valid, `false` otherwise

**Example:**
```ruby
def verify_signature(payload:, headers:)
  signature = headers["X-Signature"]
  return false if signature.blank?

  expected = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, payload)
  ActiveSupport::SecurityUtils.secure_compare(signature, expected)
end
```

#### `extract_event_type(payload)`

Extracts the event type identifier from the webhook payload.

**Parameters:**
- `payload` (Hash): Parsed JSON payload

**Returns:** String - Event type identifier

**Example:**
```ruby
def extract_event_type(payload)
  payload.dig("data", "type") || payload["type"] || "unknown"
end
```

### Optional Methods

#### `extract_event_id(payload)`

Extracts a unique event identifier for idempotency.

**Parameters:**
- `payload` (Hash): Parsed JSON payload

**Returns:** String or nil

**Example:**
```ruby
def extract_event_id(payload)
  payload["id"] || payload.dig("event", "id")
end
```

#### `extract_timestamp(payload)`

Extracts the event timestamp for time-based validation.

**Parameters:**
- `payload` (Hash): Parsed JSON payload

**Returns:** Time or nil

**Example:**
```ruby
def extract_timestamp(payload)
  timestamp = payload["created_at"] || payload["timestamp"]
  Time.parse(timestamp) if timestamp
rescue ArgumentError
  nil
end
```

## Common Signature Verification Patterns

### HMAC-SHA256 (Most Common)

```ruby
def verify_signature(payload:, headers:)
  signature = headers["X-Signature"]
  return false if signature.blank?

  expected = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, payload)
  ActiveSupport::SecurityUtils.secure_compare(signature, expected)
end
```

### HMAC with Timestamp (Stripe-style)

```ruby
def verify_signature(payload:, headers:)
  signature_header = headers["X-Signature"]
  return false if signature_header.blank?

  timestamp, signature = parse_signature_header(signature_header)
  
  # Check timestamp tolerance
  return false if (Time.now.to_i - timestamp).abs > 300

  signed_payload = "#{timestamp}.#{payload}"
  expected = OpenSSL::HMAC.hexdigest("SHA256", signing_secret, signed_payload)
  
  ActiveSupport::SecurityUtils.secure_compare(signature, expected)
end

private

def parse_signature_header(header)
  # Parse "t=1234567890,v1=abc123..."
  parts = header.split(",").map { |p| p.split("=") }.to_h
  [parts["t"].to_i, parts["v1"]]
end
```

### JWT Signature

```ruby
def verify_signature(payload:, headers:)
  token = headers["Authorization"]&.remove("Bearer ")
  return false if token.blank?

  JWT.decode(token, signing_secret, true, algorithm: "HS256")
  true
rescue JWT::DecodeError
  false
end
```

### No Signature (Testing Only)

```ruby
def verify_signature(payload:, headers:)
  # For testing or providers without signature verification
  # NOT recommended for production!
  true
end
```

## Testing Your Adapter

Create a test file `test/adapters/your_provider_test.rb`:

```ruby
require "test_helper"

module CaptainHook
  module Adapters
    class YourProviderTest < ActiveSupport::TestCase
      setup do
        @adapter = YourProvider.new(signing_secret: "test_secret")
      end

      test "verifies valid signature" do
        payload = '{"event_type":"test"}'
        signature = OpenSSL::HMAC.hexdigest("SHA256", "test_secret", payload)
        headers = { "X-Signature" => signature }

        assert @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "rejects invalid signature" do
        payload = '{"event_type":"test"}'
        headers = { "X-Signature" => "invalid" }

        refute @adapter.verify_signature(payload: payload, headers: headers)
      end

      test "extracts event type" do
        payload = { "event_type" => "user.created" }
        assert_equal "user.created", @adapter.extract_event_type(payload)
      end
    end
  end
end
```

## Using in Gems

If you're creating a gem with custom adapters:

1. Place adapters in `lib/your_gem/adapters/`
2. Namespace them appropriately
3. Create provider YAML files in `captain_hook/providers/`
4. Users will scan for providers and your adapter will be loaded

Example gem structure:
```
your_gem/
├── lib/
│   └── captain_hook/
│       └── adapters/
│           └── your_provider.rb
└── captain_hook/
    └── providers/
        └── your_provider.yml
```

## Best Practices

1. **Always use `ActiveSupport::SecurityUtils.secure_compare`** for signature comparison to prevent timing attacks
2. **Validate timestamps** when possible to prevent replay attacks
3. **Extract event IDs** to enable idempotency checks
4. **Handle missing headers gracefully** - return `false` instead of raising errors
5. **Log verification failures** for debugging (but not sensitive data)
6. **Test with real webhook examples** from the provider
7. **Document required headers** in your adapter comments

## Troubleshooting

### Signature Verification Fails

1. Check the signing secret matches what the provider expects
2. Verify you're using the raw request body (not parsed JSON)
3. Check header names (case-sensitive)
4. Look for whitespace or encoding issues
5. Review the provider's documentation for algorithm details

### Event Type Not Found

1. Inspect the actual webhook payload structure
2. Check for nested fields using `dig`
3. Handle multiple possible locations for event type
4. Provide a sensible default ("unknown")

### Adapter Not Loading

1. Ensure file is in `app/adapters/captain_hook/adapters/`
2. Check class name matches file name
3. Verify module nesting is correct
4. Restart Rails server after creating new adapters
