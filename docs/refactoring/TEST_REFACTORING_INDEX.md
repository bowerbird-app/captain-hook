# Test Refactoring Documentation Index

This directory contains comprehensive documentation for the Provider model test refactoring. These documents were created as part of the migration from database-centric provider configuration to a registry-based (YAML) architecture.

## Quick Start

**If you just want to know what changed:**
→ Read [CHANGES_DIFF.md](./CHANGES_DIFF.md)

**If you need to update more test files:**
→ Read [REMAINING_TEST_UPDATES.md](./REMAINING_TEST_UPDATES.md)

**If you want the full context:**
→ Read [TEST_REFACTORING_SUMMARY.md](./TEST_REFACTORING_SUMMARY.md)

**If you want status and next steps:**
→ Read [COMPLETION_SUMMARY.md](./COMPLETION_SUMMARY.md)

---

## Document Overview

### 1. [CHANGES_DIFF.md](./CHANGES_DIFF.md)
**Purpose:** Show exact before/after code changes  
**Best for:** Developers who want to see precise diffs  
**Contents:**
- Setup method transformations
- Removed test examples
- Updated test examples
- New test examples
- Statistics on changes made

### 2. [REMAINING_TEST_UPDATES.md](./REMAINING_TEST_UPDATES.md)
**Purpose:** Guide for updating additional test files  
**Best for:** Developers continuing the refactoring work  
**Contents:**
- List of 8+ test files that need updates
- Three strategies for fixing tests:
  - Use existing provider YAMLs
  - Create test-specific YAMLs
  - Mock Configuration.provider()
- Priority order for fixes
- Common patterns and code examples
- Testing strategy

### 3. [TEST_REFACTORING_SUMMARY.md](./TEST_REFACTORING_SUMMARY.md)
**Purpose:** Comprehensive architectural overview  
**Best for:** Understanding the big picture and migration path  
**Contents:**
- Architecture changes (DB vs Registry vs Global Config)
- Detailed test file changes
- Testing instructions
- Migration path for existing installations
- Benefits of new architecture
- Future improvements

### 4. [COMPLETION_SUMMARY.md](./COMPLETION_SUMMARY.md)
**Purpose:** Project status and completion checklist  
**Best for:** Project managers and developers tracking progress  
**Contents:**
- Task overview
- Files updated (✅ completed)
- Documentation created
- Test execution status
- Key principles maintained
- Next steps (immediate, short-term, long-term)
- Breaking changes summary
- Verification checklist
- Questions and considerations

---

## Architecture Summary

### What Changed

**Database (Provider Model)** - Simplified to runtime state only:
- ✅ `name`, `token`, `active`
- ✅ `rate_limit_requests`, `rate_limit_period`
- ❌ ~~`display_name`, `description`, `signing_secret`~~
- ❌ ~~`verifier_class`, `verifier_file`~~
- ❌ ~~`timestamp_tolerance_seconds`, `max_payload_size_bytes`~~

**Registry (YAML Files)** - Provider configuration:
- Location: `captain_hook/<provider>/provider.yml`
- Contains: verifier setup, display info, signing secrets (ENV refs)

**Global Config** - Application-wide defaults:
- Location: `config/captain_hook.yml`
- Contains: `max_payload_size_bytes`, `timestamp_tolerance_seconds`

### Why This Matters for Tests

1. **Can't create providers with removed fields**
   ```ruby
   # ❌ This will fail
   Provider.create!(verifier_class: "Stripe", signing_secret: "secret")
   
   # ✅ This works
   Provider.create!(name: "stripe", active: true)
   ```

2. **Need YAML files for integration tests**
   ```ruby
   # Tests that verify webhooks need provider YAML files
   # Either use existing test/dummy/captain_hook/stripe/stripe.yml
   # Or create test-specific YAMLs in setup/teardown
   ```

3. **Use Configuration.provider() for full config**
   ```ruby
   # ❌ Provider model no longer has verifier_class
   provider.verifier_class
   
   # ✅ Use ProviderConfig from Configuration
   config = CaptainHook.configuration.provider("stripe")
   config.verifier_class
   config.signing_secret  # Resolves ENV variables
   ```

---

## Test Files Status

### ✅ Completed (4 files)
1. `test/models/provider_test.rb`
2. `test/services/provider_sync_test.rb`
3. `test/provider_config_test.rb`
4. `test/lib/captain_hook/provider_config_additional_test.rb`

