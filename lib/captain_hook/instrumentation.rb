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
    ACTION_STARTED = "action.started.captain_hook"
    ACTION_COMPLETED = "action.completed.captain_hook"
    ACTION_FAILED = "action.failed.captain_hook"
    RATE_LIMIT_EXCEEDED = "rate_limit.exceeded.captain_hook"
    SIGNATURE_VERIFIED = "signature.verified.captain_hook"
    SIGNATURE_FAILED = "signature.failed.captain_hook"

    # Deprecated: Backward compatibility
    HANDLER_STARTED = ACTION_STARTED
    HANDLER_COMPLETED = ACTION_COMPLETED
    HANDLER_FAILED = ACTION_FAILED

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
          actions_count: event.incoming_event_actions.count
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

      # Instrument action started
      def action_started(action, event:)
        ActiveSupport::Notifications.instrument(
          ACTION_STARTED,
          action_id: action.id,
          action_class: action.action_class,
          event_id: event.id,
          provider: event.provider,
          attempt: action.attempt_count + 1
        )
      end

      # Deprecated: Backward compatibility
      alias handler_started action_started

      # Instrument action completed
      def action_completed(action, duration:)
        ActiveSupport::Notifications.instrument(
          ACTION_COMPLETED,
          action_id: action.id,
          action_class: action.action_class,
          duration: duration
        )
      end

      # Deprecated: Backward compatibility
      alias handler_completed action_completed

      # Instrument action failed
      def action_failed(action, error:)
        ActiveSupport::Notifications.instrument(
          ACTION_FAILED,
          action_id: action.id,
          action_class: action.action_class,
          error: error.class.name,
          error_message: error.message,
          attempt: action.attempt_count
        )
      end

      # Deprecated: Backward compatibility
      alias handler_failed action_failed

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
