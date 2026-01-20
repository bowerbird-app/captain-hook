# Remaining Test Files That Need Updates

## Overview

This document lists all test files that still reference removed Provider model fields. These files need to be updated to work with the new architecture where most provider configuration comes from YAML files rather than the database.

## Files Requiring Updates

### Model Tests

#### 1. test/models/incoming_event_test.rb
**Current Issue:** Creates provider with `verifier_class`

**Fix Required:**
```ruby
# BEFORE
@provider = CaptainHook::Provider.create!(
  name: "test_provider",
  verifier_class: "CaptainHook::Verifiers::Base"
)

# AFTER
@provider = CaptainHook::Provider.create!(
  name: "test_provider",
  active: true
)
# verifier_class now comes from registry YAML
```

#### 2. test/models/action_test.rb
**Current Issue:** Creates provider with `verifier_class` and `signing_secret`

**Fix Required:**
```ruby
# BEFORE
@provider = CaptainHook::Provider.create!(
  verifier_class: "StripeVerifier",
  signing_secret: "secret"
)

# AFTER
@provider = CaptainHook::Provider.create!(
  name: "test_provider",
  active: true
)
# verifier_class and signing_secret now come from registry YAML
```

#### 3. test/models/incoming_event_action_test.rb
**Current Issue:** Creates provider with `verifier_class`

**Fix Required:** Same as incoming_event_test.rb

### Controller Tests

#### 4. test/controllers/admin/sandbox_controller_test.rb
**Current Issue:** Creates provider with `verifier_class` and `signing_secret`

**Fix Required:**
```ruby
# BEFORE
@provider = CaptainHook::Provider.create!(
  verifier_class: "CaptainHook::Verifiers::Stripe",
  signing_secret: "test_secret"
)

# AFTER
@provider = CaptainHook::Provider.create!(
  name: "stripe",
  active: true
)
# Create corresponding YAML file or use existing stripe test provider
```

#### 5. test/controllers/admin/providers_controller_test.rb
**Current Issue:** Creates multiple providers with `verifier_class` and `signing_secret`

**Fix Required:**
```ruby
# BEFORE
post admin_providers_url, params: { 
  captain_hook_provider: {
    verifier_class: "CaptainHook::Verifiers::Paypal",
    signing_secret: "paypal_secret"
  }
}

# AFTER
post admin_providers_url, params: { 
  captain_hook_provider: {
    name: "paypal",
    active: true,
    rate_limit_requests: 100,
    rate_limit_period: 60
  }
}
# verifier_class and signing_secret must exist in YAML registry
```

#### 6. test/controllers/admin/incoming_events_controller_test.rb
**Current Issue:** Creates provider with `verifier_class` and `signing_secret`

**Fix Required:** Same as sandbox_controller_test.rb

#### 7. test/controllers/admin/actions_controller_test.rb
**Current Issue:** Creates provider with `verifier_class` and `signing_secret`

**Fix Required:** Same as sandbox_controller_test.rb

#### 8. test/controllers/incoming_controller_test.rb
**Current Issue:** Creates provider with ALL removed fields:
- `verifier_class`
- `signing_secret`
- `timestamp_tolerance_seconds`
- `max_payload_size_bytes`

**Fix Required:**
```ruby
# BEFORE
@provider = CaptainHook::Provider.create!(
  name: "stripe",
  verifier_class: "CaptainHook::Verifiers::Stripe",
  active: true,
  token: "test_token",
  signing_secret: "whsec_test123",
  timestamp_tolerance_seconds: 300,
  max_payload_size_bytes: 1_000_000,
  rate_limit_requests: 100,
  rate_limit_period: 60
)

# AFTER
@provider = CaptainHook::Provider.create!(
  name: "stripe",
  active: true,
  token: "test_token",
  rate_limit_requests: 100,
  rate_limit_period: 60
)

# For integration tests that need signing_secret:
# Either:
# 1. Use existing test/dummy/captain_hook/stripe/ YAML definition
# 2. Set ENV variable: ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test123"
# 3. Mock the Configuration.provider() method to return ProviderConfig with signing_secret
```

