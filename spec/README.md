# RSpec Test Suite

This directory contains the comprehensive RSpec test suite for CaptainHook, a Rails engine for managing webhooks.

## Overview

The test suite uses RSpec for behavior-driven testing, with FactoryBot for test data creation and WebMock for HTTP stubbing. Tests are organized by type (models, requests, integration) and cover all major functionality of the CaptainHook engine.

## Test Structure

```
spec/
├── README.md                              # This file
├── spec_helper.rb                         # RSpec configuration
├── rails_helper.rb                        # Rails-specific test setup
├── factories/                             # FactoryBot factories
│   └── captain_hook_factories.rb          # Factories for all models
├── integration/                           # Integration tests
│   └── complex_webhook_scenarios_spec.rb  # End-to-end webhook flows
├── lib/                                   # Library/service tests
│   └── captain_hook/
│       └── action_registry_spec.rb        # ActionRegistry tests
├── models/                                # Model tests
│   └── provider_spec.rb                   # Provider model tests
└── requests/                              # Request/controller tests
    └── incoming_webhooks_spec.rb          # Webhook endpoint tests
```

## Running Tests

### Run All Tests

```bash
bundle exec rspec
```

### Run Specific Test Files

```bash
# Model tests
bundle exec rspec spec/models/provider_spec.rb

# Request tests
bundle exec rspec spec/requests/incoming_webhooks_spec.rb

# Integration tests
bundle exec rspec spec/integration/complex_webhook_scenarios_spec.rb
```

### Run Tests by Type

```bash
# All model tests
bundle exec rspec spec/models

# All request tests
bundle exec rspec spec/requests

# All integration tests
bundle exec rspec spec/integration
```

### Run Specific Examples

```bash
# Run examples matching a description
bundle exec rspec spec/models/provider_spec.rb -e "validates presence"

# Run a specific line
bundle exec rspec spec/models/provider_spec.rb:25

# Run focused tests (marked with :focus)
bundle exec rspec --tag focus
```

### Run with Options

```bash
# Run with detailed output
bundle exec rspec --format documentation

# Run only failed tests from last run
bundle exec rspec --only-failures

# Run next failure
bundle exec rspec --next-failure

# Run with coverage (if SimpleCov configured)
COVERAGE=true bundle exec rspec
```

## Test Categories

### Model Tests (`spec/models/`)

Test ActiveRecord models, validations, associations, scopes, and callbacks.

**Example: Provider Model Tests** ([provider_spec.rb](models/provider_spec.rb))

```ruby
RSpec.describe CaptainHook::Provider do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:verifier_class) }
    
    it "validates uniqueness of name" do
      create(:captain_hook_provider, name: "stripe")
      duplicate = build(:captain_hook_provider, name: "stripe")
      expect(duplicate).not_to be_valid
    end
  end
  
  describe "associations" do
    it { is_expected.to have_many(:incoming_events) }
    it { is_expected.to have_many(:actions) }
  end
  
  describe "scopes" do
    it "returns only active providers" do
      active = create(:captain_hook_provider, active: true)
      inactive = create(:captain_hook_provider, active: false)
      expect(Provider.active).to include(active)
      expect(Provider.active).not_to include(inactive)
    end
  end
end
```

**Coverage**:
- ✅ Provider validations (presence, uniqueness, format)
- ✅ Provider associations (incoming_events, actions)
- ✅ Provider scopes (active, inactive)
- ✅ Provider callbacks (name normalization, token generation)
- ✅ Provider methods (webhook_url, verifier loading)

### Request Tests (`spec/requests/`)

Test HTTP endpoints, authentication, and API responses.

**Example: Webhook Endpoint Tests** ([incoming_webhooks_spec.rb](requests/incoming_webhooks_spec.rb))

