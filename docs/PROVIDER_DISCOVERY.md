# Provider Discovery System - Implementation Documentation

## High-Level Overview

The Provider Discovery System transforms CaptainHook from a manual UI-based provider configuration system to an automated, file-based discovery system. Instead of manually creating providers through the admin interface, developers now define providers in YAML configuration files which are automatically discovered and synced to the database.

### Key Benefits

1. **Version Control**: Provider configurations are now part of your codebase and can be version controlled
2. **Consistency**: Same provider configurations across environments (dev, staging, production)
3. **Security**: Signing secrets are referenced via environment variables, never committed to version control
4. **Scalability**: Works with monoliths and gems - any gem can ship its own webhook providers
5. **Automation**: "Discover New" adds new providers, "Full Sync" updates all from YAML
6. **Duplicate Detection**: Warns when the same provider exists in multiple sources

## Technical Implementation

### 1. YAML Configuration Format

Provider configurations are defined in YAML files with the following structure:

```yaml
# Location: captain_hook/providers/stripe.yml
name: stripe                                    # Required: unique identifier
display_name: Stripe                            # Optional: human-readable name
description: Stripe payment webhooks            # Optional: description
adapter_file: stripe.rb                         # Optional: file with signature verification adapter
active: true                                    # Optional: default true

# Security settings
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]     # Optional: ENV variable reference
timestamp_tolerance_seconds: 300                # Optional: replay attack prevention

# Rate limiting
rate_limit_requests: 100                        # Optional: max requests per period
rate_limit_period: 60                           # Optional: time period in seconds

# Payload limits
max_payload_size_bytes: 1048576                # Optional: max payload size
```

**Key Design Decisions:**

- **ENV Variable References**: The format `ENV[VARIABLE_NAME]` allows referencing environment variables for secrets
- **Optional Fields**: Most fields are optional with sensible defaults to minimize configuration
- **YAML Format**: Human-readable, widely supported, easy to diff in version control

### 2. Directory Structure

```
your_rails_app/
├── captain_hook/
│   ├── providers/          # Provider YAML configurations
│   │   ├── stripe.yml
│   │   ├── square.yml
│   │   └── webhook_site.yml
│   ├── handlers/           # Custom webhook event handlers
│   │   ├── stripe_payment_intent_handler.rb
│   │   └── square_bank_account_handler.rb
│   └── adapters/           # Custom signature verification adapters (optional)
│       └── custom_adapter.rb
└── ...

your_gem/
├── lib/
└── captain_hook/           # Gems can also define providers!
    ├── providers/
    │   └── my_service.yml
    ├── handlers/
    │   └── my_service_handler.rb
    └── adapters/
        └── my_service_adapter.rb
```

**Key Design Decisions:**

- **Centralized Location**: All webhook-related code in one `captain_hook/` directory
- **Gem Support**: Any gem can ship providers by including a `captain_hook/` directory
- **Separation of Concerns**: Providers, handlers, and adapters are in separate subdirectories

### 3. Provider Discovery Service

**Class**: `CaptainHook::Services::ProviderDiscovery`

**Purpose**: Scans the filesystem for provider YAML files and returns parsed provider definitions.

**Algorithm**:
1. Scan `Rails.root/captain_hook/providers/*.{yml,yaml}`
2. Scan all loaded gems for `<gem_root>/captain_hook/providers/*.{yml,yaml}`
3. Parse each YAML file
4. Add metadata (source_file, source) to each definition
5. Handle errors gracefully (log and skip malformed files)

**Key Code**:

```ruby
def call
  scan_application_providers
  scan_gem_providers
  @discovered_providers
end

def scan_gem_providers
  Gem.loaded_specs.each_value do |spec|
    gem_providers_path = File.join(spec.gem_dir, "captain_hook", "providers")
    next unless File.directory?(gem_providers_path)
    scan_directory(gem_providers_path, source: "gem:#{spec.name}")
  end
end
```

**Key Design Decisions:**

- **Graceful Degradation**: Missing directories or malformed YAML don't crash the system
- **Metadata Tracking**: Each provider knows its source file and origin (app vs gem)
- **Gem Integration**: Uses Ruby's `Gem.loaded_specs` to discover gems at runtime

### 4. Provider Sync Service

