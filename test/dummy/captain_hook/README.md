# CaptainHook Directory Structure

This directory contains CaptainHook webhook configurations for automatic provider discovery.

## Directory Structure

```
captain_hook/
├── providers/       # Provider configuration YAML files
│   ├── stripe.yml
│   ├── square.yml
│   └── webhook_site.yml
├── handlers/        # Custom webhook event handlers
│   ├── stripe_payment_intent_handler.rb
│   └── square_bank_account_handler.rb
└── adapters/        # Custom signature verification adapters (optional)
    └── custom_adapter.rb
```

## Provider Configuration Files

Provider configuration files are YAML files that define webhook providers. CaptainHook scans these files when you click "Scan for Providers" in the admin interface.

### Example: `providers/stripe.yml`

```yaml
# Stripe webhook provider configuration
name: stripe
display_name: Stripe
description: Stripe payment and subscription webhooks
adapter_class: CaptainHook::Adapters::Stripe
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

### Configuration Fields

- **name** (required): Unique identifier for the provider (lowercase, underscores only)
- **display_name** (optional): Human-readable name shown in the UI
- **description** (optional): Description of the provider
- **adapter_class** (required): Full class name of the signature verification adapter
- **active** (optional, default: true): Whether the provider is active
- **signing_secret** (optional): Webhook signing secret. Use `ENV[VARIABLE_NAME]` to reference environment variables
- **timestamp_tolerance_seconds** (optional): Maximum allowed time difference for timestamp validation
- **rate_limit_requests** (optional): Maximum number of requests allowed per period
- **rate_limit_period** (optional): Time period in seconds for rate limiting
- **max_payload_size_bytes** (optional): Maximum allowed payload size in bytes

### Environment Variable References

Use the format `ENV[VARIABLE_NAME]` to reference environment variables for sensitive data like signing secrets:

```yaml
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

This will read the value from the `STRIPE_WEBHOOK_SECRET` environment variable at runtime.

## Handlers

Handlers are Ruby classes that process webhook events. Place handler files in the `handlers/` directory.

### Example Handler

```ruby
# handlers/stripe_payment_intent_handler.rb
class StripePaymentIntentHandler
  def handle(event:, payload:, metadata: {})
    # Process the webhook event
    Rails.logger.info "Processing payment intent: #{payload['id']}"
    
    # Your business logic here
    
    true # Return true for success
  end
end
```

### Registering Handlers

Register handlers in your `config/initializers/captain_hook.rb`:

```ruby
Rails.application.config.after_initialize do
  CaptainHook.register_handler(
    provider: "stripe",
    event_type: "payment_intent.succeeded",
    handler_class: "StripePaymentIntentHandler",
    priority: 100,
    async: true,
    max_attempts: 3
  )
end
```

## Adapters

Adapters handle signature verification for webhook providers. CaptainHook includes built-in adapters for:

- Stripe (`CaptainHook::Adapters::Stripe`)
- Square (`CaptainHook::Adapters::Square`)
- PayPal (`CaptainHook::Adapters::PayPal`)

### Custom Adapters

If you need a custom adapter, place it in the `adapters/` directory:

```ruby
# adapters/my_custom_adapter.rb
module CaptainHook
  module Adapters
    class MyCustomAdapter < Base
      def verify_signature(payload:, headers:)
        # Implement signature verification
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

Then reference it in your provider YAML:

```yaml
adapter_class: CaptainHook::Adapters::MyCustomAdapter
```

## Using in Gems

You can also place a `captain_hook/` directory in any gem, and CaptainHook will discover the providers during a scan:

```
my_gem/
├── lib/
└── captain_hook/
    ├── providers/
    │   └── my_service.yml
    ├── handlers/
    │   └── my_service_handler.rb
    └── adapters/
        └── my_service_adapter.rb
```

## Scanning for Providers

To discover and create providers from YAML files:

1. Navigate to the CaptainHook admin interface at `/captain_hook/admin/providers`
2. Click the "Scan for Providers" button
3. CaptainHook will:
   - Scan `Rails.root/captain_hook/providers/` for YAML files
   - Scan all loaded gems for `captain_hook/providers/` directories
   - Create or update provider records based on the YAML definitions
   - Display a summary of created/updated providers

## Best Practices

1. **Store secrets in environment variables**: Never commit signing secrets to version control
2. **Use descriptive names**: Provider names should be clear and unique
3. **Document your handlers**: Add comments explaining what each handler does
4. **Test your adapters**: Ensure signature verification works correctly
5. **Keep YAMLs in sync**: Update YAML files when provider settings change
6. **Version control**: Commit YAML files and handler/adapter code to your repository
