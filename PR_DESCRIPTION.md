# Pull Request: Refactor Providers to Use Registry as Source of Truth

## Summary

This PR implements a major architectural refactor of the CaptainHook provider system to use the registry (YAML files) as the source of truth, with minimal database storage for runtime data only. This aligns with modern Rails practices where configuration is code-based rather than database-driven.

## Problem Statement

The previous architecture stored all provider configuration in the database, making it difficult to:
- Version control provider configurations
- Share provider setups across environments
- Manage signing secrets securely (stored encrypted in DB)
- Override settings at different levels (application-wide vs per-provider)

## Solution

### Three-Tier Configuration System

1. **Registry (YAML files)** - Source of truth for provider metadata
   - `verifier_class`, `verifier_file`
   - `display_name`, `description`
   - `signing_secret` (as ENV reference)
   
2. **Database** - Runtime operational data only
   - `name`, `token`, `active`
   - `rate_limit_requests`, `rate_limit_period`
   
3. **Global Config** - Application-wide defaults
   - `max_payload_size_bytes` (default: 1MB)
   - `timestamp_tolerance_seconds` (default: 300s)
   - Per-provider overrides

## Changes Made

### Database Migration
- **Created**: `db/migrate/20260120015225_simplify_providers_table.rb`
- **Removes 8 columns**: display_name, description, signing_secret, verifier_class, verifier_file, timestamp_tolerance_seconds, max_payload_size_bytes, metadata
- **Retains 7 columns**: name, token, active, rate_limit_requests, rate_limit_period, created_at, updated_at

### New Services
- **GlobalConfigLoader** - Loads `config/captain_hook.yml` for application-wide defaults
- Supports per-provider overrides
- Provides sensible defaults if config file doesn't exist

### Core Refactors
1. **Provider Model** (`app/models/captain_hook/provider.rb`)
   - Removed encryption for signing_secret
   - Removed validations for deleted columns
   - Simplified to manage only DB-stored fields
   
2. **Configuration Class** (`lib/captain_hook/configuration.rb`)
   - Refactored `provider()` to build ProviderConfig from 3 sources
   - Added registry lookup caching
   - Combines DB + registry + global config
   
3. **ProviderConfig** (`lib/captain_hook/provider_config.rb`)
   - Updated to load defaults from GlobalConfigLoader
   - Maintains backward compatibility
   
4. **ProviderSync** (`lib/captain_hook/services/provider_sync.rb`)
   - Only syncs DB-managed fields (active, rate limits)
   - Removed signing secret and verifier class syncing

### Test Updates
- **provider_test.rb**: Removed ~150 lines for deleted columns
- **provider_sync_test.rb**: Updated to test only DB field syncing
- **provider_config_test.rb**: Added GlobalConfigLoader integration tests

### Documentation
- **Migration Guide**: Complete step-by-step migration instructions
- **Implementation Summary**: Comprehensive overview of all changes
- **Test Refactoring Docs**: Detailed test update documentation
- **Updated README**: New architecture, global config, ENV variables

## Configuration Priority

New clear priority order for settings:

### For `max_payload_size_bytes` and `timestamp_tolerance_seconds`:
1. Provider YAML file (highest)
2. Global config per-provider override
3. Global config default
4. Built-in default (lowest)

### For `rate_limit_requests` and `rate_limit_period`:
1. Database value (set via admin UI)
2. Provider YAML file (synced to DB on boot)
3. Built-in defaults

### For provider metadata:
1. Provider YAML file (only source)

### For `signing_secret`:
1. Environment variable (via `ENV[VARIABLE_NAME]` reference in YAML)

## Example Usage

### Provider YAML (before):
```yaml
name: stripe
display_name: Stripe
verifier_class: CaptainHook::Verifiers::Stripe
signing_secret: whsec_abc123  # Stored encrypted in DB
timestamp_tolerance_seconds: 300
max_payload_size_bytes: 1048576
```

