# Detailed Changes: Before & After

This document shows the exact changes made to each test file.

## test/models/provider_test.rb

### Setup Method

**BEFORE:**
```ruby
setup do
  @provider = CaptainHook::Provider.create!(
    name: "test_provider",
    display_name: "Test Provider",
    verifier_class: "CaptainHook::Verifiers::Base",
    signing_secret: "test_secret",
    active: true
  )
end
```

**AFTER:**
```ruby
setup do
  # Database only manages: name, token, active, rate_limit_requests, rate_limit_period
  @provider = CaptainHook::Provider.create!(
    name: "test_provider",
    active: true
  )
  
  # Create a test provider YAML file for registry integration
  create_test_provider_yaml("test_provider")
end

teardown do
  # Clean up test YAML file
  cleanup_test_provider_yaml("test_provider")
end

private

def create_test_provider_yaml(name)
  provider_dir = Rails.root.join("captain_hook", name)
  FileUtils.mkdir_p(provider_dir)
  
  File.write(provider_dir.join("#{name}.yml"), <<~YAML)
    name: #{name}
    display_name: Test Provider
    description: A test provider
    verifier_file: #{name}.rb
    signing_secret: ENV[TEST_PROVIDER_WEBHOOK_SECRET]
    active: true
  YAML
  
  # Create minimal verifier file
  File.write(provider_dir.join("#{name}.rb"), <<~RUBY)
    class TestProviderVerifier
      include CaptainHook::VerifierHelpers
      def verify(request); true; end
    end
  RUBY
end

def cleanup_test_provider_yaml(name)
  provider_dir = Rails.root.join("captain_hook", name)
  FileUtils.rm_rf(provider_dir) if provider_dir.exist?
end
```

### Removed Tests

```ruby
# REMOVED: verifier_class validation
test "requires verifier_class" do
  provider = CaptainHook::Provider.new(name: "unique_test", verifier_class: nil)
  assert_not provider.valid?
  assert_includes provider.errors[:verifier_class], "can't be blank"
end

# REMOVED: timestamp_tolerance_seconds validation
test "validates timestamp_tolerance_seconds is positive integer" do
  @provider.timestamp_tolerance_seconds = -1
  refute @provider.valid?
  # ...
end

# REMOVED: max_payload_size_bytes validation
test "validates max_payload_size_bytes is positive integer" do
  @provider.max_payload_size_bytes = -1
  refute @provider.valid?
  # ...
end

# REMOVED: signing_secret tests
test "signing_secret returns database value" do
  assert_equal "test_secret", @provider.signing_secret
end

# REMOVED: encryption tests
test "signing_secret is encrypted" do
  @provider.signing_secret = "super_secret"
  @provider.save!
  # ...
end

# REMOVED: verifier instance tests
test "verifier returns verifier instance" do
  verifier = @provider.verifier
  assert_kind_of CaptainHook::Verifiers::Base, verifier
end

# REMOVED: feature check methods
test "payload_size_limit_enabled? returns true when configured" do
  @provider.max_payload_size_bytes = 1024
  assert @provider.payload_size_limit_enabled?
end

test "timestamp_validation_enabled? returns true when configured" do
  @provider.timestamp_tolerance_seconds = 300
  assert @provider.timestamp_validation_enabled?
end
```

### Updated Tests

**Provider Creation Tests:**
```ruby
# BEFORE
test "name must be lowercase alphanumeric with underscores" do
  provider = CaptainHook::Provider.new(name: "Test-Provider!", verifier_class: "Test")
  assert provider.save
  assert_equal "test_provider_", provider.name
end

# AFTER
test "name must be lowercase alphanumeric with underscores" do
  provider = CaptainHook::Provider.new(name: "Test-Provider!")
  assert provider.save
  assert_equal "test_provider_", provider.name
end
```

```ruby
# BEFORE
test "active scope returns only active providers" do
  inactive = CaptainHook::Provider.create!(name: "inactive", verifier_class: "Test", active: false)
  # ...
end

# AFTER
test "active scope returns only active providers" do
  inactive = CaptainHook::Provider.create!(name: "inactive", active: false)
  # ...
end
```