```ruby
RSpec.describe "Incoming Webhooks", type: :request do
  let(:provider) { create(:captain_hook_provider) }
  let(:payload) { { id: "evt_123", type: "test.event" }.to_json }
  
  describe "POST /captain_hook/:provider/:token" do
    it "accepts valid webhook with correct signature" do
      signature = generate_signature(payload, provider.signing_secret)
      
      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload,
           headers: { "X-Signature" => signature }
      
      expect(response).to have_http_status(:created)
      expect(IncomingEvent.count).to eq(1)
    end
    
    it "rejects webhook with invalid signature" do
      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload,
           headers: { "X-Signature" => "invalid" }
      
      expect(response).to have_http_status(:unauthorized)
      expect(IncomingEvent.count).to eq(0)
    end
    
    it "rejects webhook when provider is inactive" do
      provider.update!(active: false)
      
      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload
      
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

**Coverage**:
- ✅ Successful webhook processing (201 Created)
- ✅ Provider validation (404, 403)
- ✅ Token verification (401)
- ✅ Rate limiting (429)
- ✅ Payload size validation (413)
- ✅ Signature verification (401)
- ✅ JSON parsing (400)
- ✅ Timestamp validation (400)
- ✅ Duplicate detection (200)

### Integration Tests (`spec/integration/`)

Test complete end-to-end workflows and complex scenarios.

**Example: Multi-Provider Webhook Scenarios** ([complex_webhook_scenarios_spec.rb](integration/complex_webhook_scenarios_spec.rb))

```ruby
RSpec.describe "Complex Webhook Integration Scenarios" do
  describe "Multiple providers with same verifier type" do
    let(:primary_provider) { create(:captain_hook_provider, name: "stripe_primary") }
    let(:secondary_provider) { create(:captain_hook_provider, name: "stripe_secondary") }
    
    it "verifies signatures with correct provider secret" do
      # Send webhook to primary provider
      primary_payload = { id: "evt_primary" }.to_json
      primary_signature = generate_signature(primary_payload, primary_provider.signing_secret)
      
      post "/captain_hook/stripe_primary/#{primary_provider.token}",
           params: primary_payload,
           headers: { "Stripe-Signature" => primary_signature }
      
      expect(response).to have_http_status(:created)
      
      # Same payload to secondary with different secret should fail
      post "/captain_hook/stripe_secondary/#{secondary_provider.token}",
           params: primary_payload,
           headers: { "Stripe-Signature" => primary_signature }
      
      expect(response).to have_http_status(:unauthorized)
    end
  end
  
  describe "Action execution outcomes" do
    it "marks action as completed on success" do
      # Test successful action execution
      # Verify status transitions: pending → processing → success
    end
    
    it "marks action as failed after errors" do
      # Test failed action execution
      # Verify status transitions: pending → processing → failed
      # Verify retry scheduling
    end
  end
end
```

**Coverage**:
- ✅ Third-party gem and app sharing provider
- ✅ Separate webhook providers for gem and app
- ✅ Action execution outcomes (success, failure, retries)
- ✅ Async and sync action execution
- ✅ Multiple providers with same verifier type
- ✅ Priority-based action execution order
- ✅ Event history separation per provider

### Library/Service Tests (`spec/lib/`)

Test service objects, utilities, and non-model classes.

**Example: ActionRegistry Tests** ([action_registry_spec.rb](lib/captain_hook/action_registry_spec.rb))

```ruby
RSpec.describe CaptainHook::ActionRegistry do
  let(:registry) { described_class.new }
  
  describe "#register" do
    it "registers an action with required parameters" do
      registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "PaymentAction",
        priority: 100
      )
      
      actions = registry.find_actions(
        provider: "stripe",
        event_type: "payment.succeeded"
      )
      
      expect(actions).not_to be_empty
      expect(actions.first[:action_class]).to eq("PaymentAction")
    end
  end
  
  describe "#find_actions" do
    it "finds actions matching exact event type" do
      registry.register(
        provider: "stripe",
        event_type: "payment.succeeded",
        action_class: "PaymentAction"
      )
      
      actions = registry.find_actions(
        provider: "stripe",
        event_type: "payment.succeeded"
      )
      
      expect(actions.length).to eq(1)
    end
    
    it "finds actions matching wildcard patterns" do
      registry.register(
        provider: "stripe",
        event_type: "payment.*",
        action_class: "AllPaymentsAction"
      )
      
      actions = registry.find_actions(
        provider: "stripe",
        event_type: "payment.succeeded"
      )
      
      expect(actions).to include(
        hash_including(action_class: "AllPaymentsAction")
      )
    end
  end
end
```

**Coverage**:
- ✅ ActionRegistry registration and lookup
- ✅ Service objects (ProviderDiscovery, ActionDiscovery, etc.)
- ✅ Configuration classes (ProviderConfig, Configuration)
- ✅ Verifier classes (Base, Stripe)
- ✅ Helper modules (VerifierHelpers)

## Factories

### Available Factories

FactoryBot factories for creating test data ([factories/captain_hook_factories.rb](factories/captain_hook_factories.rb)).

#### Provider Factory

```ruby
# Basic provider
provider = create(:captain_hook_provider)

# Stripe provider
stripe = create(:captain_hook_provider, :stripe)

