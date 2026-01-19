# RSpec Test Suite

This directory contains the comprehensive RSpec test suite for CaptainHook, a Rails engine for managing webhooks.

## Overview

The RSpec test suite provides extensive coverage of webhook reception, signature verification, action execution, and complex integration scenarios. It complements the existing Minitest suite and provides BDD-style specifications.

## Test Structure

```
spec/
├── factories/                      # FactoryBot factories for test data
│   └── captain_hook_factories.rb   # Provider, event, and action factories
├── integration/                     # Integration tests for complex scenarios
│   └── complex_webhook_scenarios_spec.rb
├── lib/captain_hook/
│   ├── verifiers/                    # Verifier specs (Stripe, Square, etc.)
│   │   ├── stripe_spec.rb
│   │   └── square_spec.rb
│   └── action_registry_spec.rb     # Action registry specs
├── models/                          # Model specs
│   └── provider_spec.rb            # Provider model specs
├── requests/                        # Request specs
│   └── incoming_webhooks_spec.rb   # Webhook reception specs
├── support/                         # Test support files
├── rails_helper.rb                 # Rails-specific test configuration
└── spec_helper.rb                  # RSpec configuration
```

## Running Tests

### Prerequisites

1. **PostgreSQL Database**: Tests require a PostgreSQL database to be running
2. **Environment Setup**: Configure database connection in `test/dummy/config/database.yml`
3. **Dependencies**: Run `bundle install` to install RSpec and related gems

### Running All Specs

```bash
bundle exec rspec
```

### Running Specific Test Files

```bash
# Run all integration tests
bundle exec rspec spec/integration

# Run incoming webhook tests
bundle exec rspec spec/requests/incoming_webhooks_spec.rb

# Run verifier tests
bundle exec rspec spec/lib/captain_hook/verifiers

# Run a specific test
bundle exec rspec spec/models/provider_spec.rb:123
```

### Running Tests with Rake

```bash
# Run RSpec tests
bundle exec rake spec

# Or use the alias
bundle exec rake rspec
```

### Continuous Integration

The CI workflow runs RSpec tests automatically:

```yaml
- name: Run RSpec tests
  run: bundle exec rspec
```

## Test Coverage

### Incoming Webhook Scenarios

- ✅ Successful webhook reception and event creation
- ✅ Action job enqueueing (async and sync)
- ✅ Idempotency and duplicate detection
- ✅ Authentication (token validation, provider activation)
- ✅ Signature verification (valid/invalid/missing)
- ✅ Timestamp validation (expired/recent/future)
- ✅ Rate limiting (within/exceeding limits)
- ✅ Payload size limits
- ✅ Invalid JSON handling
- ✅ Multiple provider support

### Verifier Scenarios

#### Stripe Verifier
- ✅ Valid signature verification (v0, v1, multiple versions)
- ✅ Invalid signature rejection
- ✅ Timestamp validation with tolerance windows
- ✅ Event ID and type extraction
- ✅ Timestamp extraction from headers

#### Square Verifier
- ✅ HMAC-SHA256 Base64 signature verification
- ✅ Notification URL validation
- ✅ Event ID and type extraction

### Integration Scenarios

#### Third-Party Gem + Rails App (Same Webhook)
- ✅ Multiple actions for same event type
- ✅ Shared signing secret usage
- ✅ Action execution in priority order
- ✅ Both gem and app actions execute correctly

#### Separate Webhook Providers
- ✅ Independent webhook routing based on provider
- ✅ Separate event histories per provider
- ✅ Correct action association per provider

#### Action Execution Outcomes
- ✅ Successful action completion
- ✅ Failed action with error messages
- ✅ Retry logic and exponential backoff

#### Async vs Sync Execution
- ✅ Async actions enqueued as background jobs
- ✅ Sync actions executed immediately
- ✅ Execution status tracking

#### Multiple Providers with Same Verifier
- ✅ Different signing secrets per provider instance
- ✅ Signature verification with correct provider secret
- ✅ Unique webhook URLs per provider

### Model Specs

