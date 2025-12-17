# Inter-Gem Communication - Implementation Summary

## Overview

This implementation adds a comprehensive inter-gem communication system to CaptainHook, transforming it into a webhook hub that other gems can integrate with through auto-discovery.

## What Was Built

### 1. Database Schema (Migration)
**File:** `db/migrate/20251217000001_add_gem_source_to_providers_and_handlers.rb`

- Added `gem_source` column to `captain_hook_providers` table
- Added `gem_source` column to `captain_hook_incoming_event_handlers` table
- Added indexes on both columns for efficient querying

### 2. Provider Loader
**File:** `lib/captain_hook/provider_loader.rb`

- Scans all installed gems for `config/captain_hook_providers.yml`
- Automatically registers providers from YAML configuration
- Uses `YAML.safe_load_file` for security
- Validates configuration data types
- Specific error handling for different failure types
- Re-raises critical infrastructure errors

### 3. Handler Loader
**File:** `lib/captain_hook/handler_loader.rb`

- Scans all installed gems for `config/captain_hook_handlers.yml`
- Automatically registers handlers from YAML configuration
- Uses `YAML.safe_load_file` for security
- Validates configuration data types
- Specific error handling with appropriate logging
- Graceful handling of per-gem failures

### 4. Enhanced Handler Registry
**File:** `lib/captain_hook/handler_registry.rb`

- Added `gem_source` field to HandlerConfig struct
- Tracks which gem provides each handler
- Maintains backward compatibility with existing registrations

### 5. Programmatic API
**File:** `lib/captain_hook.rb`

- `CaptainHook.register_provider()`: Register providers programmatically
- Enhanced `CaptainHook.register_handler()`: Accept gem_source parameter
- Logging when models aren't loaded for debugging

### 6. Engine Integration
**File:** `lib/captain_hook/engine.rb`

- Added `captain_hook.load_gem_configurations` initializer
- Runs after `:load_config_initializers` to ensure proper timing
- Auto-loads providers and handlers on application boot

### 7. Model Enhancements

**Provider Model** (`app/models/captain_hook/provider.rb`):
- Scopes: `from_gem`, `gem_provided`, `manually_created`
- Methods: `gem_provided?`, `manually_created?`

**IncomingEventHandler Model** (`app/models/captain_hook/incoming_event_handler.rb`):
- Scopes: `from_gem`, `gem_provided`, `manually_created`
- Methods: `gem_provided?`, `manually_created?`

### 8. Comprehensive Tests

**Provider Loader Tests** (`test/provider_loader_test.rb`):
- Single provider registration
- Multiple providers registration
- Empty configuration handling
- Missing keys handling
- Edge cases

**Handler Loader Tests** (`test/handler_loader_test.rb`):
- Single handler registration
- Multiple handlers registration
- Empty configuration handling
- Edge cases
- Gem source tracking

**Integration Tests** (`test/gem_communication_test.rb`):
- Programmatic API tests
- Multiple gem scenarios
- Backward compatibility
- Handler config structure

### 9. Documentation

**Inter-Gem Communication Guide** (`docs/INTER_GEM_COMMUNICATION.md`):
- Complete guide with examples
- YAML configuration format
- Programmatic API reference
- Security considerations
- Benefits and limitations

**Example Integration** (`docs/EXAMPLE_GEM_INTEGRATION.md`):
- Complete gem structure
- Real-world example with Stripe
- Handler implementations
- Best practices

**README Updates** (`README.md`):
- Quick start guide
- Integration examples
- Links to detailed docs

## Key Design Decisions

### 1. YAML-First Approach
Used YAML configuration as the primary method because:
- Simple and declarative
- Easy to understand and maintain
- Standard Rails convention
- Programmatic API available as alternative

### 2. Safe YAML Loading
Used `YAML.safe_load_file` instead of `YAML.load_file`:
- Prevents arbitrary code execution
- Security best practice
- No performance penalty

### 3. Array-Only Validation
Required `providers` and `handlers` to be arrays:
- Prevents ambiguous configurations
- Simpler to understand and debug
- Clear error messages when format is wrong

### 4. Specific Error Handling
Categorized errors by type:
- YAML syntax errors: Logged per-gem
- Database errors: Re-raised (critical)
- Validation errors: Logged per-gem
- Infrastructure errors: Re-raised (critical)

