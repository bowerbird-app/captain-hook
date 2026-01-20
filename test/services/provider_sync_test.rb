# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class ProviderSyncTest < ActiveSupport::TestCase
      setup do
        # Clear any existing providers
        CaptainHook::Provider.delete_all

        # Provider definitions from registry (YAML files)
        # Only DB-managed fields should be synced: active, rate_limit_requests, rate_limit_period
        @provider_definitions = [
          {
            "name" => "test_provider",
            "display_name" => "Test Provider",
            "description" => "A test provider",
            "verifier_class" => "CaptainHook::Verifiers::Base",
            "verifier_file" => "test_provider.rb",
            "active" => true,
            "signing_secret" => "ENV[TEST_SECRET]",
            "timestamp_tolerance_seconds" => 300,
            "rate_limit_requests" => 100,
            "rate_limit_period" => 60,
            "source_file" => "/test/providers/test_provider.yml",
            "source" => "test"
          }
        ]
      end

      test "creates new provider from definition" do
        sync = ProviderSync.new(@provider_definitions)
        results = sync.call

        assert_equal 1, results[:created].size
        assert_equal 0, results[:updated].size
        assert_equal 0, results[:errors].size

        provider = CaptainHook::Provider.find_by(name: "test_provider")
        assert_not_nil provider
        # Only DB fields are synced
        assert provider.active?
        assert_equal 100, provider.rate_limit_requests
        assert_equal 60, provider.rate_limit_period
        # Token is auto-generated
        assert_not_nil provider.token
        
        # These fields are NOT in database anymore
        assert_nil provider.attributes["display_name"]
        assert_nil provider.attributes["description"]
        assert_nil provider.attributes["verifier_class"]
        assert_nil provider.attributes["signing_secret"]
        assert_nil provider.attributes["timestamp_tolerance_seconds"]
      end

      test "updates existing provider from definition" do
        # Create initial provider
        provider = CaptainHook::Provider.create!(
          name: "test_provider",
          active: false,
          rate_limit_requests: 50,
          rate_limit_period: 30
        )

        sync = ProviderSync.new(@provider_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 1, results[:updated].size
        assert_equal 0, results[:errors].size

        provider.reload
        # DB fields should be updated
        assert provider.active?
        assert_equal 100, provider.rate_limit_requests
        assert_equal 60, provider.rate_limit_period
      end

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

      test "handles invalid provider definition" do
        invalid_definitions = [
          {
            "name" => "",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(invalid_definitions)
        results = sync.call

        assert_equal 0, results[:created].size
        assert_equal 1, results[:errors].size
        assert results[:errors].first[:error].present?
      end

      test "handles multiple providers in one sync" do
        multi_definitions = [
          {
            "name" => "provider_one",
            "active" => true,
            "source" => "test"
          },
          {
            "name" => "provider_two",
            "active" => false,
            "rate_limit_requests" => 200,
            "rate_limit_period" => 120,
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(multi_definitions)
        results = sync.call

        assert_equal 2, results[:created].size
        assert CaptainHook::Provider.exists?(name: "provider_one")
        assert CaptainHook::Provider.exists?(name: "provider_two")
        
        provider_two = CaptainHook::Provider.find_by(name: "provider_two")
        assert_equal 200, provider_two.rate_limit_requests
        assert_equal 120, provider_two.rate_limit_period
      end

      test "sets default active to true when not specified" do
        definitions = [
          {
            "name" => "default_active_provider",
            "source" => "test"
          }
        ]

        sync = ProviderSync.new(definitions)
        sync.call

        provider = CaptainHook::Provider.find_by(name: "default_active_provider")
        assert provider.active?, "Provider should be active by default"
      end

      test "valid_provider_definition checks for name presence" do
        sync = ProviderSync.new([])
        result = sync.send(:valid_provider_definition?, { "source" => "test" })
        refute result, "Should be invalid without name"
      end

      test "only updates database-managed fields" do
        # Create provider with initial values
        provider = CaptainHook::Provider.create!(
          name: "test_provider",
          active: false
        )

        # Try to sync with updated values
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
    end
  end
end