#### Provider Model
- ✅ Validations (presence, uniqueness, format, numericality)
- ✅ Callbacks (name normalization, token generation)
- ✅ Associations (incoming_events, actions)
- ✅ Scopes (active, inactive, by_name)
- ✅ Webhook URL generation
- ✅ Rate limiting checks
- ✅ Payload size limit checks
- ✅ Timestamp validation checks
- ✅ Signing secret encryption
- ✅ Environment variable override for secrets
- ✅ Verifier instantiation
- ✅ Activation/deactivation

### Action Registry Specs
- ✅ Action registration
- ✅ Multiple actions per event
- ✅ Default parameter values
- ✅ Action lookup by provider and event type
- ✅ Wildcard event type matching
- ✅ Priority-based ordering
- ✅ Thread safety
- ✅ Clear functionality

## Dependencies

The RSpec test suite uses these gems:

- **rspec-rails**: Rails-specific RSpec integration
- **factory_bot_rails**: Test data generation
- **faker**: Realistic fake data generation
- **shoulda-matchers**: RSpec matchers for common Rails validations
- **webmock**: HTTP request stubbing for testing external API calls

## Configuration

### Rails Helper

`spec/rails_helper.rb` configures:
- Rails test environment
- Database transactions for test isolation
- FactoryBot integration
- Shoulda Matchers configuration
- WebMock network request stubbing
- Action registry cleanup between tests

### Spec Helper

`spec/spec_helper.rb` configures:
- RSpec expectations and mocks
- Test output formatting
- Random test ordering
- Example status persistence

## Best Practices

### 1. Test Isolation

Each test runs in a database transaction that's rolled back after completion:

```ruby
config.use_transactional_fixtures = true
```

The action registry is cleared before each test:

```ruby
config.before(:each) do
  CaptainHook.action_registry.clear!
end
```

### 2. Factory Usage

Use factories for consistent test data:

```ruby
# Create a provider
provider = create(:captain_hook_provider, :stripe)

# Build without saving
provider = build(:captain_hook_provider, :inactive)

# Use traits for variations
provider = create(:captain_hook_provider, :with_rate_limiting)
```

### 3. Request Specs

Test HTTP requests with proper headers and signatures:

```ruby
post "/captain_hook/#{provider.name}/#{provider.token}",
     params: payload,
     headers: {
       "Content-Type" => "application/json",
       "Stripe-Signature" => signature
     }

expect(response).to have_http_status(:created)
```

### 4. Integration Tests

Test complex scenarios that span multiple components:

```ruby
# Register multiple actions
CaptainHook.register_action(...)

# Send webhook
post "/captain_hook/..."

# Verify outcomes
expect(event.metadata["gem_action_executed"]).to be true
expect(event.metadata["app_action_executed"]).to be true
```

## Troubleshooting

### Database Connection Issues

If you see `ActiveRecord::ConnectionNotEstablished`, ensure PostgreSQL is running:

```bash
# Check if PostgreSQL is running
pg_isready

# Start PostgreSQL (macOS with Homebrew)
brew services start postgresql

# Start PostgreSQL (Linux)
sudo service postgresql start
```

### Missing Factories

If you see `FactoryBot::InvalidFactoryError`, ensure factories are loaded:

```ruby
# In rails_helper.rb
config.include FactoryBot::Syntax::Methods
```

### Action Registry Pollution

If tests fail due to action registry state, ensure cleanup:

```ruby
# In rails_helper.rb
config.before(:each) do
  CaptainHook.action_registry.clear!
end
```

## Contributing

When adding new features:

1. Write RSpec tests that cover the new functionality
2. Include both success and failure scenarios
3. Test edge cases and error conditions
4. Ensure tests are isolated and don't depend on test order
5. Use descriptive test names that explain the behavior being tested

## Additional Resources

- [RSpec Documentation](https://rspec.info/)
- [RSpec Rails Documentation](https://rspec.info/features/6-0/rspec-rails/)
- [FactoryBot Documentation](https://github.com/thoughtbot/factory_bot)
- [Shoulda Matchers Documentation](https://github.com/thoughtbot/shoulda-matchers)
- [WebMock Documentation](https://github.com/bblimke/webmock)