# Inactive provider
inactive = create(:captain_hook_provider, :inactive)

# With rate limiting
limited = create(:captain_hook_provider, :with_rate_limiting)

# Without rate limiting
unlimited = create(:captain_hook_provider, :without_rate_limiting)

# With payload limit
small_payloads = create(:captain_hook_provider, :with_payload_limit)

# Custom attributes
custom = create(:captain_hook_provider,
  name: "github",
  display_name: "GitHub",
  signing_secret: "custom_secret"
)
```

#### IncomingEvent Factory

```ruby
# Basic event
event = create(:captain_hook_incoming_event)

# Duplicate event
duplicate = create(:captain_hook_incoming_event, :duplicate)

# Processing event
processing = create(:captain_hook_incoming_event, :processing)

# Completed event
completed = create(:captain_hook_incoming_event, :completed)

# Failed event
failed = create(:captain_hook_incoming_event, :failed)

# Custom event
custom = create(:captain_hook_incoming_event,
  provider: "stripe",
  external_id: "evt_123",
  event_type: "payment_intent.succeeded",
  payload: { amount: 1000 }
)
```

#### Action Factory

```ruby
# Basic action
action = create(:captain_hook_action)

# Inactive action
inactive = create(:captain_hook_action, :inactive)

# Sync action (executes immediately)
sync = create(:captain_hook_action, :sync)

# High priority action
high = create(:captain_hook_action, :high_priority)

# Low priority action
low = create(:captain_hook_action, :low_priority)

# Custom action
custom = create(:captain_hook_action,
  provider: "stripe",
  event_type: "payment.*",
  action_class: "PaymentAction",
  priority: 100,
  async: true
)
```

#### IncomingEventAction Factory

```ruby
# Basic incoming event action
iea = create(:captain_hook_incoming_event_action)

# Processing
processing = create(:captain_hook_incoming_event_action, :processing)

# Completed
completed = create(:captain_hook_incoming_event_action, :completed)

# Failed
failed = create(:captain_hook_incoming_event_action, :failed)

# With custom attributes
custom = create(:captain_hook_incoming_event_action,
  incoming_event: event,
  action: action,
  status: :pending,
  attempt: 0
)
```

### Factory Traits

Traits provide pre-configured variations of factories:

**Provider Traits**:
- `:inactive` - Sets `active: false`
- `:stripe` - Configures as Stripe provider
- `:with_rate_limiting` - Enables rate limiting (10 req/60s)
- `:without_rate_limiting` - Disables rate limiting
- `:with_payload_limit` - Sets small payload limit (1KB)
- `:without_payload_limit` - No payload size restriction

**IncomingEvent Traits**:
- `:duplicate` - Sets `dedup_state: :duplicate`
- `:processing` - Sets `status: :processing`
- `:completed` - Sets `status: :completed`
- `:failed` - Sets `status: :failed`

**Action Traits**:
- `:inactive` - Sets `active: false`
- `:sync` - Sets `async: false` (immediate execution)
- `:high_priority` - Sets `priority: 100`
- `:low_priority` - Sets `priority: 10`

**IncomingEventAction Traits**:
- `:processing` - Sets `status: :processing`, includes timestamp
- `:completed` - Sets `status: :success`, includes timestamp
- `:failed` - Sets `status: :failed`, includes error message

## Test Helpers

### Signature Generation

Helper for generating valid webhook signatures:

```ruby
def generate_stripe_signature(payload, secret)
  timestamp = Time.current.to_i
  signed_payload = "#{timestamp}.#{payload}"
  signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
  "t=#{timestamp},v1=#{signature}"
end

# Usage in tests
signature = generate_stripe_signature(payload, provider.signing_secret)
headers = { "Stripe-Signature" => signature }
```

### WebMock Stubs

Stub external API calls:

```ruby
# Stub Stripe API
stub_request(:post, "https://api.stripe.com/v1/payment_intents")
  .to_return(status: 200, body: { id: "pi_123" }.to_json)

# Verify request was made
expect(WebMock).to have_requested(:post, "https://api.stripe.com/v1/payment_intents")
```

### Time Helpers

Manipulate time in tests:

```ruby
# Travel to specific time
travel_to Time.zone.parse("2024-01-15 12:00:00") do
  # Test code here
end

# Travel forward
travel 5.minutes do
  # Test code here
end

# Freeze time
freeze_time do
  # Time doesn't advance
