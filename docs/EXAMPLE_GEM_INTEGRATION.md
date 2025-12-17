# Example Gem Integration

This directory contains a complete example of how to create a gem that integrates with CaptainHook using the inter-gem communication system.

## Directory Structure

```
example_stripe_integration/
├── lib/
│   ├── example_stripe_integration/
│   │   ├── engine.rb
│   │   ├── stripe_adapter.rb
│   │   └── version.rb
│   └── example_stripe_integration.rb
├── app/
│   └── captain_hook_handlers/
│       └── example_stripe_integration/
│           ├── invoice_handler.rb
│           └── subscription_handler.rb
├── config/
│   ├── captain_hook_providers.yml
│   └── captain_hook_handlers.yml
├── example_stripe_integration.gemspec
├── Gemfile
└── README.md
```

## File Contents

### example_stripe_integration.gemspec

```ruby
Gem::Specification.new do |spec|
  spec.name        = "example_stripe_integration"
  spec.version     = "0.1.0"
  spec.authors     = ["Your Name"]
  spec.email       = ["your.email@example.com"]
  spec.summary     = "Stripe webhook integration for CaptainHook"
  spec.description = "Automatically handles Stripe webhooks using CaptainHook"
  spec.license     = "MIT"

  spec.files = Dir["{app,config,lib}/**/*", "MIT-LICENSE", "README.md"]

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "captain_hook", ">= 0.1.0"
end
```

### lib/example_stripe_integration.rb

```ruby
require "example_stripe_integration/version"
require "example_stripe_integration/engine"
require "example_stripe_integration/stripe_adapter"

module ExampleStripeIntegration
  # Your gem's configuration and setup
end
```

### lib/example_stripe_integration/engine.rb

```ruby
module ExampleStripeIntegration
  class Engine < ::Rails::Engine
    isolate_namespace ExampleStripeIntegration

    # Optional: Programmatic registration (alternative to YAML)
    # initializer "example_stripe_integration.register_with_captain_hook", 
    #            after: :load_config_initializers do
    #   Rails.application.config.after_initialize do
    #     CaptainHook.register_provider(
    #       name: "stripe",
    #       display_name: "Stripe",
    #       adapter_class: "ExampleStripeIntegration::StripeAdapter",
    #       gem_source: "example_stripe_integration"
    #     )
    #   end
    # end
  end
end
```

### lib/example_stripe_integration/stripe_adapter.rb

```ruby
module ExampleStripeIntegration
  class StripeAdapter < CaptainHook::Adapters::Base
    def verify_signature(payload:, headers:)
      stripe_signature = extract_header(headers, "Stripe-Signature")
      return false unless stripe_signature

      timestamp, signature = parse_stripe_signature(stripe_signature)
      expected = generate_signature(payload, timestamp)
      
      Rack::Utils.secure_compare(signature, expected)
    end

    def extract_event_id(payload)
      payload["id"]
    end

    def extract_event_type(payload)
      payload["type"]
    end

    def extract_timestamp(headers)
      stripe_signature = extract_header(headers, "Stripe-Signature")
      return nil unless stripe_signature
      
      timestamp, _ = parse_stripe_signature(stripe_signature)
      timestamp&.to_i
    end

    private

    def parse_stripe_signature(signature_header)
      parts = signature_header.split(",").each_with_object({}) do |part, hash|
        key, value = part.split("=", 2)
        hash[key] = value
      end
      
      [parts["t"], parts["v1"]]
    end

    def generate_signature(payload, timestamp)
      signed_payload = "#{timestamp}.#{payload}"
      OpenSSL::HMAC.hexdigest("SHA256", signing_secret, signed_payload)
    end
  end
end
```

### config/captain_hook_providers.yml

```yaml
providers:
  - name: stripe
    display_name: Stripe
    adapter_class: ExampleStripeIntegration::StripeAdapter
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
    handler_class: ExampleStripeIntegration::InvoiceHandler
    priority: 100
    async: true
    max_attempts: 5
    retry_delays: [30, 60, 300, 900, 3600]
  
  - provider: stripe
    event_type: customer.subscription.created
    handler_class: ExampleStripeIntegration::SubscriptionHandler
    priority: 100
    async: true
  
  - provider: stripe
    event_type: customer.subscription.updated
    handler_class: ExampleStripeIntegration::SubscriptionHandler
    priority: 100
    async: true
  
  - provider: stripe
    event_type: customer.subscription.deleted
    handler_class: ExampleStripeIntegration::SubscriptionHandler
    priority: 100
    async: true
```

### app/captain_hook_handlers/example_stripe_integration/invoice_handler.rb

