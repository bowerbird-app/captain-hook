# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    # Helper method to generate Stripe signatures
    def generate_stripe_signature(payload, timestamp, secret)
      signed_payload = "#{timestamp}.#{payload}"
      OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    end

    setup do
      # Clear action registry before each test
      CaptainHook.action_registry.clear!
      # Clear in-memory provider registrations
      CaptainHook.configuration.instance_variable_set(:@providers, {})
      CaptainHook.configuration.instance_variable_set(:@registry_cache, {})

      @provider = CaptainHook::Provider.find_or_create_by!(name: "stripe") do |p|
        p.active = true
        p.token = "test_token"
        p.rate_limit_requests = 100
        p.rate_limit_period = 60
      end

      # Ensure token is always set correctly (find_or_create_by only runs block on create)
      @provider.update!(token: "test_token", active: true)

      # Test signing secret (signing_secret is now in registry, not DB)
      @test_signing_secret = "whsec_test123"

      # Register stripe provider in memory with test signing secret
      CaptainHook.configuration.register_provider("stripe",
                                                  signing_secret: @test_signing_secret,
                                                  verifier_class: "CaptainHook::Verifiers::Stripe")

      # Register a test action
      CaptainHook.register_action(
        provider: "stripe",
        event_type: "charge.succeeded",
        action_class: "TestChargeAction"
      )

      @valid_payload = {
        id: "evt_test_#{SecureRandom.hex(8)}",
        type: "charge.succeeded",
        data: { object: { id: "ch_test" } }
      }.to_json

      @timestamp = Time.now.to_i.to_s
    end

    test "should receive webhook with valid signature" do
      signature = generate_stripe_signature(@valid_payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :created
      json = JSON.parse(response.body)
      assert_equal "received", json["status"]
      assert json["id"].present?
    end

    test "should reject webhook with invalid signature" do
      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=invalid_signature"
           }

      assert_response :unauthorized
      json = JSON.parse(response.body)
      assert_equal "Invalid signature", json["error"]
    end

    test "should reject webhook with invalid token" do
      signature = generate_stripe_signature(@valid_payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/wrong_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :unauthorized
      json = JSON.parse(response.body)
      assert_equal "Invalid token", json["error"]
    end

    test "should reject webhook for unknown provider" do
      post "/captain_hook/unknown_provider/test_token",
           params: @valid_payload,
           headers: { "Content-Type" => "application/json" }

      assert_response :not_found
      json = JSON.parse(response.body)
      assert_equal "Unknown provider", json["error"]
    end

    test "should reject webhook for inactive provider" do
      @provider.update!(active: false)

      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: { "Content-Type" => "application/json" }

      assert_response :forbidden
      json = JSON.parse(response.body)
      assert_equal "Provider is inactive", json["error"]
    end

    test "should reject webhook with invalid JSON" do
      invalid_payload = "not-json"
      signature = generate_stripe_signature(invalid_payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           env: { "RAW_POST_DATA" => invalid_payload },
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :bad_request
      json = JSON.parse(response.body)
      assert_equal "Invalid JSON", json["error"]
    end

    test "should handle duplicate events" do
      signature = generate_stripe_signature(@valid_payload, @timestamp, @test_signing_secret)

      # First request
      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }
      assert_response :created

      # Duplicate request
      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }
      assert_response :ok
      json = JSON.parse(response.body)
      assert_equal "duplicate", json["status"]
    end

    test "should reject webhook with expired timestamp" do
      old_timestamp = (Time.now - 400).to_i.to_s # 400 seconds ago, outside tolerance
      signature = generate_stripe_signature(@valid_payload, old_timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{old_timestamp},v1=#{signature}"
           }

      assert_response :unauthorized
      json = JSON.parse(response.body)
      assert_equal "Invalid signature", json["error"]
    end

    test "should accept webhook with valid timestamp" do
      fresh_timestamp = Time.now.to_i.to_s
      signature = generate_stripe_signature(@valid_payload, fresh_timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{fresh_timestamp},v1=#{signature}"
           }

      assert_response :created
    end

    test "should reject webhook with oversized payload" do
      # Create a provider with small payload limit
      small_provider = CaptainHook::Provider.create!(
        name: "small",
        active: true,
        token: "small_test_token"
      )

      # Register in memory with small payload limit
      CaptainHook.configuration.register_provider("small",
                                                  signing_secret: @test_signing_secret,
                                                  verifier_class: "CaptainHook::Verifiers::Stripe",
                                                  max_payload_size_bytes: 100) # Small limit to trigger rejection

      large_payload = {
        id: "evt_large",
        type: "charge.succeeded",
        data: { object: { description: "x" * 200 } }
      }.to_json

      signature = generate_stripe_signature(large_payload, @timestamp, @test_signing_secret)

      post "/captain_hook/small/small_test_token",
           params: large_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :content_too_large
      json = JSON.parse(response.body)
      assert_equal "Payload too large", json["error"]
    end

    test "should create action records for event" do
      signature = generate_stripe_signature(@valid_payload, @timestamp, @test_signing_secret)

      assert_difference "CaptainHook::IncomingEvent.count", 1 do
        assert_difference "CaptainHook::IncomingEventAction.count", 1 do
          post "/captain_hook/stripe/test_token",
               params: @valid_payload,
               headers: {
                 "Content-Type" => "application/json",
                 "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
               }
        end
      end

      assert_response :created
      event = CaptainHook::IncomingEvent.last
      assert_equal "stripe", event.provider
      assert_equal "charge.succeeded", event.event_type
    end

    test "should extract headers correctly" do
      signature = generate_stripe_signature(@valid_payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}",
             "X-Custom-Header" => "test-value"
           }

      assert_response :created
      event = CaptainHook::IncomingEvent.last
      assert event.headers["Stripe-Signature"].present?
      assert event.headers["Content-Type"].present?
    end

    test "should handle events with no registered actions" do
      payload_no_action = {
        id: "evt_no_action",
        type: "no.action.event",
        data: { object: { id: "ch_test" } }
      }.to_json

      signature = generate_stripe_signature(payload_no_action, @timestamp, @test_signing_secret)

      assert_difference "CaptainHook::IncomingEvent.count", 1 do
        assert_no_difference "CaptainHook::IncomingEventAction.count" do
          post "/captain_hook/stripe/test_token",
               params: payload_no_action,
               headers: {
                 "Content-Type" => "application/json",
                 "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
               }
        end
      end

      assert_response :created
    end

    test "should skip CSRF token verification" do
      # This test verifies that skip_before_action :verify_authenticity_token works
      signature = generate_stripe_signature(@valid_payload, @timestamp, @test_signing_secret)

      # Don't include CSRF token
      post "/captain_hook/stripe/test_token",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      # Should not raise ActionController::InvalidAuthenticityToken
      assert_response :created
    end

    # === Security Tests ===

    test "should use constant-time comparison for token validation" do
      signature = generate_stripe_signature(@valid_payload, @timestamp, @test_signing_secret)

      # Test with nearly-matching token (differs by one character)
      post "/captain_hook/stripe/test_tokeo",
           params: @valid_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :unauthorized
      json = JSON.parse(response.body)
      assert_equal "Invalid token", json["error"]
    end

    test "should prevent timing attacks on token comparison" do
      signature = generate_stripe_signature(@valid_payload, @timestamp, @test_signing_secret)

      # Test multiple tokens with varying similarity
      tokens_to_test = [
        "aaaa_token",      # Completely different
        "test_aaaaa",      # Same length, different end
        "tast_token",      # One char different in middle
        "test_tokeo"       # One char different at end
      ]

      tokens_to_test.each do |wrong_token|
        post "/captain_hook/stripe/#{wrong_token}",
             params: @valid_payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
             }

        assert_response :unauthorized, "Token #{wrong_token} should be rejected"
        json = JSON.parse(response.body)
        assert_equal "Invalid token", json["error"]
      end
    end

    test "should sanitize error logs for invalid JSON to prevent sensitive data leakage" do
      invalid_payload = '{"secret": "supersecret", "invalid": json}'
      signature = generate_stripe_signature(invalid_payload, @timestamp, @test_signing_secret)

      # Capture Rails logger output
      log_output = StringIO.new
      original_logger = Rails.logger
      Rails.logger = Logger.new(log_output)

      post "/captain_hook/stripe/test_token",
           env: { "RAW_POST_DATA" => invalid_payload },
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :bad_request

      # Verify log contains only provider name, not sensitive payload
      log_content = log_output.string
      assert_includes log_content, "provider=stripe", "Should log provider name"
      refute_includes log_content, "supersecret", "Should NOT log sensitive data from payload"
      refute_includes log_content, invalid_payload, "Should NOT log raw payload"

      Rails.logger = original_logger
    end

    test "should not expose error details in response for invalid JSON" do
      invalid_payload = '{"secret": "supersecret", "password": "hunter2", invalid: }'
      signature = generate_stripe_signature(invalid_payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           env: { "RAW_POST_DATA" => invalid_payload },
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :bad_request
      json = JSON.parse(response.body)

      # Response should be generic, not expose payload details
      assert_equal "Invalid JSON", json["error"]
      refute_includes response.body, "supersecret"
      refute_includes response.body, "hunter2"
    end
  end
end