end
```

## Test Configuration

### RSpec Configuration ([spec_helper.rb](spec_helper.rb))

```ruby
RSpec.configure do |config|
  # Run specs in random order
  config.order = :random
  
  # Focus on specific tests
  config.filter_run_when_matching :focus
  
  # Persist example status
  config.example_status_persistence_file_path = "spec/examples.txt"
  
  # Verify partial doubles
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
```

### Rails Helper ([rails_helper.rb](rails_helper.rb))

```ruby
RSpec.configure do |config|
  # Use transactional fixtures
  config.use_transactional_fixtures = true
  
  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods
  
  # Include request helpers
  config.include CaptainHook::Engine.routes.url_helpers, type: :request
end
```

## Testing Best Practices

### 1. Use Descriptive Test Names

```ruby
# ✅ GOOD: Clear what's being tested
it "rejects webhook when signature is invalid" do
  # ...
end

# ❌ BAD: Vague description
it "works" do
  # ...
end
```

### 2. Follow Arrange-Act-Assert Pattern

```ruby
it "creates incoming event with correct attributes" do
  # Arrange - Set up test data
  provider = create(:captain_hook_provider)
  payload = { id: "evt_123" }.to_json
  
  # Act - Perform the action
  post webhook_path(provider), params: payload
  
  # Assert - Verify results
  event = IncomingEvent.last
  expect(event.external_id).to eq("evt_123")
  expect(event.provider).to eq(provider.name)
end
```

### 3. Test One Thing Per Example

```ruby
# ✅ GOOD: Tests one behavior
it "creates an incoming event" do
  expect { post_webhook }.to change(IncomingEvent, :count).by(1)
end

it "returns 201 Created status" do
  post_webhook
  expect(response).to have_http_status(:created)
end

# ❌ BAD: Tests multiple things
it "creates event and returns success" do
  expect { post_webhook }.to change(IncomingEvent, :count).by(1)
  expect(response).to have_http_status(:created)
  expect(response.body).to include("id")
end
```

### 4. Use Factories, Not Fixtures

```ruby
# ✅ GOOD: Flexible, clear intent
provider = create(:captain_hook_provider, name: "stripe")

# ❌ BAD: Brittle, unclear what data looks like
provider = providers(:stripe)  # fixture
```

### 5. Use Shared Examples for Common Behavior

```ruby
shared_examples "a webhook endpoint" do |provider_name|
  it "accepts valid webhooks" do
    # Test implementation
  end
  
  it "rejects invalid signatures" do
    # Test implementation
  end
end

describe "Stripe webhooks" do
  it_behaves_like "a webhook endpoint", "stripe"
end

describe "GitHub webhooks" do
  it_behaves_like "a webhook endpoint", "github"
end
```

### 6. Use Let for Test Data

```ruby
# ✅ GOOD: Lazy evaluation, clear dependencies
let(:provider) { create(:captain_hook_provider) }
let(:event) { create(:captain_hook_incoming_event, provider: provider.name) }

# ❌ BAD: Eager evaluation, unclear dependencies
before do
  @provider = create(:captain_hook_provider)
  @event = create(:captain_hook_incoming_event, provider: @provider.name)
end
```

### 7. Test Both Happy Path and Edge Cases

```ruby
describe "webhook processing" do
  context "with valid webhook" do
    it "creates incoming event" do
      # Happy path test
    end
  end
  
  context "with invalid signature" do
    it "rejects webhook" do
      # Edge case test
    end
  end
  
  context "with expired timestamp" do
    it "rejects webhook" do
      # Edge case test
    end
  end
  
  context "when provider is inactive" do
    it "rejects webhook" do
      # Edge case test
    end
  end
end
```

### 8. Use Context Blocks for Grouping

```ruby
describe "#webhook_action" do
  context "when action succeeds" do
    it "marks event action as success" do
      # Test success case
    end
  end
  
  context "when action fails" do
    it "marks event action as failed" do
      # Test failure case
    end
    
    it "schedules retry" do
      # Test retry scheduling
    end
  end
end
```

## Common Test Patterns

### Testing Validations

```ruby
describe "validations" do
  subject { build(:captain_hook_provider) }
  
  # Using shoulda-matchers
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_uniqueness_of(:name) }
  
  # Custom validation tests
  it "validates name format" do
    provider = build(:captain_hook_provider, name: "Invalid Name!")
    expect(provider).not_to be_valid
    expect(provider.errors[:name]).to be_present
  end
end
```

### Testing Associations

```ruby
describe "associations" do
  it { is_expected.to have_many(:incoming_events) }
  it { is_expected.to have_many(:actions) }
  it { is_expected.to belong_to(:provider) }