**Class**: `CaptainHook::Services::ProviderSync`

**Purpose**: Takes discovered provider definitions and creates/updates database records.

**Algorithm**:
1. For each provider definition:
   - Find or initialize provider by name
   - Map YAML fields to model attributes
   - Resolve ENV variable references for signing_secret
   - Save provider (create or update)
   - Track results (created, updated, errors)
2. Return results summary

**Key Code**:

```ruby
def resolve_signing_secret(secret_value)
  return nil if secret_value.blank?
  
  if secret_value.is_a?(String) && secret_value.match?(/\AENV\[([^\]]+)\]\z/)
    env_var = secret_value.match(/\AENV\[([^\]]+)\]\z/)[1]
    ENV[env_var]
  else
    secret_value
  end
end
```

**Key Design Decisions:**

- **Idempotency**: Running sync multiple times is safe - updates existing providers
- **ENV Variable Resolution**: Happens at sync time, not at file parse time
- **Error Collection**: Errors don't stop the entire sync, they're collected and reported
- **Secret Handling**: Only updates signing_secret if it's a new record or value changed

### 5. Admin UI Changes

**Controller**: `CaptainHook::Admin::ProvidersController`

**New Actions**: 
- `discover_new` (POST /captain_hook/admin/providers/discover_new) - Add new only
- `sync_all` (POST /captain_hook/admin/providers/sync_all) - Update all

**Algorithm**:
1. Call ProviderDiscovery service
2. If no providers found, show alert and exit
3. Call ProviderSync service with discovered providers
4. Build flash message from sync results
5. Redirect to provider index with results

**View Changes**:

```erb
<!-- Before: Add Provider button -->
<%= link_to "Add Provider", new_admin_provider_path, class: "btn btn-primary" %>

<!-- After: Discover New and Full Sync buttons -->
<div class="d-flex gap-2">
  <span data-bs-toggle="tooltip" data-bs-title="Add new providers/handlers only">
    <%= button_to "Discover New", discover_new_admin_providers_path, method: :post, 
        class: "btn btn-outline-primary",
        data: { confirm: "This will scan for NEW providers/handlers only. Continue?" } %>
  </span>
  <span data-bs-toggle="tooltip" data-bs-title="Update all from YAML files">
    <%= button_to "Full Sync", sync_all_admin_providers_path, method: :post,
        class: "btn btn-primary",
        data: { confirm: "This will update ALL providers/handlers from YAML. Continue?" } %>
  </span>
</div>
```

**Key Design Decisions:**

- **Two Scanning Modes**: "Discover New" (safe, no updates) vs "Full Sync" (updates everything)
- **Confirmation Dialogs**: Prevent accidental scans with clear descriptions
- **Detailed Feedback**: Shows count of created/updated/skipped/errored providers
- **Non-destructive Discovery**: "Discover New" doesn't modify existing providers
- **Duplicate Warnings**: Alerts when same provider exists in multiple sources

### 6. Autoloading Configuration

**Location**: `config/application.rb` (in host app)

```ruby
config.autoload_paths += [
  Rails.root.join("captain_hook", "handlers"),
  Rails.root.join("captain_hook", "adapters")
]
```

**Key Design Decisions:**

- **Automatic Loading**: Handlers and adapters are automatically loaded by Rails
- **No Manual Requires**: Developers don't need to manually require files
- **Zeitwerk Compatible**: Works with Rails' Zeitwerk autoloader

## Security Considerations

### 1. Signing Secrets

**Problem**: Signing secrets are sensitive and should never be committed to version control.

**Solution**: Use ENV variable references in YAML files:

```yaml
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
```

At sync time, the service resolves this to the actual environment variable value and stores it encrypted in the database.

### 2. Encryption at Rest

Provider signing secrets are encrypted in the database using Rails' ActiveRecord encryption:

```ruby
class Provider < ApplicationRecord
  encrypts :signing_secret, deterministic: false
end
```

The encryption happens automatically when saving the provider record.

### 3. Validation

Providers are validated before saving:

```ruby
validates :name, presence: true, uniqueness: true,
          format: { with: /\A[a-z0-9_]+\z/ }
validates :adapter_class, presence: true
```

Note: `adapter_class` is auto-extracted from the `adapter_file` during sync.

This prevents invalid or malicious provider configurations.

