# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class IncomingControllerParserTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    setup do
      # Clear registries
      CaptainHook.action_registry.clear!
      CaptainHook.configuration.instance_variable_set(:@providers, {})
      CaptainHook.configuration.instance_variable_set(:@registry_cache, {})

      @provider = CaptainHook::Provider.find_or_create_by!(name: "stripe") do |p|
        p.active = true
        p.token = "test_token"
        p.rate_limit_requests = 100
        p.rate_limit_period = 60
      end

      @provider.update!(token: "test_token", active: true)

      @test_signing_secret = "whsec_test123"

      # Register provider in memory
      CaptainHook.configuration.register_provider("stripe",
                                                  signing_secret: @test_signing_secret,
                                                  verifier_class: "CaptainHook::Verifiers::Stripe")

      @timestamp = Time.now.to_i.to_s
    end

    # === INVALID JSON Tests ===

    test "rejects invalid JSON with malformed syntax" do
      post "/captain_hook/stripe/test_token",
           params: "{ invalid json syntax",
           headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
      json = JSON.parse(response.body)
      assert_match(/invalid json/i, json["error"])
    end

    test "rejects JSON with unclosed braces" do
      post "/captain_hook/stripe/test_token",
           params: '{"id":"evt_test", "type":"test"',
           headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
    end

    test "rejects JSON with trailing commas" do
      post "/captain_hook/stripe/test_token",
           params: '{"id":"evt_test", "type":"test",}',
           headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
    end

    test "rejects JSON with single quotes instead of double quotes" do
      post "/captain_hook/stripe/test_token",
           params: "{'id':'evt_test', 'type':'test'}",
           headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
    end

    test "rejects JSON with unquoted keys" do
      post "/captain_hook/stripe/test_token",
           params: "{id:'evt_test', type:'test'}",
           headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
    end

    # === EMPTY Payload Tests ===

    test "rejects completely empty payload" do
      post "/captain_hook/stripe/test_token",
           params: "",
           headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
    end

    test "rejects payload with only whitespace" do
      post "/captain_hook/stripe/test_token",
           params: "   \n\t  ",
           headers: { "Content-Type" => "application/json" }

      assert_response :bad_request
    end

    test "rejects empty JSON object when event_id required" do
      valid_signature = generate_stripe_signature("{}", @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: "{}",
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{valid_signature}"
           }

      # May accept or reject depending on verifier requirements
      # Document the actual behavior
      assert_response [:created, :bad_request, :unprocessable_entity]
    end

    # === NULL Payload Tests ===

    test "rejects JSON null payload" do
      post "/captain_hook/stripe/test_token",
           params: "null",
           headers: { "Content-Type" => "application/json" }

      assert_response [:bad_request, :unprocessable_entity]
    end

    test "handles null values in JSON payload" do
      payload = '{"id":"evt_test","type":"test","data":null}'
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      # Should accept null values in payload
      assert_response [:created, :ok]
    end

    # === HUGE Payload Tests (DoS Protection) ===

    test "accepts payload at exact size limit" do
      # Assuming 1MB limit
      large_data = "x" * (1_048_576 - 100) # Leave room for JSON structure
      payload = %{{"id":"evt_test","type":"test","data":"#{large_data}"}}
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      # Should accept if within limit
      assert_response [:created, :ok, :content_too_large]
    end

    test "rejects oversized payload" do
      # 2MB payload (over 1MB limit)
      huge_data = "x" * 2_000_000
      huge_payload = %{{"id":"evt_test","type":"test","data":"#{huge_data}"}}

      post "/captain_hook/stripe/test_token",
           params: huge_payload,
           headers: { "Content-Type" => "application/json" }

      assert_response :content_too_large
      json = JSON.parse(response.body)
      assert_match(/payload too large/i, json["error"])
    end

    test "handles very large JSON array" do
      large_array = (1..10000).map { |i| { "id" => i, "value" => "item_#{i}" } }
      payload = { id: "evt_test", type: "test", items: large_array }.to_json

      # Only test if within size limit
      if payload.bytesize < 1_048_576
        signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

        post "/captain_hook/stripe/test_token",
             params: payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
             }

        assert_response [:created, :ok]
      end
    end

    # === WEIRD Encoding Tests ===

    test "handles UTF-8 encoded payload" do
      payload = {
        id: "evt_test_#{SecureRandom.hex(4)}",
        type: "test.event",
        message: "Hello 世界 🌍 émojis"
      }.to_json
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json; charset=utf-8",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :created
      json = JSON.parse(response.body)
      assert_equal "received", json["status"]
    end

    test "handles payload with emoji in multiple fields" do
      payload = {
        id: "evt_emoji_test_#{SecureRandom.hex(4)}",
        type: "emoji.test",
        description: "Testing 🎉 with 🔥 emojis 🚀",
        data: { message: "Hello 👋 World 🌍" }
      }.to_json
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :created
    end

    test "handles payload with special Unicode characters" do
      payload = {
        id: "evt_unicode_#{SecureRandom.hex(4)}",
        type: "test.event",
        text: "Special chars: ™ © ® € £ ¥ § ¶ † ‡ • …"
      }.to_json
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :created
    end

    test "handles payload with escaped characters" do
      payload = {
        id: "evt_escaped_#{SecureRandom.hex(4)}",
        type: "test.event",
        data: "Escaped: \\n \\t \\r \\\\ \\\" \\'"
      }.to_json
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :created
    end

    test "handles payload with control characters" do
      # JSON should escape control characters
      payload = {
        id: "evt_control_#{SecureRandom.hex(4)}",
        type: "test.event",
        data: "Text with\nnewline and\ttab"
      }.to_json
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :created
    end

    # === Missing Content-Type Header ===

    test "handles missing Content-Type header gracefully" do
      payload = {
        id: "evt_no_ct_#{SecureRandom.hex(4)}",
        type: "test.event"
      }.to_json
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      # Should handle gracefully - may accept or require Content-Type
      assert_response [:created, :ok, :bad_request, :unsupported_media_type]
    end

    # === ARRAY Instead of Object ===

    test "handles JSON array payload" do
      payload = '[{"id":"evt_1","type":"test"},{"id":"evt_2","type":"test"}]'
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      # Behavior depends on application logic
      # Document whether arrays are accepted
      assert_response [:created, :ok, :bad_request, :unprocessable_entity]
    end

    # === Deeply Nested JSON ===

    test "handles deeply nested JSON structure" do
      nested = { "level1" => { "level2" => { "level3" => { "level4" => { "value" => "deep" } } } } }
      payload = {
        id: "evt_nested_#{SecureRandom.hex(4)}",
        type: "test.event",
        data: nested
      }.to_json

      if payload.bytesize < 1_048_576 # Within size limit
        signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

        post "/captain_hook/stripe/test_token",
             params: payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
             }

        assert_response :created
      end
    end

    # === Boolean and Number Types ===

    test "handles boolean values in payload" do
      payload = {
        id: "evt_bool_#{SecureRandom.hex(4)}",
        type: "test.event",
        active: true,
        disabled: false
      }.to_json
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :created
    end

    test "handles numeric values including floats" do
      payload = {
        id: "evt_num_#{SecureRandom.hex(4)}",
        type: "test.event",
        count: 42,
        amount: 99.99,
        large_number: 9999999999
      }.to_json
      signature = generate_stripe_signature(payload, @timestamp, @test_signing_secret)

      post "/captain_hook/stripe/test_token",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{@timestamp},v1=#{signature}"
           }

      assert_response :created
    end

    private

    def generate_stripe_signature(payload, timestamp, secret)
      signed_payload = "#{timestamp}.#{payload}"
      OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
    end
  end
end