---

## test/services/provider_sync_test.rb

### Setup Method

**BEFORE:**
```ruby
@provider_definitions = [
  {
    "name" => "test_provider",
    "display_name" => "Test Provider",
    "description" => "A test provider",
    "verifier_class" => "CaptainHook::Verifiers::Base",
    "active" => true,
    "signing_secret" => "test_secret",
    "timestamp_tolerance_seconds" => 300,
    "rate_limit_requests" => 100,
    "rate_limit_period" => 60,
    "source_file" => "/test/providers/test_provider.yml",
    "source" => "test"
  }
]
```

**AFTER:**
```ruby
# Provider definitions from registry (YAML files)
# Only DB-managed fields should be synced: active, rate_limit_requests, rate_limit_period
@provider_definitions = [
  {
    "name" => "test_provider",
    "display_name" => "Test Provider",        # Registry only - not synced
    "description" => "A test provider",       # Registry only - not synced
    "verifier_class" => "CaptainHook::Verifiers::Base",  # Registry only
    "verifier_file" => "test_provider.rb",    # Registry only
    "active" => true,                         # Synced to DB
    "signing_secret" => "ENV[TEST_SECRET]",   # Registry only - not synced
    "timestamp_tolerance_seconds" => 300,     # From global config
    "rate_limit_requests" => 100,             # Synced to DB
    "rate_limit_period" => 60,                # Synced to DB
    "source_file" => "/test/providers/test_provider.yml",
    "source" => "test"
  }
]
```

### Main Test Changes

**BEFORE:**
```ruby
test "creates new provider from definition" do
  sync = ProviderSync.new(@provider_definitions)
  results = sync.call

  provider = CaptainHook::Provider.find_by(name: "test_provider")
  assert_equal "Test Provider", provider.display_name
  assert_equal "A test provider", provider.description
  assert_equal "CaptainHook::Verifiers::Base", provider.verifier_class
  assert provider.active?
  assert_equal 300, provider.timestamp_tolerance_seconds
  assert_equal 100, provider.rate_limit_requests
  assert_equal 60, provider.rate_limit_period
end
```

**AFTER:**
```ruby
test "creates new provider from definition" do
  sync = ProviderSync.new(@provider_definitions)
  results = sync.call

  provider = CaptainHook::Provider.find_by(name: "test_provider")
  # Only DB fields are synced
  assert provider.active?
  assert_equal 100, provider.rate_limit_requests
  assert_equal 60, provider.rate_limit_period
  assert_not_nil provider.token  # Auto-generated
  
  # These fields are NOT in database anymore
  assert_nil provider.attributes["display_name"]
  assert_nil provider.attributes["description"]
  assert_nil provider.attributes["verifier_class"]
  assert_nil provider.attributes["signing_secret"]
  assert_nil provider.attributes["timestamp_tolerance_seconds"]
end
```

### Removed Tests

```ruby
# REMOVED: ENV variable resolution (now in ProviderConfig)
test "resolves ENV variable references in signing_secret" do
  ENV["TEST_WEBHOOK_SECRET"] = "secret_from_env"
  # ...
end

# REMOVED: verifier_class validation
test "valid_provider_definition checks for verifier_class presence" do
  sync = ProviderSync.new([])
  result = sync.send(:valid_provider_definition?, { "name" => "test" })
  refute result, "Should be invalid without verifier_class"
end

# REMOVED: signing_secret syncing tests
test "only updates signing_secret when value changes" do
  # ...
end
```

### New Tests Added