## Migration Path

### For Existing Installations

If you have existing providers created via the UI:

1. **Export to YAML**: Create YAML files for your existing providers
2. **Set ENV Variables**: Add signing secrets to your environment
3. **Run Full Sync**: Click "Full Sync" to update providers from YAML
4. **Verify**: Existing providers will be updated with YAML values

### For New Installations

1. **Create YAML Files**: Define your providers in `captain_hook/providers/`
2. **Set ENV Variables**: Add signing secrets to your environment
3. **Run Discover New**: Click "Discover New" to create providers
4. **Configure Handlers**: Register handlers in `config/initializers/captain_hook.rb`

## Testing

### Unit Tests

**Provider Discovery**:
- Tests YAML file discovery from app directory
- Tests gem directory scanning
- Tests malformed YAML handling
- Tests metadata inclusion

**Provider Sync**:
- Tests provider creation from definition
- Tests provider updates
- Tests ENV variable resolution
- Tests error handling
- Tests multiple provider sync

### Integration Testing

```ruby
# In test/dummy/captain_hook/providers/test.yml
name: test_provider
adapter_file: test.rb
signing_secret: ENV[TEST_SECRET]

# In test
ENV["TEST_SECRET"] = "test_value"
discovery = CaptainHook::Services::ProviderDiscovery.new
providers = discovery.call
sync = CaptainHook::Services::ProviderSync.new(providers)
results = sync.call

assert_equal 1, results[:created].size
provider = CaptainHook::Provider.find_by(name: "test_provider")
assert_equal "test_value", provider.signing_secret
```

## Future Enhancements

### 1. Handler Discovery

Currently handlers must be manually registered in initializers. Future enhancement:

```yaml
# captain_hook/providers/stripe.yml
handlers:
  - event_type: payment_intent.succeeded
    handler_class: StripePaymentIntentHandler
    priority: 100
    async: true
```

The sync service could automatically register handlers from YAML.

### 2. Adapter Discovery

Custom adapters are automatically discovered from the specified file:

```yaml
# captain_hook/providers/custom.yml
adapter_file: my_custom_adapter.rb  # Auto-detected from captain_hook/providers/custom/
```

### 3. Validation Rules

YAML files could include custom validation rules:

```yaml
# captain_hook/providers/stripe.yml
validation:
  event_id_format: /^evt_[a-zA-Z0-9]+$/
  required_headers:
    - Stripe-Signature
```

### 4. UI for YAML Editing

Add a "Edit as YAML" button in the UI that:
- Shows current provider config as YAML
- Allows editing in the browser
- Saves back to the YAML file
- Runs sync automatically

## Troubleshooting

### Provider Not Discovered

**Check**: Does the YAML file exist in `captain_hook/providers/`?
**Check**: Is the YAML valid? Test with: `ruby -ryaml -e "puts YAML.load_file('path/to/file.yml')"`
**Check**: Are there any errors in logs when clicking "Discover New" or "Full Sync"?
**Check**: For gem-provided providers, is the gem loaded in your Gemfile?

### ENV Variable Not Resolved

**Check**: Is the environment variable set? Test with: `echo $VARIABLE_NAME`
**Check**: Is the format correct? Should be: `ENV[VARIABLE_NAME]`
**Check**: Is the variable available when Rails starts? Check `.env` file or environment

### Provider Not Created

**Check**: Are there validation errors? Check the flash message after scan
**Check**: Does a provider with that name already exist?
**Check**: Is the adapter_file valid and does the adapter class exist in the file?

### Handlers Not Loading

**Check**: Is `captain_hook/handlers` in autoload_paths? Check `config/application.rb`
**Check**: Is the handler class name correct? Should match file name (CamelCase vs snake_case)
**Check**: Are handlers registered in `config/initializers/captain_hook.rb`?

## Summary

The Provider Discovery System provides a modern, developer-friendly approach to webhook configuration:

- **File-based**: Configuration as code, version controlled
- **Automated**: One-click scanning and sync
- **Secure**: Environment variables for secrets, encryption at rest
- **Flexible**: Works with monoliths and gems
- **Maintainable**: Clear separation of providers, handlers, and adapters

This implementation follows Rails conventions, uses modern Ruby features, and provides a solid foundation for webhook management at scale.
