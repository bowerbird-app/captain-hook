# Creating Custom Adapters

Adapters are the first line of defense in the webhook processing pipeline. They handle signature verification and metadata extraction specific to each webhook provider.

## Overview

Each webhook provider (Stripe, PayPal, GitHub, etc.) has its own signature verification scheme. Adapters encapsulate this provider-specific logic so the rest of CaptainHook remains provider-agnostic.

**CaptainHook ships with built-in adapters for:**
- Stripe (`CaptainHook::Adapters::Stripe`)
- Square (`CaptainHook::Adapters::Square`)
- PayPal (`CaptainHook::Adapters::Paypal`)
- WebhookSite (`CaptainHook::Adapters::WebhookSite`) - testing only

**You only need to create a custom adapter if your provider is not in the list above.**

## Adapter Responsibilities

An adapter must implement:

1. **Signature Verification**: Verify the webhook came from the provider
2. **Timestamp Extraction**: Extract event timestamp for replay attack prevention
3. **Event ID Extraction**: Get the unique event identifier
4. **Event Type Extraction**: Determine what type of event this is

## Using Built-in Adapters

If CaptainHook already has an adapter for your provider, simply reference it in your provider YAML:

```yaml
# captain_hook/providers/stripe.yml
name: stripe
display_name: Stripe
adapter_class: CaptainHook::Adapters::Stripe  # Use built-in adapter
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

No adapter code needed! CaptainHook handles all the signature verification.

## Creating a Custom Adapter

Only create a custom adapter if CaptainHook doesn't have a built-in one for your provider.

### Where to Put Custom Adapters

**For host Rails applications:**
- Create adapters in `app/adapters/captain_hook/adapters/`
- They will be automatically discovered by CaptainHook

**For CaptainHook gem contributions:**
- Add to `lib/captain_hook/adapters/` (see Contributing section below)

### 1. Create the Adapter Class

**Example: Custom adapter for a fictional "AcmePayments" provider**

Create `app/adapters/captain_hook/adapters/acme_payments.rb`:

```ruby
# app/adapters/captain_hook/adapters/acme_payments.rb
module CaptainHook
  module Adapters
    class AcmePayments < Base
      # Define provider-specific header names
      SIGNATURE_HEADER = "X-Acme-Signature"
      TIMESTAMP_HEADER = "X-Acme-Timestamp"

      # Implement signature verification
      def verify_signature(payload:, headers:)
        signature = headers[SIGNATURE_HEADER]
        timestamp = headers[TIMESTAMP_HEADER]
        
        return false if signature.blank? || timestamp.blank?

        # Check timestamp tolerance if enabled
        if provider_config.timestamp_validation_enabled?
          tolerance = provider_config.timestamp_tolerance_seconds || 300
          return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
        end

        # Generate expected signature using provider's algorithm
        expected = generate_hmac(provider_config.signing_secret, "#{timestamp}.#{payload}")
        secure_compare(signature, expected)
      end

      # Extract timestamp from headers
      def extract_timestamp(headers)
        headers[TIMESTAMP_HEADER]&.to_i
      end

      # Extract event ID from payload
      def extract_event_id(payload)
        payload["transaction_id"] || payload["id"]
      end

      # Extract event type from payload
      def extract_event_type(payload)
        payload["event_type"] || payload["type"]
      end

      private

      def timestamp_within_tolerance?(timestamp, tolerance)
        current_time = Time.current.to_i
        (current_time - timestamp).abs <= tolerance
      end
    end
  end
