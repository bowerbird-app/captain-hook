# frozen_string_literal: true

module CaptainHook
  # Instrumentation module using ActiveSupport::Notifications
  # Provides observability for webhook processing
  module Instrumentation
    # Event names
    INCOMING_RECEIVED = "incoming_event.received.captain_hook"
    INCOMING_PROCESSING = "incoming_event.processing.captain_hook"
    INCOMING_PROCESSED = "incoming_event.processed.captain_hook"
    INCOMING_FAILED = "incoming_event.failed.captain_hook"
    HANDLER_STARTED = "handler.started.captain_hook"
    HANDLER_COMPLETED = "handler.completed.captain_hook"
    HANDLER_FAILED = "handler.failed.captain_hook"
    RATE_LIMIT_EXCEEDED = "rate_limit.exceeded.captain_hook"
    SIGNATURE_VERIFIED = "signature.verified.captain_hook"
    SIGNATURE_FAILED = "signature.failed.captain_hook"

    class << self
      # Instrument incoming event received
      def incoming_received(event, provider:, event_type:)
        ActiveSupport::Notifications.instrument(
          INCOMING_RECEIVED,
          event_id: event.id,
          provider: provider,
          event_type: event_type,
          external_id: event.external_id
        )
      end

      # Instrument incoming event processing
      def incoming_processing(event)
        ActiveSupport::Notifications.instrument(
          INCOMING_PROCESSING,
          event_id: event.id,
          provider: event.provider,
          event_type: event.event_type
        )
      end

      # Instrument incoming event processed
      def incoming_processed(event, duration:)
        ActiveSupport::Notifications.instrument(
          INCOMING_PROCESSED,
          event_id: event.id,
          provider: event.provider,
          event_type: event.event_type,
          duration: duration,
          handlers_count: event.incoming_event_handlers.count
        )
      end

      # Instrument incoming event failed
      def incoming_failed(event, error:)
        ActiveSupport::Notifications.instrument(
          INCOMING_FAILED,
          event_id: event.id,
          provider: event.provider,
          event_type: event.event_type,
          error: error.class.name,
          error_message: error.message
        )
      end

      # Instrument handler started
      def handler_started(handler, event:)
        ActiveSupport::Notifications.instrument(
          HANDLER_STARTED,
          handler_id: handler.id,
          handler_class: handler.handler_class,
          event_id: event.id,
          provider: event.provider,
          attempt: handler.attempt_count + 1
        )
      end

      # Instrument handler completed
      def handler_completed(handler, duration:)
        ActiveSupport::Notifications.instrument(
          HANDLER_COMPLETED,
          handler_id: handler.id,
          handler_class: handler.handler_class,
          duration: duration
        )
      end

      # Instrument handler failed
      def handler_failed(handler, error:)
        ActiveSupport::Notifications.instrument(
          HANDLER_FAILED,
          handler_id: handler.id,
          handler_class: handler.handler_class,
          error: error.class.name,
          error_message: error.message,
          attempt: handler.attempt_count
        )
      end

      # Instrument rate limit exceeded
      def rate_limit_exceeded(provider:, current_count:, limit:)
        ActiveSupport::Notifications.instrument(
          RATE_LIMIT_EXCEEDED,
          provider: provider,
          current_count: current_count,
          limit: limit
        )
      end

      # Instrument signature verification success
      def signature_verified(provider:)
        ActiveSupport::Notifications.instrument(
          SIGNATURE_VERIFIED,
          provider: provider
        )
      end

      # Instrument signature verification failure
      def signature_failed(provider:, reason:)
        ActiveSupport::Notifications.instrument(
          SIGNATURE_FAILED,
          provider: provider,
          reason: reason
        )
      end
    end
  end
end