```ruby
# NEW: Verify removed columns don't exist
test "does not sync registry-only fields to database" do
  sync = ProviderSync.new(@provider_definitions)
  results = sync.call

  provider = CaptainHook::Provider.find_by(name: "test_provider")
  
  # Verify these columns don't exist in database
  refute provider.respond_to?(:display_name)
  refute provider.respond_to?(:description)
  refute provider.respond_to?(:verifier_class)
  refute provider.respond_to?(:signing_secret)
  refute provider.respond_to?(:timestamp_tolerance_seconds)
  refute provider.respond_to?(:max_payload_size_bytes)
end

# NEW: Verify only DB fields are updated
test "only updates database-managed fields" do
  provider = CaptainHook::Provider.create!(
    name: "test_provider",
    active: false
  )

  definitions = [
    {
      "name" => "test_provider",
      "active" => true,
      "rate_limit_requests" => 500,
      "rate_limit_period" => 300,
      "display_name" => "Should Not Sync",
      "description" => "Should Not Sync",
      "signing_secret" => "Should Not Sync",
      "source" => "test"
    }
  ]

  sync = ProviderSync.new(definitions)
  sync.call

  provider.reload
  # These should update
  assert provider.active?
  assert_equal 500, provider.rate_limit_requests
  assert_equal 300, provider.rate_limit_period
  
  # These columns don't exist in database anymore
  refute provider.respond_to?(:display_name)
  refute provider.respond_to?(:description)
  refute provider.respond_to?(:signing_secret)
end
```

---

## test/provider_config_test.rb

### Setup Method

**BEFORE:**
```ruby
@config_data = {
  "name" => "stripe",
  "display_name" => "Stripe",
  "verifier_class" => "CaptainHook::Verifiers::Stripe",
  "signing_secret" => "whsec_test123",
  "timestamp_tolerance_seconds" => 300,  # Hardcoded in test data
  "rate_limit_requests" => 100,
  "rate_limit_period" => 60,
  "active" => true
}
```

**AFTER:**
```ruby
@config_data = {
  "name" => "stripe",
  "display_name" => "Stripe",
  "verifier_class" => "CaptainHook::Verifiers::Stripe",
  "signing_secret" => "whsec_test123",
  # timestamp_tolerance_seconds removed - comes from GlobalConfigLoader
  "rate_limit_requests" => 100,
  "rate_limit_period" => 60,
  "active" => true
}
```

### Updated Tests

**BEFORE:**
```ruby
def test_defaults_timestamp_tolerance_to_300
  config = ProviderConfig.new("name" => "test")
  assert_equal 300, config.timestamp_tolerance_seconds
end
```

**AFTER:**
```ruby
def test_loads_timestamp_tolerance_from_global_config
  # GlobalConfigLoader should provide default of 300
  config = ProviderConfig.new("name" => "test")
  assert_equal 300, config.timestamp_tolerance_seconds
end

def test_loads_max_payload_size_from_global_config
  # GlobalConfigLoader should provide default of 1MB
  config = ProviderConfig.new("name" => "test")
  assert_equal 1_048_576, config.max_payload_size_bytes
end

def test_allows_custom_max_payload_size
  config = ProviderConfig.new("name" => "test", "max_payload_size_bytes" => 2_097_152)
  assert_equal 2_097_152, config.max_payload_size_bytes
end
```

---

## Summary of Changes

### Deleted Columns
- `display_name` → YAML
- `description` → YAML
- `signing_secret` → YAML (with ENV ref)
- `verifier_class` → YAML
- `verifier_file` → YAML
- `timestamp_tolerance_seconds` → Global config
- `max_payload_size_bytes` → Global config
- `metadata` → Removed entirely

### Kept Columns (Database)
- `name` ✅
- `token` ✅ (auto-generated)
- `active` ✅
- `rate_limit_requests` ✅
- `rate_limit_period` ✅
- `created_at`, `updated_at` ✅

### Test File Statistics

**provider_test.rb:**
- Lines removed: ~150
- Lines added: ~40
- Tests removed: 15
- Tests updated: 12
- Tests kept: 20

**provider_sync_test.rb:**
- Lines removed: ~120
- Lines added: ~80
- Tests removed: 5
- Tests added: 2
- Tests updated: 8

**provider_config_test.rb:**
- Lines removed: ~10
- Lines added: ~15
- Tests removed: 1
- Tests updated: 3
- Tests added: 2
