# Inter-Gem Webhook Communication Guide

This guide explains how multiple Rails gems can communicate with each other using Captain Hook as a webhook orchestration layer. It covers patterns for sending and receiving webhooks between gems, enabling loose coupling and event-driven architectures.

---

## Table of Contents

- [Overview](#overview)
- [Communication Patterns](#communication-patterns)
- [Sending Webhooks from Your Gem](#sending-webhooks-from-your-gem)
- [Receiving Webhooks in Your Gem](#receiving-webhooks-in-your-gem)
- [Gem-to-Gem Communication Flow](#gem-to-gem-communication-flow)
- [Real-World Example: Country List Integration](#real-world-example-country-list-integration)
- [What Your Gem Needs to Support](#what-your-gem-needs-to-support)
- [Best Practices](#best-practices)
- [Testing](#testing)

---

## Overview

Captain Hook enables gems to communicate via webhooks without direct dependencies on each other. This creates a loosely coupled, event-driven architecture where:

1. **Gem A** triggers an event (e.g., "country updated")
2. **Captain Hook** delivers the webhook
3. **Gem B** receives and processes the webhook

### Benefits

- **Loose Coupling**: Gems don't need to know about each other's internals
- **Async Processing**: Events are processed asynchronously via ActiveJob
- **Reliability**: Built-in retry logic, circuit breakers, and failure handling
- **Auditability**: All webhook events are logged and tracked
- **Flexibility**: Host applications can enable/disable integrations via configuration

---

## Communication Patterns

### Pattern 1: Direct Gem-to-Gem (Internal)

One gem sends webhooks that another gem listens for within the same application.

```
[Country Gem] --webhook--> [Captain Hook] --delivers--> [Location Gem]
```

### Pattern 2: Gem-to-External-Service

Your gem sends webhooks to external services using Captain Hook.

```
[Your Gem] --webhook--> [Captain Hook] --delivers--> [External API]
```

### Pattern 3: External-to-Gem

External services send webhooks that your gem processes.

```
[External API] --webhook--> [Captain Hook] --triggers--> [Your Gem Handler]
```

### Pattern 4: Hub Pattern

Multiple gems communicate through Captain Hook as a central hub.

```
[Gem A] ----\                    /----> [Gem C]
             [Captain Hook Hub]
[Gem B] ----/                    \----> [Gem D]
```

---

## Sending Webhooks from Your Gem

When your gem wants to notify other gems or services about events, use Captain Hook's outgoing webhook functionality.

### Step 1: Create a Webhook Service

```ruby
# lib/country_gem/services/webhook_notifier.rb
module CountryGem
  module Services
    # Service for sending webhook notifications about country events
    # Uses Captain Hook to deliver webhooks with retry logic and tracking
    class WebhookNotifier
      # Notify when a country is created
      #
      # @param country [CountryGem::Country] The country that was created
      # @return [CaptainHook::OutgoingEvent] The webhook event record
      def self.notify_country_created(country)
        new.notify_country_created(country)
      end

      # Notify when a country is updated
      #
      # @param country [CountryGem::Country] The country that was updated
      # @param changes [Hash] Hash of attribute changes
      # @return [CaptainHook::OutgoingEvent] The webhook event record
      def self.notify_country_updated(country, changes = {})
        new.notify_country_updated(country, changes)
      end

      def notify_country_created(country)
        send_webhook(
          event_type: "country.created",
          payload: country_payload(country),
          metadata: event_metadata
        )
      end

      def notify_country_updated(country, changes = {})
        send_webhook(
          event_type: "country.updated",
          payload: country_payload(country).merge(changes: changes),
          metadata: event_metadata
        )
      end

      private

      # Send a webhook via Captain Hook
      #
      # @param event_type [String] The type of event (e.g., "country.created")
      # @param payload [Hash] The webhook payload data
      # @param metadata [Hash] Additional metadata for tracking
      # @return [CaptainHook::OutgoingEvent] The created event record
      def send_webhook(event_type:, payload:, metadata: {})
        # Create the outgoing event record
        event = CaptainHook::OutgoingEvent.create!(
          provider: webhook_provider_name,
          event_type: event_type,
          target_url: webhook_target_url,
          payload: payload,
          metadata: metadata,
          headers: custom_headers
        )

        # Enqueue for delivery via ActiveJob
        # This happens asynchronously with retry logic
        CaptainHook::OutgoingJob.perform_later(event.id)

        Rails.logger.info "[CountryGem] Webhook queued: #{event_type} (ID: #{event.id})"
        event
      end

      # Build the country payload for the webhook
      #
      # @param country [CountryGem::Country] The country object
      # @return [Hash] Serialized country data
      def country_payload(country)
        {
          id: country.id,
          code: country.code,
          name: country.name,
          continent: country.continent,
          population: country.population,
          capital: country.capital,
          currency: country.currency,
          updated_at: country.updated_at.iso8601,
          created_at: country.created_at.iso8601
        }
      end

      # Metadata for tracking and debugging
      #
      # @return [Hash] Metadata about the webhook source
      def event_metadata
        {
          source_gem: "country_gem",
          version: CountryGem::VERSION,
          environment: Rails.env,
          triggered_at: Time.current.iso8601
        }
      end

      # Custom headers for the webhook request
      #
      # @return [Hash] HTTP headers
      def custom_headers
        {
          "X-Source-Gem" => "CountryGem",
          "X-Gem-Version" => CountryGem::VERSION
        }
      end

      # Get the webhook provider name from configuration
      #
      # @return [String] The provider name
      def webhook_provider_name
        # This should match a provider registered in CaptainHook configuration
        "country_gem_webhooks"
      end

      # Get the webhook target URL
      # This could be:
      # - A configured endpoint in Captain Hook
      # - A dynamic URL from configuration
      # - An internal route for gem-to-gem communication
      #
      # @return [String] The webhook URL
      def webhook_target_url
        # For internal gem-to-gem communication, use a configured endpoint
        endpoint = CaptainHook.configuration
                              .outgoing_endpoint(webhook_provider_name)

        if endpoint
          endpoint.base_url
        else
          # Fallback to configuration or environment variable
          Rails.application.config.country_gem_webhook_url ||
            ENV["COUNTRY_GEM_WEBHOOK_URL"] ||
            "http://localhost:3000/captain_hook/country_gem_internal/#{webhook_token}"
        end
      end

      # Get or generate a webhook token for authentication
      #
      # @return [String] The webhook token
      def webhook_token
        Rails.application.credentials.dig(:country_gem, :webhook_token) ||
          ENV["COUNTRY_GEM_WEBHOOK_TOKEN"] ||
          "default_token_change_in_production"
      end
    end
  end
end
```

### Step 2: Trigger Webhooks from Models

```ruby
# app/models/country_gem/country.rb
module CountryGem
  class Country < ApplicationRecord
    # Use after_commit to ensure the database transaction is complete
    # before sending webhooks (avoids sending webhooks for rolled-back changes)
    after_commit :send_created_webhook, on: :create
    after_commit :send_updated_webhook, on: :update

    private

    # Send webhook notification after country is created
    def send_created_webhook
      CountryGem::Services::WebhookNotifier.notify_country_created(self)
    rescue StandardError => e
      # Log errors but don't fail the transaction
      # Captain Hook will handle retries
      Rails.logger.error "[CountryGem] Failed to queue webhook: #{e.message}"
    end

    # Send webhook notification after country is updated
    def send_updated_webhook
      return unless saved_changes.any?

      CountryGem::Services::WebhookNotifier.notify_country_updated(
        self,
        saved_changes
      )
    rescue StandardError => e
      Rails.logger.error "[CountryGem] Failed to queue webhook: #{e.message}"
    end
  end
end
```

### Step 3: Configure Captain Hook in Host Application

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  # Register the outgoing endpoint for Country Gem webhooks
  config.register_outgoing_endpoint(
    "country_gem_webhooks",
    base_url: ENV["COUNTRY_GEM_WEBHOOK_URL"] || "http://localhost:3000/webhooks/countries",
    signing_secret: ENV["COUNTRY_GEM_WEBHOOK_SECRET"],
    signing_header: "X-Country-Gem-Signature",
    timestamp_header: "X-Country-Gem-Timestamp",
    default_headers: {
      "Content-Type" => "application/json",
      "X-Source" => "country-gem"
    },
    retry_delays: [30, 60, 300, 900, 3600],
    max_attempts: 5,
    circuit_breaker_enabled: true,
    circuit_failure_threshold: 5,
    circuit_cooldown_seconds: 300
  )
end
```

---

## Receiving Webhooks in Your Gem

When your gem wants to respond to events from other gems or services, register handlers with Captain Hook.

### Step 1: Create a Handler

```ruby
# lib/location_gem/handlers/country_updated_handler.rb
module LocationGem
  module Handlers
    # Handler for processing country update webhooks
    # This handler is called by Captain Hook when a country.updated webhook is received
    class CountryUpdatedHandler
      # Process the webhook event
      #
      # @param event [CaptainHook::IncomingEvent] The incoming event record
      # @param payload [Hash] The webhook payload (parsed JSON)
      # @param metadata [Hash] Additional metadata from Captain Hook
      def handle(event:, payload:, metadata:)
        Rails.logger.info "[LocationGem] Processing country.updated webhook (Event ID: #{event.id})"

        # Extract country data from payload
        country_data = extract_country_data(payload)

        # Update or create location records based on country data
        update_locations(country_data)

        # Log successful processing
        Rails.logger.info "[LocationGem] Successfully processed country: #{country_data[:code]}"
      rescue StandardError => e
        # Log the error - Captain Hook will handle retries
        Rails.logger.error "[LocationGem] Error processing webhook: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        raise # Re-raise to trigger Captain Hook's retry logic
      end

      private

      # Extract and validate country data from webhook payload
      #
      # @param payload [Hash] The webhook payload
      # @return [Hash] Extracted country data
      # @raise [ArgumentError] if payload is missing required fields
      def extract_country_data(payload)
        required_fields = %w[id code name]
        missing_fields = required_fields - payload.keys

        if missing_fields.any?
          raise ArgumentError, "Missing required fields: #{missing_fields.join(', ')}"
        end

        {
          external_id: payload["id"],
          code: payload["code"],
          name: payload["name"],
          continent: payload["continent"],
          population: payload["population"],
          capital: payload["capital"],
          currency: payload["currency"],
          changes: payload["changes"] || {}
        }
      end

      # Update location records based on country data
      #
      # @param country_data [Hash] The country data
      def update_locations(country_data)
        # Find locations associated with this country
        locations = LocationGem::Location.where(country_code: country_data[:code])

        if locations.empty?
          Rails.logger.info "[LocationGem] No locations found for country: #{country_data[:code]}"
          return
        end

        # Update each location with new country information
        locations.find_each do |location|
          location.update!(
            country_name: country_data[:name],
            continent: country_data[:continent],
            country_metadata: {
              population: country_data[:population],
              capital: country_data[:capital],
              currency: country_data[:currency],
              last_synced_at: Time.current.iso8601
            }
          )

          Rails.logger.info "[LocationGem] Updated location #{location.id} for country #{country_data[:code]}"
        end

        Rails.logger.info "[LocationGem] Updated #{locations.count} locations for country #{country_data[:code]}"
      end
    end
  end
end
```

### Step 2: Register the Handler in Your Engine

```ruby
# lib/location_gem/engine.rb
module LocationGem
  class Engine < ::Rails::Engine
    isolate_namespace LocationGem

    # Register webhook handlers after Captain Hook is configured
    initializer "location_gem.register_webhook_handlers", after: :load_config_initializers do
      # Use ActiveSupport.on_load to ensure Captain Hook is configured first
      ActiveSupport.on_load(:captain_hook_configured) do
        Rails.logger.info "[LocationGem] Registering webhook handlers"

        # Register handler for country updates
        CaptainHook.register_handler(
          provider: "country_gem_internal",
          event_type: "country.updated",
          handler_class: "LocationGem::Handlers::CountryUpdatedHandler",
          async: true,        # Process asynchronously (default)
          priority: 100,      # Lower number = higher priority
          retry_delays: [30, 60, 300, 900, 3600],  # Retry delays in seconds
          max_attempts: 5
        )

        # Register handler for country creation
        CaptainHook.register_handler(
          provider: "country_gem_internal",
          event_type: "country.created",
          handler_class: "LocationGem::Handlers::CountryCreatedHandler",
          async: true,
          priority: 100
        )

        Rails.logger.info "[LocationGem] Webhook handlers registered"
      end
    end
  end
end
```

### Step 3: Configure Captain Hook to Accept Webhooks

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  # Register the provider for internal Country Gem webhooks
  config.register_provider(
    "country_gem_internal",
    token: ENV["COUNTRY_GEM_INTERNAL_TOKEN"] || "change_me_in_production",
    signing_secret: ENV["COUNTRY_GEM_WEBHOOK_SECRET"],
    adapter_class: "CaptainHook::Adapters::WebhookSite", # Or create custom adapter
    timestamp_tolerance_seconds: 300,
    max_payload_size_bytes: 1_048_576,  # 1MB
    rate_limit_requests: 100,
    rate_limit_period: 60
  )
end
```

---

## Gem-to-Gem Communication Flow

Here's how two gems communicate through Captain Hook:

### Complete Flow Example

```
┌─────────────────┐
│  Country Gem    │
│  (Sender)       │
└────────┬────────┘
         │
         │ 1. Country.update!(name: "New Name")
         │    Triggers after_commit callback
         │
         ▼
┌──────────────────────────────────────────┐
│  CountryGem::Services::WebhookNotifier   │
│  notify_country_updated(country)         │
└────────┬─────────────────────────────────┘
         │
         │ 2. Creates CaptainHook::OutgoingEvent
         │
         ▼
┌─────────────────────────────────────────┐
│  Captain Hook - Outgoing Processing     │
│  - Generates HMAC signature             │
│  - Sends HTTP POST to target URL        │
│  - Includes retry logic & circuit break │
└────────┬────────────────────────────────┘
         │
         │ 3. HTTP POST to webhook URL
         │
         ▼
┌─────────────────────────────────────────┐
│  Captain Hook - Incoming Endpoint       │
│  POST /captain_hook/:provider/:token    │
│  - Verifies signature                   │
│  - Creates IncomingEvent                │
│  - Finds registered handlers            │
└────────┬────────────────────────────────┘
         │
         │ 4. Enqueues handler job
         │
         ▼
┌──────────────────────────────────────────┐
│  CaptainHook::IncomingHandlerJob         │
│  - Instantiates handler class            │
│  - Calls handle() method                 │
└────────┬─────────────────────────────────┘
         │
         │ 5. Executes handler
         │
         ▼
┌───────────────────────────────────────────┐
│  LocationGem::Handlers::                  │
│  CountryUpdatedHandler                    │
│  - Extracts payload                       │
│  - Updates location records               │
└───────────────────────────────────────────┘
```

---

## Real-World Example: Country List Integration

This complete example shows how a Country List gem and a Location gem communicate.

### Scenario

- **Country Gem**: Maintains a list of countries and their metadata
- **Location Gem**: Manages locations and needs to sync with country data
- **Integration**: When a country is updated in the Country Gem, the Location Gem automatically updates its records

### Country Gem Implementation

#### 1. Country Model with Webhooks

```ruby
# country_gem/app/models/country_gem/country.rb
module CountryGem
  class Country < ApplicationRecord
    self.table_name = "country_gem_countries"

    # Validations
    validates :code, presence: true, uniqueness: true
    validates :name, presence: true

    # Trigger webhooks after database commit (not before)
    after_commit :notify_country_created, on: :create
    after_commit :notify_country_updated, on: :update
    after_commit :notify_country_deleted, on: :destroy

    private

    def notify_country_created
      CountryGem::Services::WebhookNotifier.notify_country_created(self)
    end

    def notify_country_updated
      return unless saved_changes.any?

      CountryGem::Services::WebhookNotifier.notify_country_updated(self, saved_changes)
    end

    def notify_country_deleted
      CountryGem::Services::WebhookNotifier.notify_country_deleted(self)
    end
  end
end
```

#### 2. Webhook Configuration

```ruby
# config/initializers/country_gem_webhooks.rb

# Configure Captain Hook for Country Gem
CaptainHook.configure do |config|
  config.register_outgoing_endpoint(
    "country_gem_webhooks",
    base_url: ENV["COUNTRY_WEBHOOK_URL"],
    signing_secret: ENV["COUNTRY_WEBHOOK_SECRET"],
    signing_header: "X-Country-Signature",
    timestamp_header: "X-Country-Timestamp"
  )
end
```

### Location Gem Implementation

#### 1. Location Model

```ruby
# location_gem/app/models/location_gem/location.rb
module LocationGem
  class Location < ApplicationRecord
    self.table_name = "location_gem_locations"

    validates :country_code, presence: true
    validates :name, presence: true

    # Store country metadata as JSON
    serialize :country_metadata, coder: JSON

    # Scope for finding locations by country
    scope :by_country, ->(code) { where(country_code: code) }
  end
end
```

#### 2. Handler Registration

```ruby
# location_gem/lib/location_gem/engine.rb
module LocationGem
  class Engine < ::Rails::Engine
    isolate_namespace LocationGem

    initializer "location_gem.webhooks" do
      ActiveSupport.on_load(:captain_hook_configured) do
        # Register provider for receiving Country Gem webhooks
        CaptainHook.configuration.register_provider(
          "country_gem_internal",
          token: ENV["COUNTRY_GEM_TOKEN"],
          signing_secret: ENV["COUNTRY_WEBHOOK_SECRET"],
          adapter_class: "CaptainHook::Adapters::WebhookSite"
        )

        # Register handlers for country events
        CaptainHook.register_handler(
          provider: "country_gem_internal",
          event_type: "country.created",
          handler_class: "LocationGem::Handlers::CountryCreatedHandler",
          priority: 50
        )

        CaptainHook.register_handler(
          provider: "country_gem_internal",
          event_type: "country.updated",
          handler_class: "LocationGem::Handlers::CountryUpdatedHandler",
          priority: 50
        )

        CaptainHook.register_handler(
          provider: "country_gem_internal",
          event_type: "country.deleted",
          handler_class: "LocationGem::Handlers::CountryDeletedHandler",
          priority: 50
        )
      end
    end
  end
end
```

#### 3. Complete Handler Implementation

```ruby
# location_gem/lib/location_gem/handlers/country_updated_handler.rb
module LocationGem
  module Handlers
    class CountryUpdatedHandler
      def handle(event:, payload:, metadata:)
        country_id = payload["id"]
        country_code = payload["code"]
        country_name = payload["name"]
        changes = payload["changes"] || {}

        Rails.logger.info "[LocationGem] Processing country update: #{country_code}"

        # Find all locations for this country
        locations = LocationGem::Location.by_country(country_code)

        if locations.empty?
          Rails.logger.info "[LocationGem] No locations found for country: #{country_code}"
          return
        end

        # Update locations in a transaction
        ActiveRecord::Base.transaction do
          locations.find_each do |location|
            # Update country name if it changed
            location.country_name = country_name if changes.key?("name")

            # Update country metadata
            location.country_metadata ||= {}
            location.country_metadata["population"] = payload["population"] if payload["population"]
            location.country_metadata["capital"] = payload["capital"] if payload["capital"]
            location.country_metadata["currency"] = payload["currency"] if payload["currency"]
            location.country_metadata["last_synced_at"] = Time.current.iso8601

            location.save!
          end
        end

        Rails.logger.info "[LocationGem] Updated #{locations.count} locations for #{country_code}"
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[LocationGem] Validation error: #{e.message}"
        raise
      end
    end
  end
end
```

### Host Application Configuration

```ruby
# config/initializers/inter_gem_webhooks.rb

# This configuration enables Country Gem and Location Gem to communicate

CaptainHook.configure do |config|
  # Outgoing: Country Gem sends webhooks to this URL
  config.register_outgoing_endpoint(
    "country_gem_webhooks",
    base_url: "#{ENV['APP_URL']}/captain_hook/country_gem_internal/#{ENV['COUNTRY_GEM_TOKEN']}",
    signing_secret: ENV["COUNTRY_WEBHOOK_SECRET"],
    signing_header: "X-Country-Signature",
    timestamp_header: "X-Country-Timestamp",
    retry_delays: [30, 60, 300],
    max_attempts: 3
  )

  # Incoming: Location Gem receives webhooks at this endpoint
  config.register_provider(
    "country_gem_internal",
    token: ENV["COUNTRY_GEM_TOKEN"],
    signing_secret: ENV["COUNTRY_WEBHOOK_SECRET"],
    adapter_class: "CaptainHook::Adapters::WebhookSite",
    timestamp_tolerance_seconds: 300
  )
end
```

---

## What Your Gem Needs to Support

For your gem to participate in Captain Hook webhook communication:

### For Sending Webhooks (Outgoing)

1. **Create a webhook notifier service** (see examples above)
2. **Integrate with model callbacks** or business logic
3. **Document required configuration** in your gem's README:
   - Required environment variables
   - Captain Hook endpoint registration
   - Example configuration snippet

### For Receiving Webhooks (Incoming)

1. **Create handler classes** that implement a `handle(event:, payload:, metadata:)` method
2. **Register handlers in your engine** using `CaptainHook.register_handler`
3. **Document webhook payload format** so other gems know what to send
4. **Document required configuration**:
   - Provider registration in Captain Hook
   - Required tokens and signing secrets
   - Example handler registration

### Documentation Checklist

Your gem's README should include:

```markdown
## Webhook Support

This gem integrates with [Captain Hook](https://github.com/bowerbird-app/captain-hook) 
for webhook-based communication.

### Outgoing Webhooks

This gem sends the following webhooks:

- `resource.created` - Fired when a resource is created
- `resource.updated` - Fired when a resource is updated
- `resource.deleted` - Fired when a resource is deleted

#### Payload Format

\`\`\`json
{
  "id": 123,
  "name": "Resource Name",
  "created_at": "2023-12-15T10:00:00Z",
  "updated_at": "2023-12-15T10:00:00Z"
}
\`\`\`

#### Configuration

\`\`\`ruby
CaptainHook.configure do |config|
  config.register_outgoing_endpoint(
    "your_gem_webhooks",
    base_url: ENV["YOUR_GEM_WEBHOOK_URL"],
    signing_secret: ENV["YOUR_GEM_WEBHOOK_SECRET"]
  )
end
\`\`\`

### Incoming Webhooks

This gem can respond to webhooks from other gems/services.

#### Supported Events

- `external_resource.updated` - Updates internal records when external resource changes

#### Configuration

\`\`\`ruby
CaptainHook.configure do |config|
  config.register_provider(
    "external_provider",
    token: ENV["EXTERNAL_PROVIDER_TOKEN"],
    signing_secret: ENV["EXTERNAL_PROVIDER_SECRET"],
    adapter_class: "CaptainHook::Adapters::WebhookSite"
  )
end
\`\`\`
```

---

## Best Practices

### 1. Use after_commit Callbacks

Always use `after_commit` (not `after_save` or `after_create`) to ensure webhooks are only sent after successful database commits:

```ruby
after_commit :send_webhook, on: :create
```

### 2. Handle Errors Gracefully

Don't let webhook failures break your main business logic:

```ruby
def send_webhook
  MyGem::WebhookNotifier.notify_event(self)
rescue StandardError => e
  Rails.logger.error "Webhook failed: #{e.message}"
  # Don't re-raise - let Captain Hook handle retries
end
```

### 3. Version Your Payloads

Include version information in your webhook payloads:

```ruby
def event_metadata
  {
    source_gem: "my_gem",
    version: MyGem::VERSION,
    schema_version: "1.0"
  }
end
```

### 4. Use Semantic Event Names

Follow a consistent naming pattern:

- `resource.created` ✅
- `resource.updated` ✅
- `resource.deleted` ✅
- `create_resource` ❌
- `update` ❌

### 5. Keep Payloads Small

Only include necessary data in webhook payloads. For large datasets, send an ID and let the receiver fetch details if needed:

```ruby
# Good: Compact payload
{ id: 123, code: "US", name: "United States" }

# Avoid: Overly large payload
{ id: 123, code: "US", name: "United States", all_cities: [...1000 cities...] }
```

### 6. Document Payload Schemas

Maintain clear documentation of your webhook payload structure:

```ruby
# Webhook Payload Schema
# 
# Event: country.updated
# {
#   "id": <integer>,           # Country ID
#   "code": <string>,          # ISO country code
#   "name": <string>,          # Country name
#   "continent": <string>,     # Continent name
#   "population": <integer>,   # Population count
#   "changes": {               # Changed attributes (if update)
#     "name": ["Old", "New"]
#   }
# }
```

### 7. Test Webhook Integration

Write tests for webhook sending and receiving:

```ruby
# test/services/webhook_notifier_test.rb
test "sends webhook when country is created" do
  country = countries(:one)

  assert_enqueued_with(job: CaptainHook::OutgoingJob) do
    CountryGem::Services::WebhookNotifier.notify_country_created(country)
  end

  event = CaptainHook::OutgoingEvent.last
  assert_equal "country.created", event.event_type
  assert_equal country.id, event.payload["id"]
end
```

### 8. Use Idempotency

Ensure your handlers are idempotent (can be safely retried):

```ruby
def handle(event:, payload:, metadata:)
  # Use find_or_create_by or upsert for idempotency
  Location.find_or_create_by!(external_id: payload["id"]) do |location|
    location.name = payload["name"]
  end
end
```

### 9. Log Appropriately

Log webhook activity for debugging and monitoring:

```ruby
Rails.logger.info "[MyGem] Webhook sent: #{event_type} (Event ID: #{event.id})"
Rails.logger.info "[MyGem] Processing webhook: #{event.event_type} (ID: #{event.id})"
```

### 10. Secure Your Webhooks

- Always use HTTPS in production
- Use strong signing secrets
- Store secrets in Rails credentials or environment variables
- Never commit secrets to version control

```ruby
# Good
signing_secret: Rails.application.credentials.dig(:captain_hook, :signing_secret)

# Good
signing_secret: ENV["CAPTAIN_HOOK_SIGNING_SECRET"]

# Bad
signing_secret: "my-secret-key"  # Never hardcode!
```

---

## Testing

### Testing Outgoing Webhooks

```ruby
# test/models/country_test.rb
require "test_helper"

class CountryTest < ActiveSupport::TestCase
  test "sends webhook when country is created" do
    assert_enqueued_jobs 1, only: CaptainHook::OutgoingJob do
      Country.create!(code: "US", name: "United States")
    end
  end

  test "sends webhook when country is updated" do
    country = countries(:usa)

    assert_enqueued_jobs 1, only: CaptainHook::OutgoingJob do
      country.update!(name: "United States of America")
    end
  end

  test "webhook includes correct payload" do
    country = countries(:usa)
    country.update!(name: "United States of America")

    event = CaptainHook::OutgoingEvent.last
    assert_equal "country.updated", event.event_type
    assert_equal "US", event.payload["code"]
    assert_equal "United States of America", event.payload["name"]
  end
end
```

### Testing Incoming Webhooks

```ruby
# test/handlers/country_updated_handler_test.rb
require "test_helper"

module LocationGem
  module Handlers
    class CountryUpdatedHandlerTest < ActiveSupport::TestCase
      setup do
        @handler = CountryUpdatedHandler.new
        @event = captain_hook_incoming_events(:country_updated)
        @payload = {
          "id" => 1,
          "code" => "US",
          "name" => "United States of America",
          "population" => 331_000_000,
          "changes" => { "name" => ["United States", "United States of America"] }
        }
      end

      test "updates locations with new country data" do
        location = location_gem_locations(:new_york)
        assert_equal "United States", location.country_name

        @handler.handle(event: @event, payload: @payload, metadata: {})

        location.reload
        assert_equal "United States of America", location.country_name
        assert_equal 331_000_000, location.country_metadata["population"]
      end

      test "raises error for missing required fields" do
        invalid_payload = { "code" => "US" } # Missing "id" and "name"

        assert_raises(ArgumentError) do
          @handler.handle(event: @event, payload: invalid_payload, metadata: {})
        end
      end

      test "handles multiple locations for same country" do
        _location1 = LocationGem::Location.create!(country_code: "US", name: "New York")
        _location2 = LocationGem::Location.create!(country_code: "US", name: "Los Angeles")

        assert_changes -> { LocationGem::Location.by_country("US").count }, from: 2, to: 2 do
          @handler.handle(event: @event, payload: @payload, metadata: {})
        end

        LocationGem::Location.by_country("US").each do |location|
          assert_equal "United States of America", location.country_name
        end
      end
    end
  end
end
```

### Integration Testing

```ruby
# test/integration/inter_gem_webhooks_test.rb
require "test_helper"

class InterGemWebhooksTest < ActionDispatch::IntegrationTest
  test "country update triggers location update via webhook" do
    # Create a country
    country = CountryGem::Country.create!(code: "CA", name: "Canada")

    # Create locations for this country
    location = LocationGem::Location.create!(
      country_code: "CA",
      name: "Toronto",
      country_name: "Canada"
    )

    # Update the country
    perform_enqueued_jobs do
      country.update!(name: "Canada (Updated)")
    end

    # Verify location was updated via webhook
    location.reload
    assert_equal "Canada (Updated)", location.country_name
  end
end
```

---

## Troubleshooting

### Common Issues

#### 1. Webhooks Not Being Sent

**Check:**
- Is the outgoing endpoint registered in Captain Hook configuration?
- Are jobs being enqueued? Check ActiveJob queue adapter
- Check logs for errors in webhook notifier

```ruby
# Verify endpoint is registered
endpoint = CaptainHook.configuration.outgoing_endpoint("your_endpoint_name")
puts endpoint.inspect
```

#### 2. Webhooks Not Being Received

**Check:**
- Is the provider registered in Captain Hook configuration?
- Is the handler registered for the event type?
- Check webhook URL and token are correct
- Verify signature validation is passing

```ruby
# Verify provider is registered
provider = CaptainHook.configuration.provider("your_provider_name")
puts provider.inspect

# Verify handlers are registered
handlers = CaptainHook.handler_registry.handlers_for(
  provider: "your_provider", 
  event_type: "your.event"
)
puts handlers.inspect
```

#### 3. Handler Not Being Called

**Check:**
- Is the handler class name correct (as string)?
- Is the handler class loaded and available?
- Check for errors in background jobs
- Verify event_type matches exactly

```ruby
# Test handler instantiation
handler_class = "YourGem::Handlers::YourHandler".constantize
handler = handler_class.new
handler.handle(event: mock_event, payload: {}, metadata: {})
```

---

## Summary

Captain Hook enables powerful inter-gem communication patterns through webhooks:

1. **Sending Webhooks**: Use `CaptainHook::OutgoingEvent` to send webhooks from your gem
2. **Receiving Webhooks**: Register handlers with `CaptainHook.register_handler` to process webhooks
3. **Configuration**: Both sender and receiver gems need Captain Hook configuration
4. **Best Practices**: Use after_commit, handle errors gracefully, version payloads, keep payloads small
5. **Testing**: Write comprehensive tests for both sending and receiving webhooks

This creates a loosely coupled, event-driven architecture where gems can communicate without tight dependencies.
