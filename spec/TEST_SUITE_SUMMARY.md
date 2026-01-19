# RSpec Test Suite Summary

## Overview

This document provides a high-level summary of the comprehensive RSpec test suite created for the Captain Hook webhook system.

## Test Files Created

### 1. Configuration Files

- **`.rspec`**: RSpec configuration for formatting and options
- **`spec/spec_helper.rb`**: Base RSpec configuration
- **`spec/rails_helper.rb`**: Rails-specific test configuration with database setup

### 2. Factories (`spec/factories/`)

- **`captain_hook_factories.rb`**: FactoryBot definitions for:
  - Providers (with traits for Stripe, Square, PayPal, WebhookSite)
  - Incoming events
  - Actions
  - Incoming event actions

### 3. Request Specs (`spec/requests/`)

- **`incoming_webhooks_spec.rb`**: Comprehensive webhook reception tests
  - Successful webhook reception and event creation
  - Idempotency and duplicate detection
  - Authentication (token, provider status)
  - Signature verification (valid, invalid, missing, expired)
  - Rate limiting
  - Payload size limits
  - Invalid JSON handling
  - Multiple provider support

### 4. Verifier Specs (`spec/lib/captain_hook/verifiers/`)

- **`stripe_spec.rb`**: Stripe HMAC-SHA256 hex signature verification
- **`square_spec.rb`**: Square HMAC-SHA256 Base64 signature verification
- **`paypal_spec.rb`**: PayPal certificate-based verification (simplified)
- **`webhook_site_spec.rb`**: No-verification testing verifier

### 5. Model Specs (`spec/models/`)

- **`provider_spec.rb`**: Provider model tests
  - Validations (presence, uniqueness, format, numericality)
  - Callbacks (name normalization, token generation)
  - Associations (incoming_events, actions)
  - Scopes (active, inactive, by_name)
  - Webhook URL generation
  - Rate limiting checks
  - Signing secret encryption
  - Verifier instantiation

### 6. Library Specs (`spec/lib/captain_hook/`)

- **`handler_registry_spec.rb`**: Action registry tests
  - Action registration
  - Action lookup by provider and event type
  - Wildcard event type matching
  - Priority-based ordering
  - Thread safety

### 7. Integration Specs (`spec/integration/`)

- **`complex_webhook_scenarios_spec.rb`**: Complex real-world scenarios
  - Third-party gem + Rails app sharing same webhook (same secret)
  - Separate webhook providers for gem and app
  - Action execution outcomes (success/failure)
  - Async vs Sync execution
  - Multiple providers with same verifier but different secrets

## Scenario Coverage

### Scenario 1: Third-Party Gem + Rails App (Same Webhook)

**Use Case**: A payment gem and your Rails app both need to handle the same Stripe webhooks.

**Tests**:
- Both actions execute for the same webhook
- Actions execute in priority order
- Shared signing secret works correctly
- Event metadata tracks both action executions

### Scenario 2: Third-Party Gem + Rails App (Different Webhooks)

**Use Case**: A payment gem handles its Stripe account, your app handles a different Stripe account.

**Tests**:
- Webhooks route to correct actions based on provider
- Separate event histories maintained per provider
- Different signing secrets verified correctly

### Scenario 3: Action Execution Outcomes

**Use Case**: Testing both successful and failing actions.

**Tests**:
- Successful actions marked as completed
- Failed actions marked as failed with error messages
- Status tracking and metadata updates

### Scenario 4: Async vs Sync Execution

**Use Case**: Some actions need immediate execution, others can be async.

**Tests**:
- Async actions enqueued as background jobs
- Sync actions executed immediately
- Proper status tracking for both types

### Scenario 5: Multiple Providers (Same Verifier, Different Secrets)

**Use Case**: Multiple Stripe accounts (personal, business, client accounts).

**Tests**:
- Each provider has unique signing secret
- Signature verification uses correct provider secret
- Unique webhook URLs per provider

## Running the Test Suite

### All Tests

```bash
bundle exec rspec
```