```ruby
module ExampleStripeIntegration
  class InvoiceHandler
    def handle(event:, payload:, metadata:)
      invoice_data = payload.dig("data", "object")
      return unless invoice_data

      invoice_id = invoice_data["id"]
      customer_id = invoice_data["customer"]
      amount = invoice_data["amount_paid"]
      status = invoice_data["status"]

      Rails.logger.info "Processing Stripe invoice: #{invoice_id} (#{status})"

      # Your business logic here
      # For example:
      # invoice = Invoice.find_or_create_by(stripe_id: invoice_id)
      # invoice.update!(
      #   customer_id: customer_id,
      #   amount: amount,
      #   status: status,
      #   paid_at: status == "paid" ? Time.current : nil
      # )
      #
      # if invoice.paid?
      #   InvoiceMailer.payment_received(invoice).deliver_later
      # end
    rescue StandardError => e
      Rails.logger.error "Failed to process invoice #{invoice_id}: #{e.message}"
      raise # Re-raise to trigger retry
    end
  end
end
```

### app/captain_hook_handlers/example_stripe_integration/subscription_handler.rb

```ruby
module ExampleStripeIntegration
  class SubscriptionHandler
    def handle(event:, payload:, metadata:)
      subscription_data = payload.dig("data", "object")
      return unless subscription_data

      subscription_id = subscription_data["id"]
      customer_id = subscription_data["customer"]
      status = subscription_data["status"]
      event_type = payload["type"]

      Rails.logger.info "Processing Stripe subscription event: #{event_type} for #{subscription_id}"

      case event_type
      when "customer.subscription.created"
        handle_subscription_created(subscription_id, customer_id, subscription_data)
      when "customer.subscription.updated"
        handle_subscription_updated(subscription_id, status, subscription_data)
      when "customer.subscription.deleted"
        handle_subscription_deleted(subscription_id)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to process subscription #{subscription_id}: #{e.message}"
      raise
    end

    private

    def handle_subscription_created(subscription_id, customer_id, data)
      # Your business logic here
      Rails.logger.info "Subscription created: #{subscription_id}"
    end

    def handle_subscription_updated(subscription_id, status, data)
      # Your business logic here
      Rails.logger.info "Subscription updated: #{subscription_id} to #{status}"
    end

    def handle_subscription_deleted(subscription_id)
      # Your business logic here
      Rails.logger.info "Subscription deleted: #{subscription_id}"
    end
  end
end
```

## Usage

### In Host Application

Add to your Gemfile:

```ruby
gem 'captain_hook'
gem 'example_stripe_integration'
```

Then run:

```bash
bundle install
rails captain_hook:install:migrations
rails db:migrate
rails server
```

### Accessing the Webhook URL

Visit the CaptainHook admin interface at `/captain_hook/admin/providers`.

The Stripe provider will be automatically created with a unique webhook URL. Copy this URL and paste it into your Stripe webhook settings at https://dashboard.stripe.com/webhooks.

### Testing

You can test the integration using:

1. **Stripe CLI**: `stripe trigger invoice.payment_succeeded`
2. **CaptainHook Sandbox**: Navigate to `/captain_hook/admin/sandbox`
3. **Stripe Dashboard**: Send test events from the webhook configuration page

## Customization

### Adding More Event Types

Edit `config/captain_hook_handlers.yml` to add more handlers:

```yaml
handlers:
  - provider: stripe
    event_type: payment_intent.succeeded
    handler_class: ExampleStripeIntegration::PaymentIntentHandler
    priority: 100
    async: true
```

Then create the handler class:

```ruby
# app/captain_hook_handlers/example_stripe_integration/payment_intent_handler.rb
module ExampleStripeIntegration
  class PaymentIntentHandler
    def handle(event:, payload:, metadata:)
      # Your logic here
    end
  end
end
```

### Wildcard Event Handlers

You can use wildcards to handle multiple related events with a single handler:

```yaml
handlers:
  - provider: stripe
    event_type: charge.*
    handler_class: ExampleStripeIntegration::ChargeHandler
    priority: 100
    async: true
```

This will handle `charge.succeeded`, `charge.failed`, `charge.refunded`, etc.

## Best Practices

1. **Error Handling**: Always re-raise errors you want to retry. CaptainHook will automatically retry failed handlers.

2. **Idempotency**: Make your handlers idempotent - they should be safe to run multiple times with the same payload.

3. **Logging**: Log important events and errors for debugging.

4. **Testing**: Write tests for your handlers using fixtures from Stripe's webhook documentation.

5. **Configuration**: Store sensitive data like signing secrets in environment variables, not in the database.

## Resources

- [CaptainHook Documentation](https://github.com/bowerbird-app/captain-hook)
- [Stripe Webhook Documentation](https://stripe.com/docs/webhooks)
- [CaptainHook Inter-Gem Communication](../INTER_GEM_COMMUNICATION.md)
