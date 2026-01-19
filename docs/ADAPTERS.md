# Provider Adapters

Adapters are the first line of defense in the webhook processing pipeline. They handle signature verification and metadata extraction specific to each webhook provider.

## Overview

Each webhook provider (Stripe, PayPal, Square, etc.) has its own signature verification scheme. Adapters encapsulate this provider-specific logic so your application can process webhooks securely.

**Latest Architecture:** CaptainHook now ships with **built-in adapters** for common providers:
- **Stripe** - `CaptainHook::Adapters::Stripe`
- **Square** - `CaptainHook::Adapters::Square`  
- **PayPal** - `CaptainHook::Adapters::Paypal`
- **WebhookSite** - `CaptainHook::Adapters::WebhookSite` (testing only)
- **Base** - `CaptainHook::Adapters::Base` (no-op for custom implementations)

For these providers, **you only need a YAML file** - no adapter code required! Just use `adapter_class: CaptainHook::Adapters::Stripe` in your configuration.

For custom providers not included in CaptainHook, you can still create custom adapters that live alongside your provider configuration.

## Adapter Responsibilities

An adapter must implement these methods:

1. **`verify_signature(payload:, headers:, provider_config:)`**: Verify the webhook came from the provider
2. **`extract_timestamp(headers)`**: Extract event timestamp for replay attack prevention
3. **`extract_event_id(payload)`**: Get the unique event identifier
4. **`extract_event_type(payload)`**: Determine what type of event this is

## Using Built-in Adapters

For supported providers (Stripe, Square, PayPal, WebhookSite), simply reference the built-in adapter in your YAML:

```yaml
# captain_hook/providers/stripe/stripe.yml
name: stripe
display_name: Stripe
adapter_class: CaptainHook::Adapters::Stripe  # Built-in adapter!
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
active: true
```

No adapter file needed!

## Creating Custom Adapters

For providers not included in CaptainHook, you can create custom adapters that live alongside your provider configuration:

### 1. Create Provider Directory

Create a folder for your provider in `captain_hook/providers/`:

```bash
mkdir -p captain_hook/providers/acme_payments
```

### 2. Create the Adapter Class

Create the adapter file (e.g., `acme_payments.rb`) that uses the `CaptainHook::AdapterHelpers` module:

```ruby
# captain_hook/providers/acme_payments/acme_payments.rb
class AcmePaymentsAdapter
  include CaptainHook::AdapterHelpers

  # Define provider-specific header names
  SIGNATURE_HEADER = "X-Acme-Signature"
  TIMESTAMP_HEADER = "X-Acme-Timestamp"

  # Implement signature verification
  def verify_signature(payload:, headers:, provider_config:)
    signature = extract_header(headers, SIGNATURE_HEADER)
    timestamp = extract_header(headers, TIMESTAMP_HEADER)
    
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
    extract_header(headers, TIMESTAMP_HEADER)&.to_i
  end

  # Extract event ID from payload
  def extract_event_id(payload)
    payload["transaction_id"] || payload["id"]
  end

  # Extract event type from payload
  def extract_event_type(payload)
    payload["event_type"] || payload["type"]
  end
end
```

### 3. Create Provider Configuration

Create the YAML configuration file:

```yaml
# captain_hook/providers/acme_payments/acme_payments.yml
name: acme_payments
display_name: AcmePayments
description: AcmePayments webhook provider
adapter_file: acme_payments.rb
signing_secret: ENV[ACME_PAYMENTS_SECRET]
timestamp_tolerance_seconds: 300
active: true
```

### 4. Scan for Providers

Run "Discover New" or "Full Sync" in the admin UI, and your adapter will be automatically discovered and loaded!

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

## Available Helper Methods

The `CaptainHook::AdapterHelpers` module provides these helper methods for all adapters:

### Security Helpers

#### `secure_compare(a, b)`
Constant-time string comparison to prevent timing attacks:

```ruby
secure_compare(signature, expected_signature)
```

#### `skip_verification?(secret)`
Check if signature verification should be skipped:

```ruby
if skip_verification?(provider_config.signing_secret)
  log_verification("provider", "Status" => "Skipping verification")
  return true
end
```

