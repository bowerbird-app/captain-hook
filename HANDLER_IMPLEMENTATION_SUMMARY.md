# Handler Management Feature - Implementation Summary

## High-Level Overview

This feature adds the ability to discover, persist, edit, and manage webhook handlers through the admin UI. Previously, handlers existed only in the application's in-memory registry. Now they can be:

1. **Discovered** - Scanned from the in-memory HandlerRegistry
2. **Synced to Database** - Persisted for configuration and management
3. **Configured** - Edited through the admin UI (async/sync, retries, priority)
4. **Soft Deleted** - Marked as deleted to prevent re-addition during scans

## Key Features

### 1. Handler Discovery & Sync
- "Scan for Providers" button now also discovers and syncs all handlers
- Each provider has a "Scan Handlers" button for provider-specific scanning
- Handlers are discovered from the HandlerRegistry and synced to database
- Soft-deleted handlers are automatically skipped during sync

### 2. Handler Configuration
- Edit page allows configuring:
  - Event type
  - Async/sync execution mode
  - Maximum retry attempts
  - Retry delays (comma-separated seconds)
  - Priority (lower executes first)
- Provider and handler class are read-only (cannot be changed)

### 3. Soft Delete
- Delete button soft-deletes handlers (sets `deleted_at`)
- Deleted handlers remain in database but marked as deleted
- Future scans skip soft-deleted handlers
- Prevents unwanted re-addition of deleted handlers

## Technical Implementation

### Database Schema

**New Table: `captain_hook_handlers`**
```ruby
create_table :captain_hook_handlers, id: :uuid do |t|
  t.string :provider, null: false
  t.string :event_type, null: false
  t.string :handler_class, null: false
  t.boolean :async, null: false, default: true
  t.integer :max_attempts, null: false, default: 5
  t.integer :priority, null: false, default: 100
  t.jsonb :retry_delays, null: false, default: [30, 60, 300, 900, 3600]
  t.datetime :deleted_at
  t.timestamps
  
  # Unique constraint on (provider, event_type, handler_class)
  # Indexes on provider and deleted_at
end
```

### New Models

**`CaptainHook::Handler`** (`app/models/captain_hook/handler.rb`)
- Validations for all required fields
- Custom validation for retry_delays (must be array of positive integers)
- Soft delete methods: `soft_delete!`, `restore!`, `deleted?`
- Scopes: `active`, `deleted`, `for_provider`, `for_event_type`, `by_priority`
- Helper method `registry_key` to get "provider:event_type" format
- Helper method `provider_record` to get associated Provider

### New Services

**`CaptainHook::Services::HandlerDiscovery`** (`lib/captain_hook/services/handler_discovery.rb`)
- Scans the in-memory HandlerRegistry
- Returns array of handler definitions
- Class method `for_provider(name)` for provider-specific discovery

**`CaptainHook::Services::HandlerSync`** (`lib/captain_hook/services/handler_sync.rb`)
- Syncs handler definitions to database
- Creates new handlers or updates existing ones
- Skips soft-deleted handlers (respects user deletions)
- Returns results hash: `{ created: [], updated: [], skipped: [], errors: [] }`
- Validates handler definitions before syncing

### Controllers

**Updated `ProvidersController`** (`app/controllers/captain_hook/admin/providers_controller.rb`)
- `scan` action now also discovers and syncs handlers
- New `scan_handlers` action for provider-specific handler scanning
- Flash messages report results for both providers and handlers

**Updated `HandlersController`** (`app/controllers/captain_hook/admin/handlers_controller.rb`)
- `index` shows both DB handlers and registry handlers
- New `show`, `edit`, `update`, `destroy` actions
- `update` handles retry_delays parsing (JSON or comma-separated)
- `destroy` performs soft delete instead of hard delete
- Helper method `handler_registry_for_provider` for displaying registry handlers

### Routes

**Updated Routes** (`config/routes.rb`)
```ruby
resources :providers do
  collection do
    post :scan
  end
  member do
    post :scan_handlers  # New route
  end
  resources :handlers, only: %i[index show edit update destroy]  # Expanded
end
```

### Views

**Updated `providers/show.html.erb`**
- Added "Scan Handlers" button in header

**Updated `handlers/index.html.erb`**
- Added "Scan Handlers" button
- Shows two sections:
  1. Configured Handlers (from database) with edit/delete buttons
  2. Registered Handlers (from registry) not yet synced
- Grouped by event type

**New `handlers/edit.html.erb`**
- Form for editing handler configuration
- Read-only fields for provider and handler class
- Radio buttons for async/sync mode
- Number inputs for priority and max_attempts
- Text input for retry_delays (comma-separated)
- JavaScript to convert comma-separated to JSON array on submit
- Danger zone with soft-delete button

### Associations

**`Provider` model** (`app/models/captain_hook/provider.rb`)
- Added `has_many :handlers` association

### Tests

**New Test Files:**
1. `test/models/handler_test.rb` - Handler model tests
2. `test/services/handler_discovery_test.rb` - HandlerDiscovery service tests
3. `test/services/handler_sync_test.rb` - HandlerSync service tests

Tests cover:
- Model validations
- Soft delete functionality
- Scopes and associations
- Handler discovery from registry
- Handler sync to database
- Skipping deleted handlers
- Error handling

### Documentation

**New `docs/HANDLER_MANAGEMENT.md`**
- Comprehensive documentation of handler management feature
- Database schema details
- API usage examples
- Admin UI guide
- Migration instructions

**Updated `README.md`**
- Added handler management to features list
- Updated Admin Interface section with handler capabilities
- Link to detailed handler management documentation

## User Workflow

### Initial Setup
1. Register handlers in application code (e.g., initializer)
2. Navigate to admin interface
3. Click "Scan for Providers" or visit a provider and click "Scan Handlers"
4. Handlers are discovered and synced to database

### Configuration
1. Navigate to provider's handlers page
2. See list of configured handlers
3. Click "Edit" on a handler
4. Modify settings (async/sync, retries, priority, event type)
5. Save changes

### Management
1. View all handlers for a provider
2. Edit individual handler settings
3. Soft-delete handlers you don't want
4. Re-scan to sync new handlers from code
5. Deleted handlers won't be re-added

## Benefits

1. **Persistence**: Handler configurations persisted to database
2. **UI Configuration**: Change handler behavior without code changes
3. **Visibility**: Clear view of all handlers per provider
4. **Control**: Soft-delete handlers to prevent unwanted re-addition
5. **Flexibility**: Edit retry behavior, priority, and execution mode on-the-fly
6. **Sync Tracking**: See which handlers are configured vs. only in-memory

## Future Enhancements

Possible improvements:
- Bulk edit for multiple handlers
- Handler execution statistics
- Handler testing from UI
- Import/export handler configurations
- Handler scheduling (run at specific times)
- Conditional handler execution (filters)
