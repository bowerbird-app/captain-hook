# Creating Custom Adapters

Adapters are the first line of defense in the webhook processing pipeline. They handle signature verification and metadata extraction specific to each webhook provider.

## Overview

Each webhook provider (Stripe, PayPal, GitHub, etc.) has its own signature verification scheme. Adapters encapsulate this provider-specific logic so the rest of CaptainHook remains provider-agnostic.

## Adapter Responsibilities

An adapter must implement:

1. **Signature Verification**: Verify the webhook came from the provider
2. **Timestamp Extraction**: Extract event timestamp for replay attack prevention
3. **Event ID Extraction**: Get the unique event identifier
4. **Event Type Extraction**: Determine what type of event this is

## Creating a New Adapter

### 1. Create the Adapter Class

Create a new file in `lib/captain_hook/adapters/`:

```ruby
# lib/captain_hook/adapters/paypal.rb
module CaptainHook
  module Adapters
    class Paypal < Base
      # Define provider-specific header names
      SIGNATURE_HEADER = "Paypal-Transmission-Sig"
      TRANSMISSION_ID_HEADER = "Paypal-Transmission-Id"
      TRANSMISSION_TIME_HEADER = "Paypal-Transmission-Time"

      # Implement signature verification
      def verify_signature(payload:, headers:)
        signature = headers[SIGNATURE_HEADER]
        transmission_id = headers[TRANSMISSION_ID_HEADER]
        transmission_time = headers[TRANSMISSION_TIME_HEADER]
        
        # Provider-specific verification logic
        # Return true if valid, false otherwise
      end

      # Extract timestamp from headers
      def extract_timestamp(headers)
        time_str = headers[TRANSMISSION_TIME_HEADER]
        Time.parse(time_str).to_i rescue nil
      end

      # Extract event ID from payload
      def extract_event_id(payload)
        payload["id"]
      end

      # Extract event type from payload
      def extract_event_type(payload)
        payload["event_type"]
      end
    end
  end
end
```

### 2. Register the Adapter

Add the require statement to `lib/captain_hook.rb`:

```ruby
# Load adapters
require "captain_hook/adapters/base"
require "captain_hook/adapters/stripe"
require "captain_hook/adapters/paypal"  # Add this line
```

### 3. Use the Adapter

Create a provider using your adapter:

#### Via Admin UI

1. Navigate to `/captain_hook/admin/providers/new`
2. Set **Name**: `paypal`
3. Set **Adapter Class**: `CaptainHook::Adapters::Paypal`
4. Set **Signing Secret**: Your PayPal webhook ID or secret
5. Save

#### Via Rails Console

```ruby
CaptainHook::Provider.create!(
  name: "paypal",
  adapter_class: "CaptainHook::Adapters::Paypal",
  signing_secret: "your-webhook-id-or-secret"
)
```

## Available Helper Methods

All adapters inherit from `Base` and have access to these helpers:

### `secure_compare(a, b)`
Constant-time string comparison to prevent timing attacks:

```ruby
secure_compare(received_signature, expected_signature)
```

### `generate_hmac(secret, data)`
Generate HMAC-SHA256 signature:

```ruby
expected_sig = generate_hmac(provider_config.signing_secret, payload)
```

### Provider Config Access

Access provider settings via `provider_config`:

```ruby
provider_config.signing_secret          # Signing secret
provider_config.timestamp_tolerance_seconds  # Time tolerance
provider_config.timestamp_validation_enabled?  # Check if enabled
```

## Common Signature Verification Patterns

### HMAC-SHA256 (Stripe-style)

```ruby
def verify_signature(payload:, headers:)
  signature = headers["X-Signature"]
  timestamp = headers["X-Timestamp"]
  
  signed_payload = "#{timestamp}.#{payload}"
  expected = generate_hmac(provider_config.signing_secret, signed_payload)
  
  secure_compare(signature, expected)
end
```

### Header Token (Simple)

```ruby
def verify_signature(payload:, headers:)
  token = headers["X-Webhook-Token"]
  secure_compare(token, provider_config.signing_secret)
end
```

### JSON Web Token (JWT)

```ruby
require 'jwt'

def verify_signature(payload:, headers:)
  token = headers["Authorization"]&.gsub(/^Bearer /, '')
  
  JWT.decode(token, provider_config.signing_secret, true, algorithm: 'HS256')
  true
rescue JWT::VerificationError, JWT::DecodeError
  false
end
```

### Certificate-based (GitHub-style)

```ruby
def verify_signature(payload:, headers:)
  signature = headers["X-Hub-Signature-256"]
  expected = "sha256=" + generate_hmac(provider_config.signing_secret, payload)
  
  secure_compare(signature, expected)
end
```

## Testing Your Adapter

### Unit Test

```ruby
# test/adapters/paypal_test.rb
require 'test_helper'

class PaypalAdapterTest < ActiveSupport::TestCase
  def setup
    @config = CaptainHook::ProviderConfig.new(
      signing_secret: "test-secret",
      timestamp_tolerance_seconds: 300
    )
    @adapter = CaptainHook::Adapters::Paypal.new(@config)
  end

  test "verifies valid signature" do
    payload = '{"id":"evt_123","event_type":"PAYMENT.CAPTURE.COMPLETED"}'
    headers = {
      "Paypal-Transmission-Sig" => "valid-signature",
      "Paypal-Transmission-Id" => "unique-id",
      "Paypal-Transmission-Time" => Time.current.iso8601
    }
    
    assert @adapter.verify_signature(payload: payload, headers: headers)
  end
end
```

### Integration Test

Use the sandbox to test with real payloads:

1. Go to `/captain_hook/admin/sandbox`
2. Select your PayPal provider
3. Paste a real PayPal webhook payload
4. Click "Test Webhook" (dry-run mode)

## Example Adapters

### Stripe
- **Location**: `lib/captain_hook/adapters/stripe.rb`
- **Signature**: HMAC-SHA256 with timestamp
- **Headers**: `Stripe-Signature`
- **Format**: `t=timestamp,v1=signature`

### PayPal
- **Location**: `lib/captain_hook/adapters/paypal.rb`
- **Signature**: HMAC-SHA256 with transmission headers
- **Headers**: `Paypal-Transmission-Sig`, `Paypal-Transmission-Id`, etc.
- **Verification**: Complex cert chain (simplified in this implementation)

### WebhookSite
- **Location**: `lib/captain_hook/adapters/webhook_site.rb`
- **Signature**: Simple token comparison
- **Headers**: `X-Webhook-Token`
- **Use Case**: Testing and development only

## Security Best Practices

1. **Always verify signatures**: Never skip signature verification in production
2. **Use constant-time comparison**: Prevents timing attacks (use `secure_compare`)
3. **Validate timestamps**: Prevents replay attacks
4. **Check payload size**: Prevents DoS attacks (handled by provider config)
5. **Rate limit**: Prevents abuse (handled by provider config)
6. **Use HTTPS**: Always use HTTPS for webhook endpoints in production
7. **Rotate secrets**: Periodically rotate signing secrets

## Environment Variable Override

Adapters automatically support ENV variable override for signing secrets:

```bash
# .env
PAYPAL_WEBHOOK_SECRET=whsec_your_secret_here
```

This overrides the database value when set, useful for:
- Local development with different secrets
- Production secrets in secure vaults
- CI/CD pipelines

## Need Help?

- Check existing adapters in `lib/captain_hook/adapters/`
- Review provider documentation for their signature verification
- Test in sandbox mode first (`/captain_hook/admin/sandbox`)
- Ask in GitHub issues if you need guidance
