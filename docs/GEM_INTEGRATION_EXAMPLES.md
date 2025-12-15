# Captain Hook Gem Integration Examples

This document provides practical examples of using Captain Hook's `GemIntegration` module for easier webhook integration.

## Table of Contents

- [Basic Usage](#basic-usage)
- [Sending Webhooks](#sending-webhooks)
- [Receiving Webhooks](#receiving-webhooks)
- [Complete Gem Example](#complete-gem-example)
- [Using Helpers in Models](#using-helpers-in-models)
- [Using Helpers in Services](#using-helpers-in-services)

---

## Basic Usage

The `CaptainHook::GemIntegration` module provides helper methods that simplify webhook integration.

### Include in Your Service Class

```ruby
# lib/my_gem/services/webhook_service.rb
module MyGem
  module Services
    class WebhookService
      include CaptainHook::GemIntegration

      def notify_resource_created(resource)
        send_webhook(
          provider: "my_gem_webhooks",
          event_type: "resource.created",
          payload: build_webhook_payload(resource)
        )
      end
    end
  end
end
```

### Use as Class Methods

```ruby
# Direct usage without including the module
CaptainHook::GemIntegration.send_webhook(
  provider: "my_gem_webhooks",
  event_type: "resource.created",
  payload: { id: 123, name: "Example" }
)
```

---

## Sending Webhooks

### Simple Webhook

```ruby
class CountryGem::Services::WebhookNotifier
  include CaptainHook::GemIntegration

  def notify_country_updated(country)
    send_webhook(
      provider: "country_gem_webhooks",
      event_type: "country.updated",
      payload: {
        id: country.id,
        code: country.code,
        name: country.name,
        population: country.population
      }
    )
  end
end
```

### Webhook with Custom Metadata

```ruby
class CountryGem::Services::WebhookNotifier
  include CaptainHook::GemIntegration

  def notify_country_updated(country, user:)
    send_webhook(
      provider: "country_gem_webhooks",
      event_type: "country.updated",
      payload: build_webhook_payload(country),
      metadata: {
        updated_by: user.email,
        ip_address: user.current_sign_in_ip,
        source: "admin_panel"
      }
    )
  end
end
```

### Webhook with Custom Headers

```ruby
def notify_with_custom_headers(resource)
  send_webhook(
    provider: "my_gem_webhooks",
    event_type: "resource.created",
    payload: build_webhook_payload(resource),
    headers: {
      "X-Source-System" => "MyGem",
      "X-Priority" => "high",
      "X-Correlation-ID" => SecureRandom.uuid
    }
  )
end
```

### Synchronous Webhook (Wait for Completion)

```ruby
def notify_critical_event(resource)
  # Process synchronously instead of via background job
  send_webhook(
    provider: "my_gem_webhooks",
    event_type: "critical.event",
    payload: build_webhook_payload(resource),
    async: false  # Process immediately
  )
end
```

### Check Configuration Before Sending

```ruby
def notify_if_configured(resource)
  if webhook_configured?("my_gem_webhooks")
    send_webhook(
      provider: "my_gem_webhooks",
      event_type: "resource.created",
      payload: build_webhook_payload(resource)
    )
  else
    Rails.logger.warn "Webhooks not configured for my_gem_webhooks"
  end
end
```

---

## Receiving Webhooks

### Register Handler Using Helper

```ruby
# lib/my_gem/engine.rb
module MyGem
  class Engine < ::Rails::Engine
    include CaptainHook::GemIntegration

    isolate_namespace MyGem

    initializer "my_gem.register_webhooks" do
      ActiveSupport.on_load(:captain_hook_configured) do
        # Register handler using the helper method
        register_webhook_handler(
          provider: "external_service",
          event_type: "resource.updated",
          handler_class: "MyGem::Handlers::ResourceUpdatedHandler",
          priority: 100,
          async: true,
          retry_delays: [30, 60, 300],
          max_attempts: 3
        )

        register_webhook_handler(
          provider: "external_service",
          event_type: "resource.deleted",
          handler_class: "MyGem::Handlers::ResourceDeletedHandler",
          priority: 100
        )
      end
    end
  end
end
```

### Handler Implementation

```ruby
# lib/my_gem/handlers/resource_updated_handler.rb
module MyGem
  module Handlers
    class ResourceUpdatedHandler
      def handle(event:, payload:, metadata:)
        Rails.logger.info "[MyGem] Processing resource.updated webhook"

        resource_id = payload["id"]
        resource = MyGem::Resource.find_by(external_id: resource_id)

        if resource
          resource.update!(
            name: payload["name"],
            status: payload["status"],
            last_synced_at: Time.current
          )
          Rails.logger.info "[MyGem] Updated resource #{resource_id}"
        else
          Rails.logger.warn "[MyGem] Resource #{resource_id} not found"
        end
      rescue StandardError => e
        Rails.logger.error "[MyGem] Error: #{e.message}"
        raise  # Re-raise to trigger retry
      end
    end
  end
end
```

---

## Complete Gem Example

Here's a complete example showing how to structure a gem with Captain Hook integration.

### Directory Structure

```
my_gem/
├── lib/
│   ├── my_gem/
│   │   ├── engine.rb
│   │   ├── services/
│   │   │   └── webhook_notifier.rb
│   │   └── handlers/
│   │       ├── external_resource_created_handler.rb
│   │       └── external_resource_updated_handler.rb
│   └── my_gem.rb
└── app/
    └── models/
        └── my_gem/
            └── resource.rb
```

### Engine Configuration

```ruby
# lib/my_gem/engine.rb
module MyGem
  class Engine < ::Rails::Engine
    include CaptainHook::GemIntegration

    isolate_namespace MyGem

    # Register incoming webhook handlers
    initializer "my_gem.register_webhook_handlers", after: :load_config_initializers do
      ActiveSupport.on_load(:captain_hook_configured) do
        Rails.logger.info "[MyGem] Registering webhook handlers"

        # Register handlers for external webhooks
        register_webhook_handler(
          provider: "external_api",
          event_type: "resource.created",
          handler_class: "MyGem::Handlers::ExternalResourceCreatedHandler",
          priority: 100
        )

        register_webhook_handler(
          provider: "external_api",
          event_type: "resource.updated",
          handler_class: "MyGem::Handlers::ExternalResourceUpdatedHandler",
          priority: 100
        )

        Rails.logger.info "[MyGem] Webhook handlers registered successfully"
      end
    end
  end
end
```

### Webhook Notifier Service

```ruby
# lib/my_gem/services/webhook_notifier.rb
module MyGem
  module Services
    class WebhookNotifier
      include CaptainHook::GemIntegration

      # Send notification when resource is created
      def self.notify_resource_created(resource)
        new.notify_resource_created(resource)
      end

      # Send notification when resource is updated
      def self.notify_resource_updated(resource, changes = {})
        new.notify_resource_updated(resource, changes)
      end

      # Send notification when resource is deleted
      def self.notify_resource_deleted(resource)
        new.notify_resource_deleted(resource)
      end

      def notify_resource_created(resource)
        return unless webhook_configured?("my_gem_webhooks")

        send_webhook(
          provider: "my_gem_webhooks",
          event_type: "resource.created",
          payload: build_resource_payload(resource),
          metadata: build_metadata(action: "created")
        )
      end

      def notify_resource_updated(resource, changes = {})
        return unless webhook_configured?("my_gem_webhooks")

        send_webhook(
          provider: "my_gem_webhooks",
          event_type: "resource.updated",
          payload: build_resource_payload(resource).merge(changes: changes),
          metadata: build_metadata(action: "updated")
        )
      end

      def notify_resource_deleted(resource)
        return unless webhook_configured?("my_gem_webhooks")

        send_webhook(
          provider: "my_gem_webhooks",
          event_type: "resource.deleted",
          payload: {
            id: resource.id,
            deleted_at: Time.current.iso8601
          },
          metadata: build_metadata(action: "deleted")
        )
      end

      private

      def build_resource_payload(resource)
        {
          id: resource.id,
          name: resource.name,
          status: resource.status,
          external_id: resource.external_id,
          created_at: resource.created_at.iso8601,
          updated_at: resource.updated_at.iso8601
        }
      end

      def build_metadata(action:)
        {
          source_gem: "my_gem",
          version: MyGem::VERSION,
          action: action,
          environment: Rails.env,
          triggered_at: Time.current.iso8601
        }
      end
    end
  end
end
```

### Model with Webhooks

```ruby
# app/models/my_gem/resource.rb
module MyGem
  class Resource < ApplicationRecord
    self.table_name = "my_gem_resources"

    # Validations
    validates :name, presence: true

    # Webhook callbacks
    after_commit :send_created_webhook, on: :create
    after_commit :send_updated_webhook, on: :update
    after_commit :send_deleted_webhook, on: :destroy

    private

    def send_created_webhook
      MyGem::Services::WebhookNotifier.notify_resource_created(self)
    rescue StandardError => e
      Rails.logger.error "[MyGem] Failed to send created webhook: #{e.message}"
    end

    def send_updated_webhook
      return unless saved_changes.any?

      MyGem::Services::WebhookNotifier.notify_resource_updated(self, saved_changes)
    rescue StandardError => e
      Rails.logger.error "[MyGem] Failed to send updated webhook: #{e.message}"
    end

    def send_deleted_webhook
      MyGem::Services::WebhookNotifier.notify_resource_deleted(self)
    rescue StandardError => e
      Rails.logger.error "[MyGem] Failed to send deleted webhook: #{e.message}"
    end
  end
end
```

### Incoming Webhook Handler

```ruby
# lib/my_gem/handlers/external_resource_updated_handler.rb
module MyGem
  module Handlers
    class ExternalResourceUpdatedHandler
      def handle(event:, payload:, metadata:)
        Rails.logger.info "[MyGem] Processing external resource update"

        external_id = payload["id"]
        resource = MyGem::Resource.find_by(external_id: external_id)

        if resource
          update_resource(resource, payload)
        else
          create_resource_from_webhook(payload)
        end
      rescue StandardError => e
        Rails.logger.error "[MyGem] Handler error: #{e.message}"
        raise
      end

      private

      def update_resource(resource, payload)
        resource.update!(
          name: payload["name"],
          status: payload["status"],
          last_synced_at: Time.current
        )
        Rails.logger.info "[MyGem] Updated resource #{resource.id}"
      end

      def create_resource_from_webhook(payload)
        resource = MyGem::Resource.create!(
          external_id: payload["id"],
          name: payload["name"],
          status: payload["status"],
          last_synced_at: Time.current
        )
        Rails.logger.info "[MyGem] Created resource #{resource.id} from webhook"
      end
    end
  end
end
```

### Host Application Configuration

```ruby
# config/initializers/my_gem_webhooks.rb

# Configure outgoing webhooks (MyGem sending to external services)
CaptainHook.configure do |config|
  config.register_outgoing_endpoint(
    "my_gem_webhooks",
    base_url: ENV["MY_GEM_WEBHOOK_URL"],
    signing_secret: ENV["MY_GEM_WEBHOOK_SECRET"],
    signing_header: "X-MyGem-Signature",
    timestamp_header: "X-MyGem-Timestamp",
    retry_delays: [30, 60, 300],
    max_attempts: 3
  )
end

# Configure incoming webhooks (External services sending to MyGem)
CaptainHook.configure do |config|
  config.register_provider(
    "external_api",
    token: ENV["EXTERNAL_API_TOKEN"],
    signing_secret: ENV["EXTERNAL_API_SECRET"],
    adapter_class: "CaptainHook::Adapters::WebhookSite",
    timestamp_tolerance_seconds: 300,
    rate_limit_requests: 100,
    rate_limit_period: 60
  )
end
```

---

## Using Helpers in Models

```ruby
# app/models/country_gem/country.rb
module CountryGem
  class Country < ApplicationRecord
    include CaptainHook::GemIntegration

    after_commit :broadcast_update, on: :update

    private

    def broadcast_update
      return unless webhook_configured?("country_gem_webhooks")

      send_webhook(
        provider: "country_gem_webhooks",
        event_type: "country.updated",
        payload: build_webhook_payload(self),
        metadata: { changes: saved_changes }
      )
    rescue StandardError => e
      Rails.logger.error "Webhook failed: #{e.message}"
    end
  end
end
```

---

## Using Helpers in Services

```ruby
# app/services/country_gem/sync_service.rb
module CountryGem
  module Services
    class SyncService
      include CaptainHook::GemIntegration

      def sync_from_api
        countries = fetch_countries_from_api

        countries.each do |country_data|
          country = sync_country(country_data)
          notify_sync_complete(country) if country
        end
      end

      private

      def sync_country(country_data)
        Country.find_or_create_by!(code: country_data["code"]) do |country|
          country.name = country_data["name"]
          country.population = country_data["population"]
        end
      end

      def notify_sync_complete(country)
        send_webhook(
          provider: "country_gem_webhooks",
          event_type: "country.synced",
          payload: build_webhook_payload(country),
          metadata: {
            sync_source: "external_api",
            synced_at: Time.current.iso8601
          }
        )
      end

      def fetch_countries_from_api
        # API fetching logic here
        []
      end
    end
  end
end
```

---

## Summary

The `CaptainHook::GemIntegration` module provides:

1. **`send_webhook`** - Simplified webhook sending with error handling
2. **`register_webhook_handler`** - Easy handler registration
3. **`webhook_configured?`** - Check if webhooks are configured
4. **`webhook_url`** - Get configured webhook URL
5. **`build_webhook_payload`** - Build standardized payloads from ActiveRecord models
6. **`build_webhook_metadata`** - Build metadata with defaults

These helpers make it easy to integrate Captain Hook into your gem without writing boilerplate code.
