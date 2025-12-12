# Integrating CaptainHook from Other Gems

This guide explains how to use CaptainHook from other Rails engines or gems to handle webhooks.

## Table of Contents

- [Handler Registration](#handler-registration)
- [Outgoing Webhook Usage](#outgoing-webhook-usage)
- [Custom Adapters](#custom-adapters)
- [Configuration in Host App](#configuration-in-host-app)
- [Examples](#examples)

## Handler Registration

### Basic Handler Registration

Register handlers from your gem's initializer or engine:

```ruby
# lib/my_gem/engine.rb
module MyGem
  class Engine < ::Rails::Engine
    initializer "my_gem.register_webhook_handlers" do
      # Register after CaptainHook is configured
      ActiveSupport.on_load(:captain_hook_configured) do
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment_intent.succeeded",
          handler_class: "MyGem::Handlers::StripePaymentHandler",
          async: true,
          priority: 100,
          retry_delays: [30, 60, 300, 900, 3600],
          max_attempts: 5
        )
      end
    end
  end
end
```

### Handler Implementation

Create handler classes in your gem:

```ruby
# lib/my_gem/handlers/stripe_payment_handler.rb
module MyGem
  module Handlers
    class StripePaymentHandler
      def handle(event:, payload:, metadata:)
        # Access the incoming event record
        Rails.logger.info "Processing event #{event.id}"
        
        # Extract data from payload
        payment_intent = payload.dig("data", "object")
        amount = payment_intent["amount"]
        currency = payment_intent["currency"]
        
        # Your business logic
        MyGem::Payment.create!(
          external_id: payment_intent["id"],
          amount: amount,
          currency: currency,
          status: "succeeded"
        )
        
        # Log metadata
        Rails.logger.info "Received at: #{metadata[:received_at]}"
      end
    end
  end
end
```

### Priority-Based Ordering

Handlers are executed in order based on priority (lower = higher priority):

```ruby
# This handler runs first
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "MyGem::LoggingHandler",
  priority: 1  # Runs first
)

# This handler runs second
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "MyGem::PaymentHandler",
  priority: 100  # Runs after priority 1
)

# This handler runs third
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "MyGem::NotificationHandler",
  priority: 200  # Runs last
)
```

### Synchronous vs Asynchronous

```ruby
# Asynchronous (default, recommended)
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "MyGem::PaymentHandler",
  async: true  # Uses ActiveJob
)

# Synchronous (blocks the webhook response)
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "critical.event",
  handler_class: "MyGem::CriticalHandler",
  async: false  # Executes immediately
)
```

### Retry Configuration

Customize retry behavior per handler:

```ruby
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  handler_class: "MyGem::PaymentHandler",
  retry_delays: [30, 60, 300, 900, 3600],  # Delays in seconds
  max_attempts: 5
)
```

## Outgoing Webhook Usage

### Sending Webhooks from Your Gem

```ruby
# lib/my_gem/services/webhook_notifier.rb
module MyGem
  module Services
    class WebhookNotifier
      def notify_user_created(user)
        event = CaptainHook::OutgoingEvent.create!(
          provider: "production_endpoint",
          event_type: "user.created",
          target_url: webhook_url_for_user(user),
          payload: {
            id: user.id,
            email: user.email,
            name: user.name,
            created_at: user.created_at.iso8601
          },
          headers: {
            "X-Source" => "my-gem"
          },
          metadata: {
            gem: "my_gem",
            version: MyGem::VERSION
          }
        )
        
        # Enqueue for delivery
        CaptainHook::OutgoingJob.perform_later(event.id)
        
        event
      end
      
      private
      
      def webhook_url_for_user(user)
        # Dynamically determine webhook URL
        user.webhook_url || default_webhook_url
      end
      
      def default_webhook_url
        CaptainHook.configuration
          .outgoing_endpoint("production_endpoint")
          &.base_url
      end
    end
  end
end
```

### Triggering Webhooks from Model Callbacks

```ruby
# app/models/my_gem/user.rb
module MyGem
  class User < ApplicationRecord
    after_create :send_webhook_notification
    
    private
    
    def send_webhook_notification
      MyGem::Services::WebhookNotifier.new.notify_user_created(self)
    end
  end
end
```

### Batch Webhook Sending

```ruby
def notify_bulk_users(users)
  events = users.map do |user|
    CaptainHook::OutgoingEvent.create!(
      provider: "production_endpoint",
      event_type: "user.created",
      target_url: webhook_url,
      payload: user_payload(user)
    )
  end
  
  # Enqueue all at once
  events.each do |event|
    CaptainHook::OutgoingJob.perform_later(event.id)
  end
end
```

## Custom Adapters

### Creating a Custom Adapter

```ruby
# lib/my_gem/adapters/custom_webhook_adapter.rb
module MyGem
  module Adapters
    class CustomWebhookAdapter < CaptainHook::Adapters::Base
      SIGNATURE_HEADER = "X-Custom-Signature"
      TIMESTAMP_HEADER = "X-Custom-Timestamp"
      
      def verify_signature(payload:, headers:)
        signature = headers[SIGNATURE_HEADER] || headers[SIGNATURE_HEADER.downcase]
        timestamp = headers[TIMESTAMP_HEADER] || headers[TIMESTAMP_HEADER.downcase]
        
        return false if signature.blank? || timestamp.blank?
        
        # Check timestamp tolerance
        return false unless timestamp_valid?(timestamp.to_i)
        
        # Generate expected signature
        data = "#{timestamp}:#{payload}"
        expected = generate_hmac(provider_config.signing_secret, data)
        
        # Secure comparison
        secure_compare(signature, expected)
      end
      
      def extract_timestamp(headers)
        timestamp = headers[TIMESTAMP_HEADER] || headers[TIMESTAMP_HEADER.downcase]
        timestamp&.to_i
      end
      
      def extract_event_id(payload)
        payload["webhook_id"] || payload["id"]
      end
      
      def extract_event_type(payload)
        payload["event_type"] || payload["type"]
      end
      
      private
      
      def timestamp_valid?(timestamp)
        tolerance = provider_config.timestamp_tolerance_seconds || 300
        current_time = Time.current.to_i
        (current_time - timestamp).abs <= tolerance
      end
    end
  end
end
```

### Registering Custom Adapter

```ruby
CaptainHook.configure do |config|
  config.register_provider(
    "custom_provider",
    token: ENV["CUSTOM_WEBHOOK_TOKEN"],
    signing_secret: ENV["CUSTOM_WEBHOOK_SECRET"],
    adapter_class: "MyGem::Adapters::CustomWebhookAdapter",
    timestamp_tolerance_seconds: 300,
    max_payload_size_bytes: 2_097_152,  # 2MB
    rate_limit_requests: 200,
    rate_limit_period: 60
  )
end
```

## Configuration in Host App

### Requiring Configuration from Host

Document configuration requirements for your gem:

```ruby
# In your gem's README or installation guide:

# config/initializers/my_gem.rb
MyGem.configure do |config|
  config.webhook_enabled = true
end

# Configure CaptainHook for your gem
CaptainHook.configure do |config|
  # Register your gem's webhook provider
  config.register_provider(
    "my_gem_provider",
    token: ENV["MY_GEM_WEBHOOK_TOKEN"],
    signing_secret: ENV["MY_GEM_WEBHOOK_SECRET"],
    adapter_class: "MyGem::Adapters::WebhookAdapter"
  )
  
  # Register outgoing endpoint for your gem
  config.register_outgoing_endpoint(
    "my_gem_endpoint",
    base_url: ENV["MY_GEM_WEBHOOK_URL"],
    signing_secret: ENV["MY_GEM_OUTGOING_SECRET"]
  )
end
```

### Generator for Configuration

Create a generator to help users set up:

```ruby
# lib/generators/my_gem/install_generator.rb
module MyGem
  module Generators
    class InstallGenerator < Rails::Generators::Base
      def create_initializer
        create_file "config/initializers/my_gem_webhooks.rb", <<~RUBY
          # MyGem Webhook Configuration
          CaptainHook.configure do |config|
            config.register_provider(
              "my_gem",
              token: ENV["MY_GEM_WEBHOOK_TOKEN"],
              signing_secret: ENV["MY_GEM_WEBHOOK_SECRET"],
              adapter_class: "MyGem::Adapters::WebhookAdapter"
            )
          end
          
          # Register handlers
          CaptainHook.register_handler(
            provider: "my_gem",
            event_type: "resource.created",
            handler_class: "MyGem::Handlers::ResourceCreatedHandler"
          )
        RUBY
      end
    end
  end
end
```

## Examples

### Example 1: Payment Processing Gem

```ruby
# lib/payment_gem/engine.rb
module PaymentGem
  class Engine < ::Rails::Engine
    initializer "payment_gem.webhooks" do
      ActiveSupport.on_load(:captain_hook_configured) do
        # Register Stripe handlers
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment_intent.succeeded",
          handler_class: "PaymentGem::Handlers::PaymentSucceededHandler",
          priority: 50
        )
        
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "payment_intent.failed",
          handler_class: "PaymentGem::Handlers::PaymentFailedHandler",
          priority: 50
        )
        
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: "refund.created",
          handler_class: "PaymentGem::Handlers::RefundCreatedHandler",
          priority: 50
        )
      end
    end
  end
end

# lib/payment_gem/handlers/payment_succeeded_handler.rb
module PaymentGem
  module Handlers
    class PaymentSucceededHandler
      def handle(event:, payload:, metadata:)
        payment_intent = payload.dig("data", "object")
        
        PaymentGem::Payment.find_or_create_by!(
          provider: "stripe",
          external_id: payment_intent["id"]
        ) do |payment|
          payment.amount = payment_intent["amount"]
          payment.currency = payment_intent["currency"]
          payment.status = "succeeded"
          payment.customer_email = payment_intent.dig("charges", "data", 0, "billing_details", "email")
        end
        
        # Trigger outgoing webhook
        notify_payment_success(payment_intent)
      end
      
      private
      
      def notify_payment_success(payment_intent)
        CaptainHook::OutgoingEvent.create!(
          provider: "payment_notifications",
          event_type: "payment.succeeded",
          target_url: payment_webhook_url,
          payload: {
            payment_id: payment_intent["id"],
            amount: payment_intent["amount"],
            currency: payment_intent["currency"]
          }
        ).tap do |event|
          CaptainHook::OutgoingJob.perform_later(event.id)
        end
      end
    end
  end
end
```

### Example 2: User Management Gem

```ruby
# lib/user_gem/services/webhook_service.rb
module UserGem
  module Services
    class WebhookService
      def self.notify_user_event(user, event_type)
        new.notify_user_event(user, event_type)
      end
      
      def notify_user_event(user, event_type)
        CaptainHook::OutgoingEvent.create!(
          provider: "user_webhooks",
          event_type: "user.#{event_type}",
          target_url: webhook_url_for(event_type),
          payload: user_payload(user),
          metadata: {
            source: "user_gem",
            triggered_at: Time.current.iso8601
          }
        ).tap do |event|
          CaptainHook::OutgoingJob.perform_later(event.id)
        end
      end
      
      private
      
      def user_payload(user)
        {
          id: user.id,
          email: user.email,
          name: user.name,
          created_at: user.created_at.iso8601,
          updated_at: user.updated_at.iso8601
        }
      end
      
      def webhook_url_for(event_type)
        endpoint = CaptainHook.configuration.outgoing_endpoint("user_webhooks")
        endpoint&.build_url("/#{event_type}")
      end
    end
  end
end

# Usage in models
module UserGem
  class User < ApplicationRecord
    after_create -> { WebhookService.notify_user_event(self, "created") }
    after_update -> { WebhookService.notify_user_event(self, "updated") }
    after_destroy -> { WebhookService.notify_user_event(self, "deleted") }
  end
end
```

### Example 3: Multi-Provider Support

```ruby
# Support multiple webhook providers in your gem
module MyGem
  class Engine < ::Rails::Engine
    initializer "my_gem.webhooks" do
      ActiveSupport.on_load(:captain_hook_configured) do
        # Stripe handlers
        register_stripe_handlers
        
        # PayPal handlers
        register_paypal_handlers
        
        # Custom provider handlers
        register_custom_handlers
      end
    end
    
    def self.register_stripe_handlers
      %w[payment_intent.succeeded charge.refunded].each do |event_type|
        CaptainHook.register_handler(
          provider: "stripe",
          event_type: event_type,
          handler_class: "MyGem::Handlers::Stripe::#{event_type.classify}Handler",
          priority: 100
        )
      end
    end
    
    def self.register_paypal_handlers
      %w[payment.sale.completed payment.sale.refunded].each do |event_type|
        CaptainHook.register_handler(
          provider: "paypal",
          event_type: event_type,
          handler_class: "MyGem::Handlers::Paypal::#{event_type.classify}Handler",
          priority: 100
        )
      end
    end
    
    def self.register_custom_handlers
      # Your custom handlers
    end
  end
end
```

## Best Practices

1. **Namespace Your Handlers**: Use your gem's namespace to avoid conflicts
2. **Set Appropriate Priorities**: Lower values for critical handlers
3. **Handle Errors Gracefully**: Let CaptainHook manage retries
4. **Log Appropriately**: Use Rails.logger for debugging
5. **Test Handlers**: Write comprehensive tests for your handlers
6. **Document Configuration**: Provide clear setup instructions
7. **Use Async by Default**: Unless you have a specific need for synchronous processing
8. **Version Your APIs**: Include version info in outgoing webhook payloads

## Testing

### Testing Handlers

```ruby
# test/handlers/my_handler_test.rb
require "test_helper"

module MyGem
  class MyHandlerTest < ActiveSupport::TestCase
    test "processes webhook successfully" do
      event = captain_hook_incoming_events(:stripe_payment)
      payload = { "data" => { "object" => { "id" => "pi_123", "amount" => 1000 } } }
      
      handler = MyGem::Handlers::PaymentHandler.new
      handler.handle(event: event, payload: payload, metadata: {})
      
      assert_equal 1, MyGem::Payment.count
      assert_equal "pi_123", MyGem::Payment.last.external_id
    end
  end
end
```

### Testing Outgoing Webhooks

```ruby
test "sends outgoing webhook" do
  user = users(:one)
  
  assert_enqueued_with(job: CaptainHook::OutgoingJob) do
    MyGem::Services::WebhookService.notify_user_event(user, "created")
  end
  
  event = CaptainHook::OutgoingEvent.last
  assert_equal "user.created", event.event_type
  assert_equal user.id, event.payload["id"]
end
```

## Support

For issues or questions:
- Open an issue on GitHub
- Check existing documentation
- Review the test suite for examples
