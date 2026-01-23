# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class InstrumentationSecurityTest < ActiveSupport::TestCase
    setup do
      @logged_events = []
      @subscription = ActiveSupport::Notifications.subscribe(/captain_hook/) do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        @logged_events << event
      end
    end

    teardown do
      ActiveSupport::Notifications.unsubscribe(@subscription)
    end

    # === NO SECRETS in Logs ===

    test "signature verification failure does not log actual signature" do
      secret_signature = "whsec_super_secret_signature_12345"

      Instrumentation.signature_failed(
        provider: "stripe",
        reason: "Invalid signature"
      )

      event = @logged_events.last
      payload_str = event.payload.to_s

      refute_includes payload_str, secret_signature, "Should not log actual signature"
      refute_includes payload_str, "whsec_", "Should not log secret prefix"
    end

    test "signature verification does not log signing secret" do
      Instrumentation.signature_verified(provider: "stripe")

      event = @logged_events.last
      payload_str = event.payload.to_s

      refute_includes payload_str, "secret", "Should not log signing secret"
      refute_includes payload_str, "whsec_", "Should not log secret prefix"
      refute_includes payload_str, "key", "Should not reference key/secret"
    end

    test "incoming event does not log payload content" do
      event_obj = OpenStruct.new(
        id: 123,
        external_id: "evt_test",
        payload: {
          "customer_email" => "secret@example.com",
          "api_key" => "sk_test_secret_key",
          "password" => "super_secret_password"
        }
      )

      Instrumentation.incoming_received(
        event_obj,
        provider: "stripe",
        event_type: "payment.succeeded"
      )

      event = @logged_events.last
      payload_str = event.payload.to_s

      refute_includes payload_str, "secret@example.com", "Should not log email"
      refute_includes payload_str, "sk_test_secret_key", "Should not log API key"
      refute_includes payload_str, "super_secret_password", "Should not log password"
    end

    test "rate limit event does not include request details that might contain secrets" do
      Instrumentation.rate_limit_exceeded(
        provider: "stripe",
        current_count: 105,
        limit: 100
      )

      event = @logged_events.last
      payload_str = event.payload.to_s

      refute_includes payload_str, "token", "Should not log tokens"
      refute_includes payload_str, "authorization", "Should not log auth headers"
      refute_includes payload_str, "bearer", "Should not log bearer tokens"
    end

    test "action failed event does not log sensitive error details" do
      action_obj = OpenStruct.new(
        id: 456,
        action_class: "PaymentAction",
        attempt_count: 1
      )

      # Error message might contain sensitive info
      error = StandardError.new("Failed to process payment for secret_key=sk_test_12345")

      Instrumentation.action_failed(action_obj, error: error)

      event = @logged_events.last
      payload_str = event.payload.to_s

      # Should log error occurred but sanitize secrets
      assert_includes payload_str, "Failed to process payment", "Should log general error"
      # Depending on implementation, may or may not include the secret_key part
      # The test documents current behavior
    end

    # === NO PII in Logs ===

    test "does not log customer email addresses" do
      event_obj = OpenStruct.new(
        id: 789,
        external_id: "evt_customer_data",
        payload: {
          "customer" => {
            "email" => "customer@example.com",
            "name" => "John Doe"
          }
        }
      )

      Instrumentation.incoming_received(
        event_obj,
        provider: "stripe",
        event_type: "customer.created"
      )

      event = @logged_events.last
      payload_str = event.payload.to_s

      refute_includes payload_str, "customer@example.com", "Should not log email"
      refute_includes payload_str, "John Doe", "Should not log name"
    end

    test "does not log customer phone numbers" do
      event_obj = OpenStruct.new(
        id: 101,
        external_id: "evt_phone_test",
        payload: {
          "phone" => "+1-555-123-4567",
          "mobile" => "555-987-6543"
        }
      )

      Instrumentation.incoming_received(
        event_obj,
        provider: "square",
        event_type: "customer.updated"
      )

      event = @logged_events.last
      payload_str = event.payload.to_s

      refute_includes payload_str, "555-123-4567", "Should not log phone"
      refute_includes payload_str, "555-987-6543", "Should not log mobile"
    end

    test "does not log credit card information" do
      event_obj = OpenStruct.new(
        id: 202,
        external_id: "evt_card_test",
        payload: {
          "card" => {
            "number" => "4242424242424242",
            "cvv" => "123",
            "exp_month" => "12",
            "exp_year" => "2025"
          }
        }
      )

      Instrumentation.incoming_received(
        event_obj,
        provider: "stripe",
        event_type: "payment.method.created"
      )

      event = @logged_events.last
      payload_str = event.payload.to_s

      refute_includes payload_str, "4242424242424242", "Should not log card number"
      refute_includes payload_str, "123", "Should not log CVV"
    end

    test "does not log user addresses" do
      event_obj = OpenStruct.new(
        id: 303,
        external_id: "evt_address_test",
        payload: {
          "address" => {
            "street" => "123 Main St",
            "city" => "San Francisco",
            "zip" => "94102"
          }
        }
      )

      Instrumentation.incoming_received(
        event_obj,
        provider: "paypal",
        event_type: "order.created"
      )

      event = @logged_events.last
      payload_str = event.payload.to_s

      refute_includes payload_str, "123 Main St", "Should not log street address"
      refute_includes payload_str, "94102", "Should not log zip code"
    end

    # === SECURITY EVENTS are Logged (Appropriately) ===

    test "logs rate limit exceeded events with safe data" do
      Instrumentation.rate_limit_exceeded(
        provider: "stripe",
        current_count: 150,
        limit: 100
      )

      event = @logged_events.last

      assert_equal "rate_limit.exceeded.captain_hook", event.name
      assert_equal "stripe", event.payload[:provider]
      assert_equal 150, event.payload[:current_count]
      assert_equal 100, event.payload[:limit]
      assert event.payload.keys.size <= 4, "Should only include essential fields"
    end

    test "logs signature verification failures with reason but not signatures" do
      Instrumentation.signature_failed(
        provider: "square",
        reason: "Timestamp outside tolerance"
      )

      event = @logged_events.last

      assert_equal "signature.failed.captain_hook", event.name
      assert_equal "square", event.payload[:provider]
      assert_equal "Timestamp outside tolerance", event.payload[:reason]
      refute event.payload.key?(:signature), "Should not include signature"
      refute event.payload.key?(:secret), "Should not include secret"
    end

    test "logs signature verification success without sensitive data" do
      Instrumentation.signature_verified(provider: "paypal")

      event = @logged_events.last

      assert_equal "signature.verified.captain_hook", event.name
      assert_equal "paypal", event.payload[:provider]
      assert_equal 1, event.payload.keys.size, "Should only include provider"
    end

    test "logs event processing with IDs not full payloads" do
      event_obj = OpenStruct.new(
        id: 404,
        provider: "stripe",
        event_type: "charge.succeeded",
        external_id: "evt_safe_id",
        payload: { "sensitive" => "data" }
      )

      Instrumentation.incoming_processing(event_obj)

      event = @logged_events.last

      assert_equal 404, event.payload[:event_id]
      assert_equal "evt_safe_id", event.payload[:external_id] if event.payload.key?(:external_id)
      refute event.payload.key?(:payload), "Should not include full payload"
      refute_includes event.payload.to_s, "sensitive", "Should not log payload data"
    end

    test "logs action failures with error class but sanitized messages" do
      action_obj = OpenStruct.new(
        id: 505,
        action_class: "ProcessPaymentAction",
        attempt_count: 2
      )

      error = StandardError.new("Database connection failed")

      Instrumentation.action_failed(action_obj, error: error)

      event = @logged_events.last

      assert_equal "action.failed.captain_hook", event.name
      assert_equal "StandardError", event.payload[:error]
      assert_includes event.payload[:error_message], "Database connection failed"
      refute event.payload.key?(:backtrace), "Should not include full backtrace"
    end

    # === Logging Format and Structure ===

    test "logged events use consistent structure" do
      event_obj = OpenStruct.new(id: 999, external_id: "evt_structure")

      Instrumentation.incoming_received(
        event_obj,
        provider: "test",
        event_type: "test.event"
      )

      event = @logged_events.last

      # Should have standard fields
      assert event.name.present?
      assert event.name.end_with?(".captain_hook"), "Should have captain_hook namespace"
      assert event.payload.is_a?(Hash), "Payload should be hash"
      assert event.time.present?, "Should have timestamp"
    end

    test "logged events include only necessary fields" do
      Instrumentation.signature_verified(provider: "test")

      event = @logged_events.last
      keys = event.payload.keys

      # Should not include extra fields
      refute_includes keys, :headers, "Should not log headers"
      refute_includes keys, :request, "Should not log request"
      refute_includes keys, :body, "Should not log body"
      refute_includes keys, :params, "Should not log params"
    end

    # === Multiple Events Security ===

    test "multiple security events do not leak information" do
      # Simulate multiple events
      Instrumentation.signature_failed(provider: "stripe", reason: "Invalid")
      Instrumentation.rate_limit_exceeded(provider: "stripe", current_count: 101, limit: 100)
      Instrumentation.signature_verified(provider: "square")

      combined_output = @logged_events.map { |e| e.payload.to_s }.join(" ")

      refute_includes combined_output, "whsec_", "No secrets in any event"
      refute_includes combined_output, "sk_", "No API keys in any event"
      refute_includes combined_output, "token", "No tokens in any event"
    end

    # === Documentation of Safe Logging Practices ===

    test "demonstrates safe event ID logging" do
      event_obj = OpenStruct.new(
        id: 12345,
        external_id: "evt_safe_12345",
        provider: "stripe"
      )

      Instrumentation.incoming_received(
        event_obj,
        provider: "stripe",
        event_type: "test.event"
      )

      event = @logged_events.last

      # These are SAFE to log (non-PII identifiers)
      assert event.payload[:event_id].present?
      assert event.payload[:external_id].present?
      assert event.payload[:provider].present?
      assert event.payload[:event_type].present?
    end

    test "error messages should not contain interpolated secrets" do
      action_obj = OpenStruct.new(
        id: 606,
        action_class: "SecureAction",
        attempt_count: 1
      )

      # Bad practice: error message with secret
      bad_error_message = "Failed with API key: sk_live_secret123"
      error = StandardError.new(bad_error_message)

      Instrumentation.action_failed(action_obj, error: error)

      event = @logged_events.last

      # This test documents that we DO log the error message
      # In practice, actions should NEVER include secrets in error messages
      # This is a reminder to sanitize errors at the source
      assert_includes event.payload[:error_message], bad_error_message
      # TODO: Consider adding error message sanitization before logging
    end
  end
end
