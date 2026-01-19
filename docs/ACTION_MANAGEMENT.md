# Action Management

This document describes the action management feature in CaptainHook, which allows you to discover, configure, and manage webhook event actions through the admin UI.

## Overview

Actions are Ruby classes that process incoming webhook events. Previously, they existed only in the in-memory action registry. Now, actions can be:

1. **Discovered** from your application code
2. **Synced** to the database
3. **Configured** through the admin UI
4. **Soft-deleted** to prevent re-addition during scans

## Database Schema

The `captain_hook_actions` table stores action configurations:

```ruby
create_table :captain_hook_actions do |t|
  t.string :provider, null: false
  t.string :event_type, null: false
  t.string :action_class, null: false
  t.boolean :async, null: false, default: true
  t.integer :max_attempts, null: false, default: 5
  t.integer :priority, null: false, default: 100
  t.jsonb :retry_delays, null: false, default: [30, 60, 300, 900, 3600]
  t.datetime :deleted_at
  t.timestamps
end
```

## Features

### Action Discovery

The `ActionDiscovery` service scans the in-memory `ActionRegistry` to find all registered actions:

```ruby
discovery = CaptainHook::Services::ActionDiscovery.new
actions = discovery.call # Returns all actions

# Or for a specific provider:
actions = CaptainHook::Services::ActionDiscovery.for_provider("stripe")
```

### Action Sync

The `ActionSync` service syncs discovered actions to the database:

```ruby
sync = CaptainHook::Services::ActionSync.new(action_definitions)
results = sync.call

# Results include:
# - created: newly created actions
# - updated: existing actions with updated config
# - skipped: soft-deleted actions (not re-added)
# - errors: actions that failed validation
```

**Important:** Soft-deleted actions are automatically skipped during sync to respect user deletions.

### Provider Scan Integration

When you scan for providers (via "Discover New" or "Full Sync" buttons), the system automatically:
1. Discovers all registered actions from the ActionRegistry
2. Syncs them to the database (respects the update_existing flag)
3. Reports the results (created/updated/skipped counts)

### Provider-Specific Action Scan

Each provider detail page has a "Scan Actions" button that:
1. Discovers actions only for that specific provider
2. Syncs them to the database (always updates existing)
3. Shows results with created/updated/skipped counts

## Admin UI

### Actions Index (`/captain_hook/admin/providers/:id/actions`)

Shows two sections:

1. **Configured Actions** - Actions synced to the database with:
   - Edit button to configure action settings
   - Delete button to soft-delete actions

2. **Registered Actions (In-Memory)** - Actions from the registry not yet synced

### Action Edit Page

Allows editing:
- **Event Type** - The webhook event this action processes
- **Execution Mode** - Async (background job) or Sync (immediate)
- **Priority** - Lower numbers execute first
- **Max Attempts** - Number of retry attempts on failure
- **Retry Delays** - Comma-separated delay times in seconds between retries

**Read-only fields:**
- Provider (cannot be changed)
- Action Class (cannot be changed)

### Soft Delete

Deleting a action:
1. Sets `deleted_at` timestamp (soft delete)
2. Action remains in database but marked as deleted
3. Action will be skipped during future scans
4. Can be restored via database if needed

## Usage Example

### 1. Register actions in your application

```ruby
# config/initializers/captain_hook.rb
CaptainHook.register_action(
  provider: "stripe",
  event_type: "payment.succeeded",
  action_class: "ProcessPaymentHandler",
  priority: 100,
  async: true,
  max_attempts: 5,
  retry_delays: [30, 60, 300, 900, 3600]
)
```

### 2. Scan for actions

Either:
- Click "Discover New" or "Full Sync" on the providers index (scans all providers and actions)
- Click "Scan Actions" on a provider detail page (scans actions for one provider only)

### 3. Configure actions

1. Navigate to provider's actions page
2. Click "Edit" on a action
3. Modify settings (async/sync, retries, priority, etc.)
4. Save changes

### 4. Manage actions

- **Update settings** through the edit form
- **Soft-delete** actions you don't want (prevents re-addition)
- **View status** of all actions for a provider

## API

### ActionDiscovery Service

```ruby
# Discover all actions
discovery = CaptainHook::Services::ActionDiscovery.new
all_actions = discovery.call

# Discover actions for specific provider
stripe_actions = CaptainHook::Services::ActionDiscovery.for_provider("stripe")
```

### ActionSync Service

```ruby
# Sync action definitions to database
sync = CaptainHook::Services::ActionSync.new(action_definitions)
results = sync.call

# Check results
puts "Created: #{results[:created].size}"
puts "Updated: #{results[:updated].size}"
puts "Skipped: #{results[:skipped].size}"
puts "Errors: #{results[:errors].size}"
```

### Action Model

```ruby
# Find actions
action = CaptainHook::Action.find(id)

# Scopes
active_actions = CaptainHook::Action.active
deleted_actions = CaptainHook::Action.deleted
stripe_actions = CaptainHook::Action.for_provider("stripe")
payment_actions = CaptainHook::Action.for_event_type("payment.succeeded")

# Soft delete
action.soft_delete!
action.deleted? # => true

# Restore
action.restore!
action.deleted? # => false

# Get provider record
provider = action.provider_record
```

## Testing

Tests are provided for:

- `Action` model (`test/models/action_test.rb`)
- `ActionDiscovery` service (`test/services/action_discovery_test.rb`)
- `ActionSync` service (`test/services/action_sync_test.rb`)

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

# Scan to sync existing actions
# Via UI: Click "Discover New" or "Full Sync" button
# Or via console:
discovery = CaptainHook::Services::ActionDiscovery.new
sync = CaptainHook::Services::ActionSync.new(discovery.call, update_existing: true)
sync.call
```

## Notes

- Action class names cannot be changed after creation
- Provider names cannot be changed after creation
- Soft-deleted actions remain in database but are marked as deleted
- Scanning respects soft-deleted actions and won't re-add them
- Retry delays must be positive integers (in seconds)
- Max attempts must be at least 1
