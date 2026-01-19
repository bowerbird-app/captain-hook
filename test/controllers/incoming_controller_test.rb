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
      # Clear handler registry before each test
      CaptainHook.handler_registry.clear!

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

      # Register a test handler
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
      signature = generate_stripe_signature(@valid_payload, @timestamp, @provider.signing_secret)

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
      signature = generate_stripe_signature(@valid_payload, @timestamp, @provider.signing_secret)

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
      signature = generate_stripe_signature(invalid_payload, @timestamp, @provider.signing_secret)

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
      signature = generate_stripe_signature(@valid_payload, @timestamp, @provider.signing_secret)

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
      signature = generate_stripe_signature(@valid_payload, old_timestamp, @provider.signing_secret)

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
      signature = generate_stripe_signature(@valid_payload, fresh_timestamp, @provider.signing_secret)

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
        verifier_class: "CaptainHook::Verifiers::Stripe",
        active: true,
        token: "small_test_token",
        signing_secret: "whsec_test123",
        max_payload_size_bytes: 100 # Very small limit
      )

      large_payload = {
        id: "evt_large",
        type: "charge.succeeded",
        data: { object: { description: "x" * 200 } }
      }.to_json

      signature = generate_stripe_signature(large_payload, @timestamp, small_provider.signing_secret)

      post "/captain_hook/small/small_test_token",
           params: large_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :payload_too_large
      json = JSON.parse(response.body)
      assert_equal "Payload too large", json["error"]
    end

    test "should create handler records for event" do
      signature = generate_stripe_signature(@valid_payload, @timestamp, @provider.signing_secret)

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
      signature = generate_stripe_signature(@valid_payload, @timestamp, @provider.signing_secret)

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

    test "should handle events with no registered handlers" do
      payload_no_handler = {
        id: "evt_no_handler",
        type: "no.handler.event",
        data: { object: { id: "ch_test" } }
      }.to_json

      signature = generate_stripe_signature(payload_no_handler, @timestamp, @provider.signing_secret)

      assert_difference "CaptainHook::IncomingEvent.count", 1 do
        assert_no_difference "CaptainHook::IncomingEventAction.count" do
          post "/captain_hook/stripe/test_token",
               params: payload_no_handler,
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
      signature = generate_stripe_signature(@valid_payload, @timestamp, @provider.signing_secret)

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
  end
end