### Provider YAML (after):
```yaml
name: stripe
display_name: Stripe
description: Stripe payment webhooks
verifier_file: stripe.rb
active: true
signing_secret: ENV[STRIPE_WEBHOOK_SECRET]  # References ENV
# timestamp and payload settings now from global config
# Can override if needed:
# timestamp_tolerance_seconds: 600
```

### Global Config (new):
```yaml
# config/captain_hook.yml
defaults:
  max_payload_size_bytes: 1048576
  timestamp_tolerance_seconds: 300

providers:
  stripe:
    max_payload_size_bytes: 2097152  # 2MB for Stripe
```

### Environment Variables (new):
```bash
STRIPE_WEBHOOK_SECRET=whsec_xxxxx
SQUARE_WEBHOOK_SECRET=your_secret
```

## Migration Steps

1. **Run migration**:
   ```bash
   rails captain_hook:install:migrations
   rails db:migrate
   ```

2. **Create global config** (optional):
   ```bash
   cp config/captain_hook.yml.example config/captain_hook.yml
   ```

3. **Set environment variables**:
   ```bash
   # Add to .env
   STRIPE_WEBHOOK_SECRET=whsec_xxxxx
   ```

4. **Verify provider YAML files** have ENV references:
   ```yaml
   signing_secret: ENV[STRIPE_WEBHOOK_SECRET]
   ```

## Benefits

✅ **Version Control**: Provider configs in YAML, tracked in git
✅ **Security**: Signing secrets in ENV, not database
✅ **Flexibility**: Three-tier configuration with clear precedence
✅ **Maintainability**: Clear separation of concerns
✅ **Portability**: Easy to share provider setups
✅ **DRY**: Global defaults, per-provider overrides

## Breaking Changes

⚠️ **Database columns removed** - Migration is required
⚠️ **Signing secrets** must be moved to environment variables
⚠️ **Provider metadata** must be in YAML files

## Testing Status

✅ **Code Changes**: Complete
✅ **Test Updates**: Complete
✅ **Documentation**: Complete
⏳ **Test Execution**: Requires Ruby 3.3.0 + bundler (not in CI)
⏳ **Migration Run**: Requires local execution
⏳ **Rubocop**: Requires local execution

## Files Changed

### Created (13 files)
- `db/migrate/20260120015225_simplify_providers_table.rb`
- `lib/captain_hook/services/global_config_loader.rb`
- `config/captain_hook.yml.example`
- `test/dummy/config/captain_hook.yml`
- `docs/MIGRATION_GUIDE.md`
- `docs/IMPLEMENTATION_SUMMARY.md`
- 5 refactoring documentation files

### Modified (9 files)
- `app/models/captain_hook/provider.rb`
- `lib/captain_hook/configuration.rb`
- `lib/captain_hook/provider_config.rb`
- `lib/captain_hook/services/provider_sync.rb`
- `lib/captain_hook.rb`
- `README.md`
- 3 test files

## Next Steps

After merging, users should:
1. Read the migration guide
2. Run the migration
3. Set environment variables
4. Verify provider YAML files
5. Test in development
6. Deploy to production

## Documentation

- **Migration Guide**: `docs/MIGRATION_GUIDE.md`
- **Implementation Summary**: `docs/IMPLEMENTATION_SUMMARY.md`
- **Test Refactoring**: `docs/refactoring/TEST_REFACTORING_INDEX.md`
- **Main README**: Updated architecture section

## Related Issues

Closes #[issue-number] (if applicable)

## Checklist

- [x] Code changes implemented
- [x] Tests updated
- [x] Documentation created
- [x] Migration guide written
- [x] README updated
- [ ] Migration executed (requires local environment)
- [ ] Tests pass (requires Ruby 3.3.0)
- [ ] Rubocop passes (requires local environment)
- [ ] Manual verification (requires local environment)

---

**Review Focus Areas**:
1. Database migration is correct
2. Configuration precedence makes sense
3. Provider model simplification is appropriate
4. Test updates cover all cases
5. Documentation is clear and complete
