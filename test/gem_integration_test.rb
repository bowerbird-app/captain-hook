# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class GemIntegrationTest < ActiveSupport::TestCase
    include CaptainHook::GemIntegration

    setup do
      # Configure a test endpoint
      CaptainHook.configuration.register_outgoing_endpoint(
        "test_endpoint",
        base_url: "https://example.com/webhooks",
        signing_secret: "test_secret",
        default_headers: { "X-Test" => "true" }
      )

      # Configure a test provider
      CaptainHook.configuration.register_provider(
        "test_provider",
        token: "test_token_123",
        signing_secret: "test_secret",
        adapter_class: "CaptainHook::Adapters::Base"
      )
    end

    teardown do
      # Clean up configuration
      CaptainHook.configuration.instance_variable_get(:@outgoing_endpoints).clear
      CaptainHook.configuration.instance_variable_get(:@providers).clear
      CaptainHook.configuration.handler_registry.clear!
    end

    # Tests for send_webhook
    test "send_webhook creates outgoing event with correct attributes" do
      assert_difference "CaptainHook::OutgoingEvent.count", 1 do
        event = send_webhook(
          provider: "test_provider",
          event_type: "test.created",
          endpoint: "test_endpoint",
          payload: { data: { id: 1 } }
        )

        assert_equal "test_provider", event.provider
        assert_equal "test.created", event.event_type
        assert_equal "https://example.com/webhooks", event.target_url
        assert_equal({ data: { id: 1 } }, event.payload)
        assert_equal "true", event.headers["X-Test"]
      end
    end

    test "send_webhook raises error when provider is blank" do
      assert_raises(ArgumentError, match: /Provider cannot be blank/) do
        send_webhook(
          provider: "",
          event_type: "test.created",
          endpoint: "test_endpoint",
          payload: {}
        )
      end
    end

    test "send_webhook raises error when event_type is blank" do
      assert_raises(ArgumentError, match: /Event type cannot be blank/) do
        send_webhook(
          provider: "test_provider",
          event_type: "",
          endpoint: "test_endpoint",
          payload: {}
        )
      end
    end

    test "send_webhook raises error when endpoint is blank" do
      assert_raises(ArgumentError, match: /Endpoint cannot be blank/) do
        send_webhook(
          provider: "test_provider",
          event_type: "test.created",
          endpoint: "",
          payload: {}
        )
      end
    end

    test "send_webhook raises error when endpoint not configured" do
      assert_raises(ArgumentError, match: /Endpoint 'nonexistent' not configured/) do
        send_webhook(
          provider: "test_provider",
          event_type: "test.created",
          endpoint: "nonexistent",
          payload: {}
        )
      end
    end

    test "send_webhook merges custom headers with default headers" do
      event = send_webhook(
        provider: "test_provider",
        event_type: "test.created",
        endpoint: "test_endpoint",
        payload: {},
        headers: { "X-Custom" => "value" }
      )

      assert_equal "true", event.headers["X-Test"]
      assert_equal "value", event.headers["X-Custom"]
    end

    test "send_webhook includes metadata" do
      event = send_webhook(
        provider: "test_provider",
        event_type: "test.created",
        endpoint: "test_endpoint",
        payload: {},
        metadata: { source: "test_gem", version: "1.0.0" }
      )

      assert_equal "test_gem", event.metadata["source"]
      assert_equal "1.0.0", event.metadata["version"]
    end

    # Tests for register_webhook_handler
    test "register_webhook_handler registers handler with default options" do
      register_webhook_handler(
        provider: "test_provider",
        event_type: "test.created",
        handler_class: "TestHandler"
      )

      handlers = CaptainHook.handler_registry.handlers_for(
        provider: "test_provider",
        event_type: "test.created"
      )

      assert_equal 1, handlers.size
      handler = handlers.first
      assert_equal "test_provider", handler.provider
      assert_equal "test.created", handler.event_type
      assert_equal "TestHandler", handler.handler_class
      assert handler.async
      assert_equal 100, handler.priority
    end

    test "register_webhook_handler registers handler with custom options" do
      register_webhook_handler(
        provider: "test_provider",
        event_type: "test.created",
        handler_class: "TestHandler",
        async: false,
        priority: 50,
        retry_delays: [10, 20],
        max_attempts: 2
      )

      handler = CaptainHook.handler_registry.handlers_for(
        provider: "test_provider",
        event_type: "test.created"
      ).first

      assert_not handler.async
      assert_equal 50, handler.priority
      assert_equal [10, 20], handler.retry_delays
      assert_equal 2, handler.max_attempts
    end

    # Tests for webhook_configured?
    test "webhook_configured? returns true when endpoint is configured" do
      assert webhook_configured?("test_endpoint")
    end

    test "webhook_configured? returns false when endpoint not configured" do
      assert_not webhook_configured?("nonexistent")
    end

    # Tests for webhook_url
    test "webhook_url returns correct URL for configured provider" do
      url = webhook_url("test_provider")
      assert_equal "/captain_hook/test_provider/test_token_123", url
    end

    test "webhook_url returns nil for unconfigured provider" do
      url = webhook_url("nonexistent")
      assert_nil url
    end

    test "webhook_url uses custom token when provided" do
      url = webhook_url("test_provider", token: "custom_token")
      assert_equal "/captain_hook/test_provider/custom_token", url
    end

    test "webhook_url returns nil when provider has no token" do
      CaptainHook.configuration.register_provider(
        "no_token_provider",
        token: nil,
        adapter_class: "CaptainHook::Adapters::Base"
      )

      url = webhook_url("no_token_provider")
      assert_nil url
    end

    # Tests for build_webhook_payload
    test "build_webhook_payload creates standardized payload" do
      payload = build_webhook_payload(
        data: { user_id: 1, action: "created" }
      )

      assert payload[:id].present?
      assert payload[:timestamp].present?
      assert_equal({ user_id: 1, action: "created" }, payload[:data])
    end

    test "build_webhook_payload uses provided event_id" do
      payload = build_webhook_payload(
        data: { user_id: 1 },
        event_id: "evt_123"
      )

      assert_equal "evt_123", payload[:id]
    end

    test "build_webhook_payload uses provided timestamp" do
      timestamp = Time.utc(2025, 1, 1, 12, 0, 0)
      payload = build_webhook_payload(
        data: { user_id: 1 },
        timestamp: timestamp
      )

      assert_equal "2025-01-01T12:00:00Z", payload[:timestamp]
    end

    test "build_webhook_payload generates UUID for event_id" do
      payload = build_webhook_payload(data: {})
      assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, payload[:id])
    end

    test "build_webhook_payload generates ISO8601 timestamp" do
      payload = build_webhook_payload(data: {})
      assert_nothing_raised { Time.iso8601(payload[:timestamp]) }
    end

    # Tests for build_webhook_metadata
    test "build_webhook_metadata creates standardized metadata" do
      metadata = build_webhook_metadata(
        source: "test_gem",
        version: "1.0.0"
      )

      assert_equal "test_gem", metadata[:source]
      assert_equal "1.0.0", metadata[:version]
      assert metadata[:triggered_at].present?
    end

    test "build_webhook_metadata includes additional metadata" do
      metadata = build_webhook_metadata(
        source: "test_gem",
        additional: { environment: "production", user_id: 123 }
      )

      assert_equal "test_gem", metadata[:source]
      assert_equal "production", metadata[:environment]
      assert_equal 123, metadata[:user_id]
    end

    test "build_webhook_metadata omits nil version" do
      metadata = build_webhook_metadata(
        source: "test_gem",
        version: nil
      )

      assert_equal "test_gem", metadata[:source]
      assert_not metadata.key?(:version)
    end

    test "build_webhook_metadata generates ISO8601 timestamp" do
      metadata = build_webhook_metadata(source: "test_gem")
      assert_nothing_raised { Time.iso8601(metadata[:triggered_at]) }
    end

    # Tests for listen_to_notification
    test "listen_to_notification subscribes to notification and sends webhook" do
      # Subscribe to notification
      listen_to_notification(
        "test.event",
        provider: "test_provider",
        endpoint: "test_endpoint"
      )

      # Emit notification
      assert_difference "CaptainHook::OutgoingEvent.count", 1 do
        ActiveSupport::Notifications.instrument(
          "test.event",
          user_id: 1,
          action: "created"
        )
      end

      event = CaptainHook::OutgoingEvent.last
      assert_equal "test_provider", event.provider
      assert_equal "test.event", event.event_type
      assert_equal 1, event.payload[:user_id]
    end

    test "listen_to_notification uses event_type_proc to transform event type" do
      listen_to_notification(
        "test.event",
        provider: "test_provider",
        endpoint: "test_endpoint",
        event_type_proc: ->(name) { name.gsub(".", "_") }
      )

      ActiveSupport::Notifications.instrument("test.event", data: {})

      event = CaptainHook::OutgoingEvent.last
      assert_equal "test_event", event.event_type
    end

    test "listen_to_notification uses payload_proc to transform payload" do
      listen_to_notification(
        "test.event",
        provider: "test_provider",
        endpoint: "test_endpoint",
        payload_proc: ->(payload) { { id: payload[:user_id] } }
      )

      ActiveSupport::Notifications.instrument("test.event", user_id: 123)

      event = CaptainHook::OutgoingEvent.last
      assert_equal({ id: 123 }, event.payload)
    end

    # Integration tests
    test "complete workflow: emit notification, send webhook, register handler" do
      # Register handler
      register_webhook_handler(
        provider: "test_provider",
        event_type: "test.completed",
        handler_class: "TestCompletedHandler"
      )

      # Subscribe to notification
      listen_to_notification(
        "test.completed",
        provider: "test_provider",
        endpoint: "test_endpoint"
      )

      # Emit notification
      assert_difference "CaptainHook::OutgoingEvent.count", 1 do
        ActiveSupport::Notifications.instrument(
          "test.completed",
          resource_id: 1,
          status: "completed"
        )
      end

      # Verify outgoing event
      event = CaptainHook::OutgoingEvent.last
      assert_equal "test_provider", event.provider
      assert_equal "test.completed", event.event_type

      # Verify handler is registered
      handlers = CaptainHook.handler_registry.handlers_for(
        provider: "test_provider",
        event_type: "test.completed"
      )
      assert_equal 1, handlers.size
      assert_equal "TestCompletedHandler", handlers.first.handler_class
    end

    # Module function tests
    test "send_webhook works as module function" do
      assert_difference "CaptainHook::OutgoingEvent.count", 1 do
        CaptainHook::GemIntegration.send_webhook(
          provider: "test_provider",
          event_type: "test.created",
          endpoint: "test_endpoint",
          payload: { data: {} }
        )
      end
    end

    test "register_webhook_handler works as module function" do
      CaptainHook::GemIntegration.register_webhook_handler(
        provider: "test_provider",
        event_type: "test.created",
        handler_class: "TestHandler"
      )

      handlers = CaptainHook.handler_registry.handlers_for(
        provider: "test_provider",
        event_type: "test.created"
      )
      assert_equal 1, handlers.size
    end

    test "webhook_configured? works as module function" do
      assert CaptainHook::GemIntegration.webhook_configured?("test_endpoint")
    end

    test "webhook_url works as module function" do
      url = CaptainHook::GemIntegration.webhook_url("test_provider")
      assert_equal "/captain_hook/test_provider/test_token_123", url
    end

    test "build_webhook_payload works as module function" do
      payload = CaptainHook::GemIntegration.build_webhook_payload(data: { id: 1 })
      assert payload[:id].present?
      assert payload[:timestamp].present?
      assert_equal({ id: 1 }, payload[:data])
    end

    test "build_webhook_metadata works as module function" do
      metadata = CaptainHook::GemIntegration.build_webhook_metadata(source: "test")
      assert_equal "test", metadata[:source]
    end
  end
end
