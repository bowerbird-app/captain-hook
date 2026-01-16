# Handler Management

This document describes the handler management feature in CaptainHook, which allows you to discover, configure, and manage webhook event handlers through the admin UI.

## Overview

Handlers are Ruby classes that process incoming webhook events. Previously, they existed only in the in-memory handler registry. Now, handlers can be:

1. **Discovered** from your application code
2. **Synced** to the database
3. **Configured** through the admin UI
4. **Soft-deleted** to prevent re-addition during scans

## Database Schema

The `captain_hook_handlers` table stores handler configurations:

```ruby
create_table :captain_hook_handlers do |t|
  t.string :provider, null: false
  t.string :event_type, null: false
  t.string :handler_class, null: false
  t.boolean :async, null: false, default: true
  t.integer :max_attempts, null: false, default: 5
  t.integer :priority, null: false, default: 100
  t.jsonb :retry_delays, null: false, default: [30, 60, 300, 900, 3600]
  t.datetime :deleted_at
  t.timestamps
end
```

## Features

### Handler Discovery

The `HandlerDiscovery` service scans the in-memory `HandlerRegistry` to find all registered handlers:

```ruby
discovery = CaptainHook::Services::HandlerDiscovery.new
handlers = discovery.call # Returns all handlers

# Or for a specific provider:
handlers = CaptainHook::Services::HandlerDiscovery.for_provider("stripe")
```

### Handler Sync

The `HandlerSync` service syncs discovered handlers to the database:

```ruby
sync = CaptainHook::Services::HandlerSync.new(handler_definitions)
results = sync.call

# Results include:
# - created: newly created handlers
# - updated: existing handlers with updated config
# - skipped: soft-deleted handlers (not re-added)
# - errors: handlers that failed validation
```

**Important:** Soft-deleted handlers are automatically skipped during sync to respect user deletions.

### Provider Scan Integration

When you scan for providers (via "Discover New" or "Full Sync" buttons), the system automatically:
1. Discovers all registered handlers from the HandlerRegistry
2. Syncs them to the database (respects the update_existing flag)
3. Reports the results (created/updated/skipped counts)

### Provider-Specific Handler Scan

Each provider detail page has a "Scan Handlers" button that:
1. Discovers handlers only for that specific provider
2. Syncs them to the database (always updates existing)
3. Shows results with created/updated/skipped counts

## Admin UI

### Handlers Index (`/captain_hook/admin/providers/:id/handlers`)

Shows two sections:

1. **Configured Handlers** - Handlers synced to the database with:
   - Edit button to configure handler settings
   - Delete button to soft-delete handlers

2. **Registered Handlers (In-Memory)** - Handlers from the registry not yet synced

### Handler Edit Page

Allows editing:
- **Event Type** - The webhook event this handler processes
- **Execution Mode** - Async (background job) or Sync (immediate)
- **Priority** - Lower numbers execute first
- **Max Attempts** - Number of retry attempts on failure
- **Retry Delays** - Comma-separated delay times in seconds between retries

**Read-only fields:**
- Provider (cannot be changed)
- Handler Class (cannot be changed)

### Soft Delete

Deleting a handler:
1. Sets `deleted_at` timestamp (soft delete)
2. Handler remains in database but marked as deleted
3. Handler will be skipped during future scans
4. Can be restored via database if needed

## Usage Example

### 1. Register handlers in your application

```ruby
# config/initializers/captain_hook.rb
CaptainHook.register_handler(
  provider: "stripe",
  event_type: "payment.succeeded",
  handler_class: "ProcessPaymentHandler",
  priority: 100,
  async: true,
  max_attempts: 5,
  retry_delays: [30, 60, 300, 900, 3600]
)
```

### 2. Scan for handlers

Either:
- Click "Discover New" or "Full Sync" on the providers index (scans all providers and handlers)
- Click "Scan Handlers" on a provider detail page (scans handlers for one provider only)

### 3. Configure handlers

1. Navigate to provider's handlers page
2. Click "Edit" on a handler
3. Modify settings (async/sync, retries, priority, etc.)
4. Save changes

### 4. Manage handlers

- **Update settings** through the edit form
- **Soft-delete** handlers you don't want (prevents re-addition)
- **View status** of all handlers for a provider

## API

### HandlerDiscovery Service

```ruby
# Discover all handlers
discovery = CaptainHook::Services::HandlerDiscovery.new
all_handlers = discovery.call

# Discover handlers for specific provider
stripe_handlers = CaptainHook::Services::HandlerDiscovery.for_provider("stripe")
```

### HandlerSync Service

```ruby
# Sync handler definitions to database
sync = CaptainHook::Services::HandlerSync.new(handler_definitions)
results = sync.call

# Check results
puts "Created: #{results[:created].size}"
puts "Updated: #{results[:updated].size}"
puts "Skipped: #{results[:skipped].size}"
puts "Errors: #{results[:errors].size}"
```

### Handler Model

```ruby
# Find handlers
handler = CaptainHook::Handler.find(id)

# Scopes
active_handlers = CaptainHook::Handler.active
deleted_handlers = CaptainHook::Handler.deleted
stripe_handlers = CaptainHook::Handler.for_provider("stripe")
payment_handlers = CaptainHook::Handler.for_event_type("payment.succeeded")

# Soft delete
handler.soft_delete!
handler.deleted? # => true

# Restore
handler.restore!
handler.deleted? # => false

# Get provider record
provider = handler.provider_record
```

## Testing

Tests are provided for:

- `Handler` model (`test/models/handler_test.rb`)
- `HandlerDiscovery` service (`test/services/handler_discovery_test.rb`)
- `HandlerSync` service (`test/services/handler_sync_test.rb`)

Run tests:

```bash
bundle exec rake test
```

## Migration

To add this feature to an existing installation:

```bash
# Install migrations
rails captain_hook:install:migrations

# Run migrations
rails db:migrate

# Scan to sync existing handlers
# Via UI: Click "Discover New" or "Full Sync" button
# Or via console:
discovery = CaptainHook::Services::HandlerDiscovery.new
sync = CaptainHook::Services::HandlerSync.new(discovery.call, update_existing: true)
sync.call
```

## Notes

- Handler class names cannot be changed after creation
- Provider names cannot be changed after creation
- Soft-deleted handlers remain in database but are marked as deleted
- Scanning respects soft-deleted handlers and won't re-add them
- Retry delays must be positive integers (in seconds)
- Max attempts must be at least 1