### ⏳ Remaining (8+ files)
1. `test/models/incoming_event_test.rb`
2. `test/models/action_test.rb`
3. `test/models/incoming_event_action_test.rb`
4. `test/controllers/admin/sandbox_controller_test.rb`
5. `test/controllers/admin/providers_controller_test.rb`
6. `test/controllers/admin/incoming_events_controller_test.rb`
7. `test/controllers/admin/actions_controller_test.rb`
8. `test/controllers/incoming_controller_test.rb`

See [REMAINING_TEST_UPDATES.md](./REMAINING_TEST_UPDATES.md) for details.

---

## Quick Reference

### Creating a Test Provider

```ruby
# In setup
@provider = CaptainHook::Provider.create!(
  name: "test_provider",
  active: true,
  token: "test_token_123",           # optional - auto-generated if nil
  rate_limit_requests: 100,          # optional
  rate_limit_period: 60              # optional
)

# If you need verifier/signing_secret for testing:
# Option 1: Use existing YAML
# test/dummy/captain_hook/stripe/stripe.yml already exists

# Option 2: Create test YAML
create_test_provider_yaml("test_provider",
  verifier_class: "TestVerifier",
  signing_secret: "ENV[TEST_SECRET]"
)
ENV["TEST_SECRET"] = "secret123"

# Option 3: Mock Configuration.provider()
config = ProviderConfig.new(
  name: "test_provider",
  verifier_class: "TestVerifier",
  signing_secret: "secret123"
)
CaptainHook.configuration.stubs(:provider).returns(config)
```

### Getting Full Provider Config

```ruby
# ❌ OLD WAY (no longer works)
provider = Provider.find_by(name: "stripe")
provider.verifier_class  # Column doesn't exist!
provider.signing_secret  # Column doesn't exist!

# ✅ NEW WAY
provider_config = CaptainHook.configuration.provider("stripe")
provider_config.verifier_class      # From YAML
provider_config.signing_secret      # From YAML (resolves ENV)
provider_config.token               # From database
provider_config.active              # From database
provider_config.rate_limit_requests # From database
provider_config.timestamp_tolerance_seconds # From global config
provider_config.max_payload_size_bytes      # From global config
```

---

## Running Tests

### Prerequisites
```bash
# 1. Run migration in test database
cd test/dummy
RAILS_ENV=test bin/rails db:migrate

# 2. Verify test provider YAMLs exist
ls -la test/dummy/captain_hook/*/
```

### Execute Tests
```bash
# Run individual test files
bundle exec rake test TEST=test/models/provider_test.rb
bundle exec rake test TEST=test/services/provider_sync_test.rb

# Run all tests
bundle exec rake test

# Check for syntax errors
ruby -c test/models/provider_test.rb
```

---

## Support

If you encounter issues:

1. **Migration errors:** Check that `db/migrate/20260120015225_simplify_providers_table.rb` ran successfully
2. **Column errors:** Verify you're not trying to access removed columns
3. **YAML errors:** Check that provider YAML files exist and are valid
4. **ENV variable errors:** Make sure signing secrets reference valid ENV variables

For detailed troubleshooting, see the individual documentation files listed above.

---

## Contributing

When updating more tests:

1. Follow the patterns in completed files
2. Update [REMAINING_TEST_UPDATES.md](./REMAINING_TEST_UPDATES.md) as you complete files
3. Add any new patterns or gotchas to the documentation
4. Update the checklist in [COMPLETION_SUMMARY.md](./COMPLETION_SUMMARY.md)

---

## Related Files

### Implementation Files
- `app/models/captain_hook/provider.rb` - Simplified Provider model
- `lib/captain_hook/provider_config.rb` - ProviderConfig struct
- `lib/captain_hook/configuration.rb` - Configuration.provider() method
- `lib/captain_hook/services/provider_sync.rb` - Syncs YAML to database
- `lib/captain_hook/services/global_config_loader.rb` - Loads global config

### Migration Files
- `db/migrate/20260120015225_simplify_providers_table.rb` - Removes columns
- `test/dummy/db/migrate/` - Test database migrations

### Provider YAML Examples
- `test/dummy/captain_hook/stripe/stripe.yml`
- `test/dummy/captain_hook/square/square.yml`
- `test/dummy/captain_hook/paypal/paypal.yml`
- `test/dummy/captain_hook/webhook_site/webhook_site.yml`

---

**Last Updated:** January 20, 2026  
**Refactoring Status:** Phase 1 Complete (Core Tests), Phase 2 Pending (Additional Tests)