### HMAC Generation

#### `generate_hmac(secret, data)`
Generate hex-encoded HMAC-SHA256 signature:

```ruby
expected = generate_hmac(provider_config.signing_secret, "#{timestamp}.#{payload}")
```

#### `generate_hmac_base64(secret, data)`
Generate Base64-encoded HMAC-SHA256 signature:

```ruby
expected = generate_hmac_base64(provider_config.signing_secret, payload)
```

### Header Extraction

#### `extract_header(headers, *keys)`
Extract header case-insensitively:

```ruby
signature = extract_header(headers, "X-Signature", "X-Hub-Signature")
```

#### `parse_kv_header(header_value)`
Parse key-value header format (e.g., Stripe's `t=123,v1=abc`):

```ruby
parsed = parse_kv_header(headers["Stripe-Signature"])
timestamp = parsed["t"]
signature = parsed["v1"]
```

### Timestamp Validation

#### `timestamp_within_tolerance?(timestamp, tolerance)`
Check if timestamp is within acceptable range:

```ruby
return false unless timestamp_within_tolerance?(timestamp.to_i, 300)
```

#### `parse_timestamp(time_string)`
Parse various timestamp formats:

```ruby
timestamp = parse_timestamp(headers["X-Timestamp"])
```

### Logging

#### `log_verification(provider, details)`
Log signature verification steps:

```ruby
log_verification("stripe", 
  "Signature" => "present",
  "Timestamp" => timestamp,
  "Result" => "✓ Passed"
)
```

### URL Building

#### `build_webhook_url(path, provider_token: nil)`
Build complete webhook URL:

```ruby
url = build_webhook_url("/captain_hook/stripe", provider_token: "abc123")
```

## Common Signature Verification Patterns

### HMAC-SHA256 with Timestamp (Stripe-style)

```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Signature")
  timestamp = extract_header(headers, "X-Timestamp")
  
  return false if signature.blank? || timestamp.blank?
  
  # Validate timestamp
  if provider_config.timestamp_validation_enabled?
    tolerance = provider_config.timestamp_tolerance_seconds || 300
    return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
  end
  
  # Verify signature
  signed_payload = "#{timestamp}.#{payload}"
  expected = generate_hmac(provider_config.signing_secret, signed_payload)
  secure_compare(signature, expected)
end
```

### Simple Token Header

```ruby
def verify_signature(payload:, headers:, provider_config:)
  token = extract_header(headers, "X-Webhook-Token")
  
  if skip_verification?(provider_config.signing_secret)
    return true
  end
  
  secure_compare(token, provider_config.signing_secret)
end
```

### Base64 HMAC (Square-style)

```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature = extract_header(headers, "X-Square-Signature")
  
  return false if signature.blank?
  
  expected = generate_hmac_base64(provider_config.signing_secret, payload)
  secure_compare(signature, expected)
end
```

### Complex Header Parsing (Stripe-style)

```ruby
def verify_signature(payload:, headers:, provider_config:)
  signature_header = extract_header(headers, "Stripe-Signature")
  return false if signature_header.blank?

  # Parse: t=timestamp,v1=signature
  parsed = parse_kv_header(signature_header)
  timestamp = parsed["t"]
  signature = parsed["v1"]
  
  return false if timestamp.blank? || signature.blank?
  
  signed_payload = "#{timestamp}.#{payload}"
  expected = generate_hmac(provider_config.signing_secret, signed_payload)
  secure_compare(signature, expected)
end
```

## Testing Your Adapter

### Unit Test Example

```ruby
# test/adapters/acme_payments_adapter_test.rb
require 'test_helper'

class AcmePaymentsAdapterTest < ActiveSupport::TestCase
  def setup
    @config = OpenStruct.new(
      signing_secret: "test-secret",
      timestamp_tolerance_seconds: 300,
      timestamp_validation_enabled?: true
    )
    @adapter = AcmePaymentsAdapter.new
  end

  test "verifies valid signature" do
    payload = '{"id":"evt_123","event_type":"payment.completed"}'
    timestamp = Time.current.to_i.to_s
    
    # Generate expected signature
    expected_sig = OpenSSL::HMAC.hexdigest('SHA256', @config.signing_secret, "#{timestamp}.#{payload}")
    
    headers = {
      "X-Acme-Signature" => expected_sig,
      "X-Acme-Timestamp" => timestamp
    }
    
    assert @adapter.verify_signature(payload: payload, headers: headers, provider_config: @config)
  end

  test "rejects invalid signature" do
    payload = '{"id":"evt_123"}'
    headers = {
      "X-Acme-Signature" => "invalid",
      "X-Acme-Timestamp" => Time.current.to_i.to_s
    }
    
    refute @adapter.verify_signature(payload: payload, headers: headers, provider_config: @config)
  end
end
```

### Integration Testing

Use the admin sandbox to test with real payloads:

1. Go to `/captain_hook/admin/sandbox`
2. Select your provider
3. Paste a real webhook payload
4. Add required headers
5. Click "Test Webhook" (dry-run mode)

## Example Provider Adapters

### Stripe
- **File**: `captain_hook/providers/stripe/stripe.rb`
- **Signature**: HMAC-SHA256 with timestamp validation
- **Headers**: `Stripe-Signature` (format: `t=timestamp,v1=signature`)
- **Documentation**: https://stripe.com/docs/webhooks/signatures

### Square
- **File**: `captain_hook/providers/square/square.rb`
- **Signature**: Base64-encoded HMAC-SHA256 of notification URL + payload
- **Headers**: `X-Square-Hmacsha256-Signature` or `X-Square-Signature`
- **Documentation**: https://developer.squareup.com/docs/webhooks

### PayPal
- **File**: `captain_hook/providers/paypal/paypal.rb`
- **Signature**: Complex certificate-based verification (simplified for testing)
- **Headers**: Multiple headers including `Paypal-Transmission-Sig`, `Paypal-Transmission-Id`
- **Documentation**: https://developer.paypal.com/api/rest/webhooks/

### WebhookSite (Testing Only)
- **File**: `captain_hook/providers/webhook_site/webhook_site.rb`
- **Signature**: No-op verification (always returns true)
- **Use**: For development and testing only - **DO NOT USE IN PRODUCTION**
- **Documentation**: https://webhook.site

## Using AdapterHelpers in Your Host App

The `CaptainHook::AdapterHelpers` module is available for use in your host application or other gems. Simply include it in any class:

```ruby
# app/services/custom_webhook_verifier.rb
class CustomWebhookVerifier
  include CaptainHook::AdapterHelpers
  
  def verify_custom_webhook(payload, headers, secret)
    signature = extract_header(headers, "X-Custom-Signature")
    expected = generate_hmac(secret, payload)
    secure_compare(signature, expected)
  end
end
```

This gives you access to all the security-hardened helper methods for your custom webhook handling needs.

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

## Troubleshooting

### Signature verification fails

1. Check signing secret is correctly configured
2. Verify you're using the raw request body (not parsed JSON)
3. Check header name casing (use `extract_header()`)
4. Enable debug logging with `log_verification()`
5. Compare expected vs received signatures character-by-character

### Timestamp validation fails

1. Check server time is synchronized (NTP)
2. Verify timestamp format matches provider's spec
3. Adjust `timestamp_tolerance_seconds` if needed
4. Check timezone handling

### Provider not found

1. Ensure YAML file exists in `captain_hook/providers/<provider_name>/`
2. Ensure .rb file exists in the same directory
3. Run "Discover New" or "Full Sync" in admin UI
4. Check `adapter_file` in YAML references the correct .rb file

## Contributing

Want to contribute an adapter for a popular provider? Great!

### Steps to Contribute

1. **Create provider folder** in `captain_hook/providers/<provider>/`
2. **Create adapter** file `<provider>.rb` using `CaptainHook::AdapterHelpers`
3. **Create configuration** file `<provider>.yml` with provider details
4. **Create example** in `captain_hook/providers/<provider>.yml.example`
5. **Write tests** to demonstrate signature verification
6. **Update documentation** with your adapter details
7. **Submit pull request** with clear description
