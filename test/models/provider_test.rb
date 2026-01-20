# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ProviderModelTest < ActiveSupport::TestCase
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

    # === Validations ===

    test "valid provider" do
      assert @provider.valid?
    end

    test "requires name" do
      provider = CaptainHook::Provider.new
      refute provider.valid?
      assert_includes provider.errors[:name], "can't be blank"
    end

    test "requires unique name" do
      duplicate = CaptainHook::Provider.new(name: @provider.name)
      refute duplicate.valid?
      assert_includes duplicate.errors[:name], "has already been taken"
    end

    test "name must be lowercase alphanumeric with underscores" do
      # The normalize_name callback converts any invalid chars to underscores
      # So "Test-Provider!" becomes "test_provider_" which is valid
      # This test verifies that normalization happens
      provider = CaptainHook::Provider.new(name: "Test-Provider!")
      assert provider.save
      assert_equal "test_provider_", provider.name
    end

    test "normalizes name before validation" do
      provider = CaptainHook::Provider.create!(name: "Test-Provider-123")
      assert_equal "test_provider_123", provider.name
    end

    test "token must be unique" do
      provider1 = CaptainHook::Provider.create!(name: "provider1")
      provider2 = CaptainHook::Provider.new(name: "provider2", token: provider1.token)

      refute provider2.valid?
      assert_includes provider2.errors[:token], "has already been taken"
    end

    test "validates rate_limit_requests is positive integer" do
      @provider.rate_limit_requests = -1
      refute @provider.valid?

      @provider.rate_limit_requests = 0
      refute @provider.valid?

      @provider.rate_limit_requests = 100
      assert @provider.valid?
    end

    test "validates rate_limit_period is positive integer" do
      @provider.rate_limit_period = -1
      refute @provider.valid?

      @provider.rate_limit_period = 0
      refute @provider.valid?

      @provider.rate_limit_period = 60
      assert @provider.valid?
    end

    # === Callbacks ===

    test "generates token before validation if blank" do
      provider = CaptainHook::Provider.new(name: "new_provider")
      assert_nil provider.token

      provider.valid?
      assert_not_nil provider.token
      assert provider.token.length > 20
    end

    test "does not override existing token" do
      original_token = @provider.token
      @provider.name = "updated_name"
      @provider.save!

      assert_equal original_token, @provider.reload.token
    end

    # === Scopes ===

    test "active scope returns only active providers" do
      inactive = CaptainHook::Provider.create!(name: "inactive", active: false)

      active_providers = CaptainHook::Provider.active
      assert_includes active_providers, @provider
      refute_includes active_providers, inactive
    end

    test "inactive scope returns only inactive providers" do
      inactive = CaptainHook::Provider.create!(name: "inactive", active: false)

      inactive_providers = CaptainHook::Provider.inactive
      assert_includes inactive_providers, inactive
      refute_includes inactive_providers, @provider
    end

    test "by_name scope orders by name" do
      CaptainHook::Provider.create!(name: "z_provider")
      CaptainHook::Provider.create!(name: "a_provider")

      ordered = CaptainHook::Provider.by_name
      assert_equal "a_provider", ordered.first.name
      assert_equal "z_provider", ordered.last.name
    end

    # === Instance Methods ===

    test "webhook_url generates correct URL" do
      url = @provider.webhook_url(base_url: "https://example.com")
      assert_equal "https://example.com/captain_hook/test_provider/#{@provider.token}", url
    end

    test "webhook_url detects localhost when no base_url provided" do
      ENV.delete("APP_URL")
      ENV.delete("CODESPACES")
      ENV["PORT"] = "3000"

      url = @provider.webhook_url
      assert_includes url, "http://localhost:3000"
    ensure
      ENV.delete("PORT")
    end

    test "webhook_url detects codespaces environment" do
      original_app_url = ENV.fetch("APP_URL", nil)
      ENV.delete("APP_URL")
      ENV["CODESPACES"] = "true"
      ENV["CODESPACE_NAME"] = "my-codespace"
      ENV["PORT"] = "3004"

      url = @provider.webhook_url
      assert_includes url, "https://my-codespace-3004.app.github.dev"
    ensure
      ENV["APP_URL"] = original_app_url if original_app_url
      ENV.delete("CODESPACES")
      ENV.delete("CODESPACE_NAME")
      ENV.delete("PORT")
    end

    test "rate_limiting_enabled? returns true when configured" do
      @provider.rate_limit_requests = 100
      @provider.rate_limit_period = 60

      assert @provider.rate_limiting_enabled?
    end

    test "rate_limiting_enabled? returns false when not configured" do
      @provider.rate_limit_requests = nil
      @provider.rate_limit_period = nil

      refute @provider.rate_limiting_enabled?
    end

    # Database no longer stores these fields - they come from registry/global config
    # Removed: payload_size_limit_enabled?, timestamp_validation_enabled? tests
    # Removed: signing_secret tests (now in registry YAML via ENV vars)

    test "activate! sets active to true" do
      @provider.update!(active: false)
      @provider.activate!

      assert @provider.reload.active?
    end

    test "deactivate! sets active to false" do
      @provider.deactivate!
      refute @provider.reload.active?
    end

    # Verifier tests removed - verifier_class is now in registry, not database
    # Tests for verifier() method should be in ProviderConfig tests

    # === Associations ===

    test "has many incoming_events" do
      assert_respond_to @provider, :incoming_events
    end

    test "has many actions" do
      assert_respond_to @provider, :actions
    end

    test "cannot delete provider with incoming_events" do
      CaptainHook::IncomingEvent.create!(
        provider: @provider.name,
        external_id: "evt_123",
        event_type: "test.event",
        payload: {},
        headers: {}
      )

      # Rails 8 raises RecordNotDestroyed when restrict_with_error dependency exists
      assert_raises(ActiveRecord::RecordNotDestroyed) do
        @provider.destroy!
      end

      # Verify provider still exists
      assert CaptainHook::Provider.exists?(@provider.id)
    end

    test "deleting provider deletes associated actions" do
      CaptainHook::Action.create!(
        provider: @provider.name,
        event_type: "test.event",
        action_class: ".*Action"
      )

      assert_difference "CaptainHook::Action.count", -1 do
        @provider.destroy
      end
    end

    # === Token Generation ===

    test "generate_token creates unique token" do
      provider = CaptainHook::Provider.new(name: "token_test")
      provider.save!

      assert_not_nil provider.token
      assert provider.token.length >= 32
    end

    test "normalize_name is called before validation" do
      provider = CaptainHook::Provider.new(name: "MixedCase_Name")
      provider.valid?

      assert_equal "mixedcase_name", provider.name
    end
  end
end
