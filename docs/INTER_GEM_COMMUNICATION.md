# Inter-Gem Communication

CaptainHook supports **inter-gem communication**, allowing other gems to automatically register webhook providers and handlers without requiring manual configuration in the host application.

## Overview

The inter-gem communication system enables:

1. **Auto-Discovery**: Gems can ship with webhook configurations that CaptainHook automatically discovers on boot
2. **Zero Configuration**: Install a gem → providers and handlers are automatically registered
3. **Decoupling**: Gems don't depend on each other, only on CaptainHook
4. **Flexibility**: Support for both YAML-based and code-based registration

## Registration Methods

### Method 1: YAML Configuration (Recommended)

The simplest way to integrate with CaptainHook is through YAML configuration files.

#### Provider Registration

Create `config/captain_hook_providers.yml` in your gem:

```yaml
providers:
  - name: stripe
    display_name: Stripe
    adapter_class: MyGem::StripeAdapter
    description: Stripe payment webhooks
    default_config:
      timestamp_tolerance_seconds: 300
      max_payload_size_bytes: 1048576
      rate_limit_requests: 100
      rate_limit_period: 60
  
  - name: github
    display_name: GitHub
    adapter_class: MyGem::GitHubAdapter
    description: GitHub webhook integration
```

#### Handler Registration

Create `config/captain_hook_handlers.yml` in your gem:

```yaml
handlers:
  - provider: stripe
    event_type: invoice.paid
    handler_class: MyGem::StripeInvoiceHandler
    priority: 100
    async: true
    max_attempts: 5
  
  - provider: stripe
    event_type: subscription.*
    handler_class: MyGem::StripeSubscriptionHandler
    priority: 100
    async: true
```

### Method 2: Programmatic Registration

For more complex scenarios, register providers and handlers programmatically in your gem's engine initializer:

```ruby
# lib/my_gem/engine.rb
module MyGem
  class Engine < ::Rails::Engine
    isolate_namespace MyGem
    
    initializer "my_gem.register_with_captain_hook", after: :load_config_initializers do
      Rails.application.config.after_initialize do
        # Register provider
        CaptainHook.register_provider(
          name: "stripe",
          display_name: "Stripe",
          adapter_class: "MyGem::StripeAdapter",
          gem_source: "my_gem",
          description: "Stripe payment webhooks",
          timestamp_tolerance_seconds: 300,
          max_payload_size_bytes: 1048576,
          rate_limit_requests: 100,
          rate_limit_period: 60
        )
        
        # Register handlers
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "invoice.paid",
          handler_class: "MyGem::StripeInvoiceHandler",
          gem_source: "my_gem",
          priority: 100,
          async: true
        )
      end
    end
  end
end
```

## Creating a Handler

Handlers must implement a `handle` method that accepts keyword arguments:

```ruby
# app/captain_hook_handlers/my_gem/stripe_invoice_handler.rb
module MyGem
  class StripeInvoiceHandler
    def handle(event:, payload:, metadata:)
      # event: CaptainHook::IncomingEvent record
      # payload: Parsed JSON payload (Hash)
      # metadata: Additional metadata (Hash with :timestamp, :headers, etc.)
      
      invoice_id = payload.dig("data", "object", "id")
      Invoice.find_by(stripe_id: invoice_id)&.mark_paid!
    end
  end
end
```

## Creating a Custom Adapter

If you need provider-specific signature verification:

```ruby
# lib/my_gem/stripe_adapter.rb
module MyGem
  class StripeAdapter < CaptainHook::Adapters::Base
    def verify_signature(payload:, headers:)
      # Implement Stripe's signature verification
      stripe_signature = extract_header(headers, "Stripe-Signature")
      expected = generate_signature(payload, signing_secret)
      Rack::Utils.secure_compare(stripe_signature, expected)
    end
    
    def extract_event_id(payload)
      payload["id"]
    end
    
    def extract_event_type(payload)
      payload["type"]
    end
    
    def extract_timestamp(headers)
      stripe_signature = extract_header(headers, "Stripe-Signature")
      # Parse timestamp from signature header
      timestamp_match = stripe_signature.match(/t=(\d+)/)
      timestamp_match ? timestamp_match[1].to_i : nil
    end
    
    private
    
    def generate_signature(payload, secret)
      timestamp = Time.now.to_i
      signed_payload = "#{timestamp}.#{payload}"
      OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    end
  end
end
```