### Specific Test Files

```bash
# Request specs
bundle exec rspec spec/requests/incoming_webhooks_spec.rb

# Integration specs
bundle exec rspec spec/integration/complex_webhook_scenarios_spec.rb

# Verifier specs
bundle exec rspec spec/lib/captain_hook/verifiers/stripe_spec.rb
bundle exec rspec spec/lib/captain_hook/verifiers/square_spec.rb
bundle exec rspec spec/lib/captain_hook/verifiers/paypal_spec.rb
bundle exec rspec spec/lib/captain_hook/verifiers/webhook_site_spec.rb

# Model specs
bundle exec rspec spec/models/provider_spec.rb

# Registry specs
bundle exec rspec spec/lib/captain_hook/handler_registry_spec.rb
```

### With Rake

```bash
bundle exec rake spec
# or
bundle exec rake rspec
```

## Test Helpers

### FactoryBot Factories

Create test data easily:

```ruby
# Create a Stripe provider
provider = create(:captain_hook_provider, :stripe)

# Create with custom attributes
provider = create(:captain_hook_provider, :square, name: "square_test")

# Build without saving
provider = build(:captain_hook_provider, :with_rate_limiting)
```

### Signature Generation Helpers

Generate valid signatures for testing:

```ruby
# Stripe signature
def generate_stripe_signature(payload, secret, timestamp = Time.current.to_i)
  signed_payload = "#{timestamp}.#{payload}"
  signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
  "t=#{timestamp},v1=#{signature}"
end

# Square signature
def generate_square_signature(notification_url, payload, secret)
  OpenSSL::HMAC.base64digest("SHA256", secret, notification_url + payload)
end
```

## Dependencies

- **rspec-rails** (~> 6.1): Rails integration for RSpec
- **factory_bot_rails** (~> 6.4): Test data generation
- **faker** (~> 3.2): Realistic fake data
- **shoulda-matchers** (~> 6.0): Rails validation matchers
- **webmock** (~> 3.19): HTTP request stubbing

## CI Integration

The GitHub Actions CI workflow runs RSpec tests automatically:

```yaml
- name: Run RSpec tests
  run: bundle exec rspec
  env:
    DATABASE_URL: postgres://postgres:postgres@localhost:5432/gem_template_test
```

## Best Practices

1. **Test Isolation**: Each test runs in a transaction that's rolled back
2. **Action Registry Cleanup**: Registry cleared before each test
3. **Factory Usage**: Use factories for consistent test data
4. **Descriptive Names**: Test names clearly describe the scenario being tested
5. **Edge Cases**: Tests cover both happy path and error conditions

## Coverage Statistics

- **11 test files**: Comprehensive coverage of all major components
- **100+ test cases**: Covering webhooks, verifiers, models, and integration scenarios
- **4 verifier specs**: All supported providers (Stripe, Square, PayPal, WebhookSite)
- **Complex scenarios**: Real-world use cases with multiple providers and actions

## Maintenance

When adding new features:

1. Add factory definitions if new models are created
2. Write request specs for new endpoints
3. Write verifier specs for new webhook providers
4. Write integration specs for complex multi-component features
5. Update this summary document

## Troubleshooting

### Database Connection Issues

Ensure PostgreSQL is running:

```bash
# Check if PostgreSQL is running
pg_isready

# Start PostgreSQL
brew services start postgresql  # macOS
sudo service postgresql start   # Linux
```

### Missing Dependencies

Install all gems:

```bash
bundle install
```

### Test Failures

1. Check database migrations are up to date
2. Verify action registry is cleared between tests
3. Check for any pending migrations in the dummy app

## Additional Resources

- [RSpec Documentation](https://rspec.info/)
- [RSpec Rails Documentation](https://rspec.info/features/6-0/rspec-rails/)
- [FactoryBot Documentation](https://github.com/thoughtbot/factory_bot)
- [Shoulda Matchers Documentation](https://github.com/thoughtbot/shoulda-matchers)
- [Captain Hook README](../README.md)