## Strategy for Fixing Tests

### Option 1: Use Existing Test Provider YAMLs
The test/dummy app already has provider YAML files:
- `test/dummy/captain_hook/stripe/stripe.yml`
- `test/dummy/captain_hook/square/square.yml`
- `test/dummy/captain_hook/paypal/paypal.yml`
- `test/dummy/captain_hook/webhook_site/webhook_site.yml`

**Recommended for:** Controller and integration tests that test real webhook flows

**Steps:**
1. Remove removed fields from Provider.create!
2. Ensure corresponding YAML exists in test/dummy/captain_hook/
3. Set ENV variables for secrets if needed
4. Tests will get configuration from Configuration.provider() which merges DB + YAML + global config

### Option 2: Create Test-Specific YAMLs
For tests that need custom configuration

**Recommended for:** Tests that need specific verifier_class or config values

**Steps:**
1. Create helper method to generate YAML files in setup
2. Clean up YAML files in teardown
3. Use the same pattern as in the updated provider_test.rb

### Option 3: Mock Configuration.provider()
For unit tests that don't need real YAML files

**Recommended for:** Fast unit tests that just need provider config

**Steps:**
```ruby
# In test setup
config = CaptainHook::ProviderConfig.new(
  name: "test_provider",
  verifier_class: "CaptainHook::Verifiers::Base",
  signing_secret: "test_secret",
  active: true
)

# Mock the configuration lookup
CaptainHook::Configuration.any_instance.stubs(:provider).with("test_provider").returns(config)
```

## Priority Order for Fixes

1. **HIGH PRIORITY:**
   - test/controllers/incoming_controller_test.rb (webhook verification tests)
   - test/models/incoming_event_test.rb (core model tests)

2. **MEDIUM PRIORITY:**
   - test/controllers/admin/providers_controller_test.rb (admin functionality)
   - test/models/action_test.rb (action registration tests)

3. **LOW PRIORITY:**
   - Other admin controller tests (mostly UI tests)

## Testing Strategy After Updates

1. **Run migration in test database:**
   ```bash
   cd test/dummy
   RAILS_ENV=test bin/rails db:migrate
   ```

2. **Verify test provider YAMLs exist:**
   ```bash
   ls -la test/dummy/captain_hook/*/
   ```

3. **Run updated tests individually:**
   ```bash
   bundle exec rake test TEST=test/models/incoming_event_test.rb
   ```

4. **Run full test suite:**
   ```bash
   bundle exec rake test
   ```

## Common Patterns

### Pattern 1: Simple Model Test
```ruby
setup do
  @provider = CaptainHook::Provider.create!(
    name: "test_provider",
    active: true
  )
end
```

### Pattern 2: Controller Test with Real Provider
```ruby
setup do
  # Uses existing test/dummy/captain_hook/stripe/stripe.yml
  @provider = CaptainHook::Provider.create!(
    name: "stripe",
    active: true,
    token: "test_token"
  )
  
  # Set secret in ENV for verification tests
  ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test123"
end

teardown do
  ENV.delete("STRIPE_WEBHOOK_SECRET")
end
```

### Pattern 3: Test with Custom YAML
```ruby
setup do
  @provider = CaptainHook::Provider.create!(
    name: "custom_test",
    active: true
  )
  
  create_test_provider_yaml("custom_test", 
    verifier_class: "CustomVerifier",
    signing_secret: "ENV[CUSTOM_SECRET]"
  )
  
  ENV["CUSTOM_SECRET"] = "test_secret_123"
end

teardown do
  cleanup_test_provider_yaml("custom_test")
  ENV.delete("CUSTOM_SECRET")
end

def create_test_provider_yaml(name, **config)
  # Implementation similar to provider_test.rb
end
```

## Notes

- **Do NOT** try to add removed columns back to the database
- **Do NOT** modify the migration - it correctly removes the columns
- **Do** use the Configuration.provider() method to get full provider config
- **Do** separate DB concerns (token, rate limits) from registry concerns (verifier, secrets)
- **Do** use ENV variables for secrets in tests