## Example: Complete Gem Integration

Here's a complete example of a gem that integrates with CaptainHook:

### Gem Structure

```
my_stripe_gem/
├── lib/
│   ├── my_stripe_gem/
│   │   ├── engine.rb
│   │   ├── stripe_adapter.rb
│   │   └── version.rb
│   └── my_stripe_gem.rb
├── app/
│   └── captain_hook_handlers/
│       └── my_stripe_gem/
│           ├── invoice_handler.rb
│           └── subscription_handler.rb
├── config/
│   ├── captain_hook_providers.yml
│   └── captain_hook_handlers.yml
└── my_stripe_gem.gemspec
```

### config/captain_hook_providers.yml

```yaml
providers:
  - name: stripe
    display_name: Stripe
    adapter_class: MyStripeGem::StripeAdapter
    description: Stripe payment and subscription webhooks
    default_config:
      timestamp_tolerance_seconds: 300
      max_payload_size_bytes: 1048576
      rate_limit_requests: 100
      rate_limit_period: 60
```

### config/captain_hook_handlers.yml

```yaml
handlers:
  - provider: stripe
    event_type: invoice.paid
    handler_class: MyStripeGem::InvoiceHandler
    priority: 100
    async: true
  
  - provider: stripe
    event_type: customer.subscription.*
    handler_class: MyStripeGem::SubscriptionHandler
    priority: 100
    async: true
```

### app/captain_hook_handlers/my_stripe_gem/invoice_handler.rb

```ruby
module MyStripeGem
  class InvoiceHandler
    def handle(event:, payload:, metadata:)
      invoice_data = payload.dig("data", "object")
      invoice_id = invoice_data["id"]
      
      invoice = Invoice.find_or_create_by(stripe_id: invoice_id)
      invoice.update!(
        status: invoice_data["status"],
        amount: invoice_data["amount_paid"],
        paid_at: Time.at(invoice_data["status_transitions"]["paid_at"])
      )
      
      InvoiceMailer.payment_received(invoice).deliver_later if invoice.paid?
    end
  end
end
```

## Using the Gem

Once your gem is published, users can simply add it to their Gemfile:

```ruby
# Host application Gemfile
gem 'captain_hook'
gem 'my_stripe_gem'
```

After running `bundle install` and restarting the application:

1. The Stripe provider is automatically created in the database
2. Handlers for `invoice.paid` and `customer.subscription.*` are automatically registered
3. The webhook URL is available in the CaptainHook admin UI
4. All webhooks from Stripe are automatically processed

## Checking Gem-Provided Configurations

### In the Rails Console

```ruby
# List all gem-provided providers
CaptainHook::Provider.gem_provided

# Find providers from a specific gem
CaptainHook::Provider.from_gem("my_stripe_gem")

# Check if a provider is gem-provided
provider = CaptainHook::Provider.find_by(name: "stripe")
provider.gem_provided? # => true
provider.gem_source    # => "my_stripe_gem"
```

### In the Admin UI

The admin interface will show which gem each provider and handler comes from, making it easy to troubleshoot and understand your webhook configuration.

## Advanced: Multiple Gems for Same Provider

Multiple gems can register handlers for the same provider:

```ruby
# Gem A: stripe_billing_gem
handlers:
  - provider: stripe
    event_type: invoice.paid
    handler_class: StripeBillingGem::InvoiceHandler

# Gem B: stripe_analytics_gem  
handlers:
  - provider: stripe
    event_type: invoice.paid
    handler_class: StripeAnalyticsGem::AnalyticsHandler
```

Both handlers will execute when a `stripe.invoice.paid` webhook is received, in priority order.

## Benefits

1. **Zero Configuration**: No manual setup in the host application
2. **Plug and Play**: Install gem → webhooks work
3. **Maintainable**: Each gem manages its own webhook logic
4. **Discoverable**: Admin UI shows what's configured from which gem
5. **Decoupled**: Gems don't depend on each other
6. **Version Controlled**: Webhook configurations are versioned with the gem

## Limitations

- Gems must be loaded before CaptainHook's initializers run
- Database must be migrated and available at boot time
- Handler classes must be autoloadable via standard Rails conventions