end
```

### Testing Scopes

```ruby
describe "scopes" do
  let!(:active_provider) { create(:captain_hook_provider, active: true) }
  let!(:inactive_provider) { create(:captain_hook_provider, active: false) }
  
  describe ".active" do
    it "returns only active providers" do
      expect(Provider.active).to include(active_provider)
      expect(Provider.active).not_to include(inactive_provider)
    end
  end
end
```

### Testing Callbacks

```ruby
describe "callbacks" do
  describe "before_validation" do
    it "normalizes name" do
      provider = build(:captain_hook_provider, name: "Test-Provider")
      provider.valid?
      expect(provider.name).to eq("test_provider")
    end
  end
  
  describe "before_create" do
    it "generates token" do
      provider = build(:captain_hook_provider, token: nil)
      provider.save!
      expect(provider.token).to be_present
    end
  end
end
```

### Testing API Requests

```ruby
describe "POST /captain_hook/:provider/:token" do
  let(:provider) { create(:captain_hook_provider) }
  let(:payload) { { id: "evt_123" }.to_json }
  let(:headers) { { "Content-Type" => "application/json" } }
  
  def post_webhook(params: payload, headers: headers)
    post "/captain_hook/#{provider.name}/#{provider.token}",
         params: params,
         headers: headers
  end
  
  it "returns 201 Created" do
    post_webhook
    expect(response).to have_http_status(:created)
  end
  
  it "creates incoming event" do
    expect { post_webhook }.to change(IncomingEvent, :count).by(1)
  end
  
  it "returns event data" do
    post_webhook
    json = JSON.parse(response.body)
    expect(json).to include("id", "status")
  end
end
```

### Testing Background Jobs

```ruby
describe "async action execution" do
  it "enqueues background job" do
    expect {
      post_webhook
    }.to have_enqueued_job(IncomingActionJob)
  end
  
  it "processes job successfully" do
    perform_enqueued_jobs do
      post_webhook
    end
    
    event_action = IncomingEventAction.last
    expect(event_action.status).to eq("success")
  end
end
```

## Continuous Integration

### Running Tests in CI

Example GitHub Actions workflow:

```yaml
name: RSpec Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true
      
      - name: Set up database
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test
        run: |
          bundle exec rails db:create
          bundle exec rails db:migrate
      
      - name: Run tests
        run: bundle exec rspec
```

## Test Coverage

### Viewing Coverage

If SimpleCov is configured:

```bash
# Run tests with coverage
COVERAGE=true bundle exec rspec

# View coverage report
open coverage/index.html
```

### Coverage Goals

- **Overall**: Aim for 90%+ coverage
- **Models**: Should be 100% covered
- **Controllers**: Core paths covered
- **Services**: Business logic fully tested
- **Integration**: Key workflows covered

## Troubleshooting

### Common Issues

**Database not found**:
```bash
bundle exec rails db:create RAILS_ENV=test
bundle exec rails db:migrate RAILS_ENV=test
```

**Factory errors**:
```ruby
# Check factory is valid
FactoryBot.lint
```

**Flaky tests** (tests that randomly fail):
```bash
# Run multiple times to identify
bundle exec rspec --seed 12345  # Use specific seed

# Check for:
# - Time-dependent logic
# - Shared state between tests
# - Race conditions in async tests
```

**Slow tests**:
```bash
# Profile slow tests
bundle exec rspec --profile 10

# Common causes:
# - Creating too many records
# - Not using database transactions
# - External API calls not stubbed
```

## Contributing to Tests

When adding new features:

1. **Write tests first** (TDD approach)
2. **Add factories** for new models
3. **Test happy path and edge cases**
4. **Update this README** if adding new test patterns
5. **Ensure all tests pass** before submitting PR

## Resources

- [RSpec Documentation](https://rspec.info/)
- [FactoryBot Documentation](https://github.com/thoughtbot/factory_bot)
- [Shoulda Matchers](https://github.com/thoughtbot/shoulda-matchers)
- [WebMock Documentation](https://github.com/bblimke/webmock)
- [Testing Rails Applications](https://guides.rubyonrails.org/testing.html)

## See Also

- [Test Suite Summary](TEST_SUITE_SUMMARY.md) - Overview of test coverage
- [TECHNICAL_PROCESS.md](../TECHNICAL_PROCESS.md) - System architecture documentation
- [Action Discovery](../docs/ACTION_DISCOVERY.md) - Action discovery process
- [Provider Discovery](../docs/PROVIDER_DISCOVERY.md) - Provider discovery process