Benefits:
- Per-gem failures don't break other gems
- Critical failures cause fast fail
- Clear error messages for debugging

### 5. Fail-Fast Philosophy
Critical errors (database connection, missing tables) cause initialization to fail:
- Prevents running with broken configuration
- Makes problems obvious immediately
- Better than silent failures

### 6. Single Responsibility
Error handling at the loader level only:
- Engine initializer just calls loaders
- No duplicate error handling
- Clear separation of concerns

### 7. Tracking Gem Source
Added `gem_source` to both providers and handlers:
- Admin UI can show which gem provides what
- Debugging: Know which gem to update
- Future: Could add gem version tracking

### 8. Backward Compatibility
Existing code continues to work:
- `gem_source` defaults to nil
- Existing handler registrations unchanged
- New scopes don't break existing queries

## Usage Patterns

### Pattern 1: YAML-Based Integration (Recommended)

```ruby
# In your gem: config/captain_hook_providers.yml
providers:
  - name: stripe
    display_name: Stripe
    adapter_class: MyGem::StripeAdapter

# In your gem: config/captain_hook_handlers.yml
handlers:
  - provider: stripe
    event_type: invoice.paid
    handler_class: MyGem::InvoiceHandler
```

### Pattern 2: Programmatic Integration

```ruby
# In your gem's engine.rb
class Engine < ::Rails::Engine
  initializer "my_gem.register_webhooks", after: :load_config_initializers do
    Rails.application.config.after_initialize do
      CaptainHook.register_provider(
        name: "stripe",
        display_name: "Stripe",
        adapter_class: "MyGem::StripeAdapter",
        gem_source: "my_gem"
      )
      
      CaptainHook.register_handler(
        provider: "stripe",
        event_type: "invoice.paid",
        handler_class: "MyGem::InvoiceHandler",
        gem_source: "my_gem"
      )
    end
  end
end
```

## Security Considerations

1. **Safe YAML**: Uses `YAML.safe_load_file` to prevent code execution
2. **Validation**: Validates data types before processing
3. **Trusted Gems**: Only install webhook gems from trusted sources
4. **Documentation**: Comprehensive security section in docs
5. **Environment Variables**: Never commit secrets to gem source

## Testing Strategy

1. **Unit Tests**: Each loader tested independently
2. **Edge Cases**: Empty configs, missing keys, invalid formats
3. **Integration**: Full system tested end-to-end
4. **Backward Compatibility**: Existing registrations still work

## Future Enhancements

Potential future improvements:

1. **Gem Version Tracking**: Track which version of gem provided config
2. **Admin UI**: Show gem source in provider/handler lists
3. **Gem Removal**: Handle when gems are uninstalled
4. **Configuration Override**: Allow host app to override gem configs
5. **Dependency Resolution**: Handle when multiple gems provide same provider
6. **Pub/Sub Pattern**: Optional ActiveSupport::Notifications broadcasting

## Files Changed

- **New Migration**: 1 file
- **New Classes**: 2 files (ProviderLoader, HandlerLoader)
- **Modified Classes**: 4 files (Engine, HandlerRegistry, Provider, IncomingEventHandler)
- **New Tests**: 3 files
- **Documentation**: 3 files (2 new, 1 updated)

Total: 14 files

## Benefits Delivered

✅ **Zero Configuration**: Install gem → webhooks work
✅ **Secure**: Safe YAML loading with validation
✅ **Reliable**: Fail-fast on critical errors
✅ **Decoupled**: Gems don't depend on each other
✅ **Discoverable**: Track which gem provides what
✅ **Flexible**: YAML or code-based registration
✅ **Maintainable**: Each gem owns its webhook logic
✅ **Backward Compatible**: Existing code unaffected
✅ **Well Documented**: Complete guides and examples
✅ **Tested**: Comprehensive test coverage

## Migration Guide for Gem Authors

To add CaptainHook integration to your gem:

1. Add `captain_hook` to your gemspec dependencies
2. Create `config/captain_hook_providers.yml` (if providing a new provider)
3. Create `config/captain_hook_handlers.yml` 
4. Implement handler classes in `app/captain_hook_handlers/your_gem/`
5. (Optional) Create custom adapter in `lib/your_gem/`
6. Document webhook integration in your gem's README

That's it! Your gem will automatically integrate with CaptainHook.