end
```

### 2. Use the Adapter

Create a provider configuration that references your custom adapter:

```yaml
# captain_hook/providers/acme_payments.yml
name: acme_payments
display_name: AcmePayments
adapter_class: CaptainHook::Adapters::AcmePayments  # Your custom adapter
signing_secret: ENV[ACME_PAYMENTS_SECRET]
```

The adapter will be automatically discovered and available in the admin UI dropdown.

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

## Example Built-in Adapters

CaptainHook includes these adapters:

### Stripe
- **Location**: `lib/captain_hook/adapters/stripe.rb`
- **Signature**: HMAC-SHA256 with timestamp validation
- **Headers**: `Stripe-Signature`
- **Format**: `t=timestamp,v1=signature,v0=fallback_signature`
- **Documentation**: https://stripe.com/docs/webhooks/signatures

### Square
- **Location**: `lib/captain_hook/adapters/square.rb`
- **Signature**: HMAC-SHA256 with Base64 encoding
- **Headers**: `X-Square-Hmacsha256-Signature`
- **Signed Data**: notification_url + request_body
- **Documentation**: https://developer.squareup.com/docs/webhooks/step3validate

### PayPal
- **Location**: `lib/captain_hook/adapters/paypal.rb`
- **Signature**: HMAC-SHA256 with transmission headers (simplified)
- **Headers**: `Paypal-Transmission-Sig`, `Paypal-Transmission-Id`, `Paypal-Transmission-Time`
- **Note**: Simplified implementation; full verification requires certificate chain
- **Documentation**: https://developer.paypal.com/api/rest/webhooks/

### WebhookSite
- **Location**: `lib/captain_hook/adapters/webhook_site.rb`
- **Signature**: No verification (always returns true)
- **Headers**: None required
- **Use Case**: Testing and development only - **DO NOT USE IN PRODUCTION**

## Security Best Practices

1. **Always verify signatures**: Never skip signature verification in production
2. **Use constant-time comparison**: Prevents timing attacks (use `secure_compare` helper)
3. **Validate timestamps**: Prevents replay attacks (enable `timestamp_tolerance_seconds`)
4. **Check payload size**: Prevents DoS attacks (set `max_payload_size_bytes`)
5. **Rate limit**: Prevents abuse (set `rate_limit_requests` and `rate_limit_period`)
6. **Use HTTPS**: Always use HTTPS for webhook endpoints in production
7. **Rotate secrets**: Periodically rotate signing secrets
8. **Test thoroughly**: Use sandbox mode before deploying to production

## Environment Variable Override

Adapters automatically support ENV variable override for signing secrets:

```bash
# .env
STRIPE_WEBHOOK_SECRET=whsec_your_secret_here
SQUARE_WEBHOOK_SECRET=your_square_secret
PAYPAL_WEBHOOK_ID=your_paypal_webhook_id
```

This overrides the database value when set, useful for:
- Local development with different secrets
- Production secrets in secure vaults
- CI/CD pipelines
- Multi-environment deployments

## Contributing Built-in Adapters

Want to contribute an adapter for a popular provider? We'd love to include it!

### Requirements

1. **Provider must be widely used** - Focus on popular payment processors, SaaS platforms, etc.
2. **Proper signature verification** - Implement the provider's official verification scheme
3. **Complete implementation** - All 4 required methods (verify_signature, extract_timestamp, extract_event_id, extract_event_type)
4. **Tests** - Include unit tests demonstrating signature verification
5. **Documentation** - Link to provider's webhook documentation

### Steps to Contribute

1. **Create adapter** in `lib/captain_hook/adapters/your_provider.rb`
2. **Add require statement** to `lib/captain_hook.rb`
3. **Create example provider YAML** in `captain_hook/providers/your_provider.yml.example`
4. **Write tests** in `test/adapters/your_provider_test.rb`
5. **Update this document** with your adapter details
6. **Submit pull request** with a clear description

**Example PR structure:**
```
- lib/captain_hook/adapters/shopify.rb (adapter code)
- lib/captain_hook.rb (add require)
- captain_hook/providers/shopify.yml.example (template)
- test/adapters/shopify_test.rb (tests)
- docs/ADAPTERS.md (documentation update)
```

## Need Help?

- Check existing adapters in `lib/captain_hook/adapters/` for examples
- Review provider documentation for their signature verification scheme
- Test in sandbox mode first (`/captain_hook/admin/sandbox`)
- Open a GitHub issue if you need guidance
- Join our community discussions for support
