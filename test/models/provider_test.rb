# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class ProviderModelTest < ActiveSupport::TestCase
    setup do
      @provider = CaptainHook::Provider.create!(
        name: "test_provider",
        display_name: "Test Provider",
        adapter_class: "CaptainHook::Adapters::Base",
        signing_secret: "test_secret",
        active: true
      )
    end

    # === Validations ===

    test "valid provider" do
      assert @provider.valid?
    end

    test "requires name" do
      provider = CaptainHook::Provider.new(adapter_class: "Test")
      refute provider.valid?
      assert_includes provider.errors[:name], "can't be blank"
    end

    test "requires unique name" do
      duplicate = CaptainHook::Provider.new(name: @provider.name, adapter_class: "Test")
      refute duplicate.valid?
      assert_includes duplicate.errors[:name], "has already been taken"
    end

    test "requires adapter_class" do
      provider = CaptainHook::Provider.new(name: "unique_test", adapter_class: nil)
      assert_not provider.valid?
      assert_includes provider.errors[:adapter_class], "can't be blank"
    end

    test "name must be lowercase alphanumeric with underscores" do
      # The normalize_name callback converts any invalid chars to underscores
      # So "Test-Provider!" becomes "test_provider_" which is valid
      # This test verifies that normalization happens
      provider = CaptainHook::Provider.new(name: "Test-Provider!", adapter_class: "Test")
      assert provider.save
      assert_equal "test_provider_", provider.name
    end

    test "normalizes name before validation" do
      provider = CaptainHook::Provider.create!(name: "Test-Provider-123", adapter_class: "CaptainHook::Adapters::Base")
      assert_equal "test_provider_123", provider.name
    end

    test "token must be unique" do
      provider1 = CaptainHook::Provider.create!(name: "provider1", adapter_class: "Test")
      provider2 = CaptainHook::Provider.new(name: "provider2", adapter_class: "Test", token: provider1.token)

      refute provider2.valid?
      assert_includes provider2.errors[:token], "has already been taken"
    end

    test "validates timestamp_tolerance_seconds is positive integer" do
      @provider.timestamp_tolerance_seconds = -1
      refute @provider.valid?

      @provider.timestamp_tolerance_seconds = 0
      refute @provider.valid?

      @provider.timestamp_tolerance_seconds = 300
      assert @provider.valid?
    end

    test "validates max_payload_size_bytes is positive integer" do
      @provider.max_payload_size_bytes = -1
      refute @provider.valid?

      @provider.max_payload_size_bytes = 0
      refute @provider.valid?

      @provider.max_payload_size_bytes = 1024
      assert @provider.valid?
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
      provider = CaptainHook::Provider.new(name: "new_provider", adapter_class: "Test")
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
      inactive = CaptainHook::Provider.create!(name: "inactive", adapter_class: "Test", active: false)

      active_providers = CaptainHook::Provider.active
      assert_includes active_providers, @provider
      refute_includes active_providers, inactive
    end

    test "inactive scope returns only inactive providers" do
      inactive = CaptainHook::Provider.create!(name: "inactive", adapter_class: "Test", active: false)

      inactive_providers = CaptainHook::Provider.inactive
      assert_includes inactive_providers, inactive
      refute_includes inactive_providers, @provider
    end

    test "by_name scope orders by name" do
      z_provider = CaptainHook::Provider.create!(name: "z_provider", adapter_class: "Test")
      a_provider = CaptainHook::Provider.create!(name: "a_provider", adapter_class: "Test")

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
      ENV["CODESPACES"] = "true"
      ENV["CODESPACE_NAME"] = "my-codespace"
      ENV["PORT"] = "3004"

      url = @provider.webhook_url
      assert_includes url, "https://my-codespace-3004.app.github.dev"
    ensure
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

    test "payload_size_limit_enabled? returns true when configured" do
      @provider.max_payload_size_bytes = 1024
      assert @provider.payload_size_limit_enabled?
    end

    test "payload_size_limit_enabled? returns false when not configured" do
      @provider.max_payload_size_bytes = nil
      refute @provider.payload_size_limit_enabled?
    end

    test "timestamp_validation_enabled? returns true when configured" do
      @provider.timestamp_tolerance_seconds = 300
      assert @provider.timestamp_validation_enabled?
    end

    test "timestamp_validation_enabled? returns false when not configured" do
      @provider.timestamp_tolerance_seconds = nil
      refute @provider.timestamp_validation_enabled?
    end

    test "signing_secret returns database value" do
      assert_equal "test_secret", @provider.signing_secret
    end

    test "signing_secret reads from environment variable" do
      @provider.name = "stripe"
      @provider.save!

      ENV["STRIPE_WEBHOOK_SECRET"] = "env_secret"

      assert_equal "env_secret", @provider.reload.signing_secret
    ensure
      ENV.delete("STRIPE_WEBHOOK_SECRET")
    end

    test "signing_secret falls back to database when env var not set" do
      @provider.name = "square"
      @provider.save!

      ENV.delete("SQUARE_WEBHOOK_SECRET")

      assert_equal "test_secret", @provider.reload.signing_secret
    end

    test "activate! sets active to true" do
      @provider.update!(active: false)
      @provider.activate!

      assert @provider.reload.active?
    end

    test "deactivate! sets active to false" do
      @provider.deactivate!
      refute @provider.reload.active?
    end

    test "adapter returns adapter instance" do
      adapter = @provider.adapter
      assert_kind_of CaptainHook::Adapters::Base, adapter
    end

    test "adapter handles invalid adapter_class gracefully" do
      @provider.adapter_class = "NonExistent::Adapter"

      adapter = @provider.adapter
      assert_kind_of CaptainHook::Adapters::Base, adapter
    end

    # === Associations ===

    test "has many incoming_events" do
      assert_respond_to @provider, :incoming_events
    end

    test "has many handlers" do
      assert_respond_to @provider, :handlers
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

    test "deleting provider deletes associated handlers" do
      handler = CaptainHook::Handler.create!(
        provider: @provider.name,
        event_type: "test.event",
        handler_class: "TestHandler"
      )

      assert_difference "CaptainHook::Handler.count", -1 do
        @provider.destroy
      end
    end

    # === Encryption ===

    test "signing_secret is encrypted" do
      @provider.signing_secret = "super_secret"
      @provider.save!

      # Check raw database value is not the plain text
      raw_value = ActiveRecord::Base.connection.execute(
        "SELECT signing_secret FROM captain_hook_providers WHERE id = '#{@provider.id}'"
      ).first["signing_secret"]

      refute_equal "super_secret", raw_value
      assert_equal "super_secret", @provider.reload.signing_secret
    end
  end
end
