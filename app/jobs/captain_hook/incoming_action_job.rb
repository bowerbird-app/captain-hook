# frozen_string_literal: true

module CaptainHook
  # Job to process incoming webhook event actions
  # Supports retry logic, priority ordering, and optimistic locking
  class IncomingActionJob < ApplicationJob
    queue_as :captain_hook_incoming

    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    # Process a specific action for an incoming event
    # @param action_id [String] UUID of the IncomingEventAction
    # @param worker_id [String] Unique identifier for this worker
    def perform(action_id, worker_id: SecureRandom.uuid)
      action = IncomingEventAction.find(action_id)
      event = action.incoming_event

      # Try to acquire lock
      return unless action.acquire_lock!(worker_id)

      # Get action configuration from database (falls back to registry)
      action_config = CaptainHook::Services::ActionLookup.find_action_config(
        provider: event.provider,
        event_type: event.event_type,
        action_class: action.action_class
      )

      return unless action_config

      # Instrument start
      Instrumentation.action_started(action, event: event)
      start_time = Time.current

      begin
        # Increment attempt count
        action.increment_attempts!

        # Execute action - resolve actual class name from stored format
        resolved_class_name = CaptainHook::Services::ActionDiscovery.resolve_action_class(action.action_class)
        action_class = resolved_class_name.constantize
        action_instance = action_class.new

        # Call webhook_action method with event payload
        action_instance.webhook_action(event: event, payload: event.payload, metadata: event.metadata)

        # Mark as processed
        action.mark_processed!

        # Update event status
        event.recalculate_status!

        # Instrument completion
        duration = (Time.current - start_time).to_f
        Instrumentation.action_completed(action, duration: duration)
      rescue StandardError => e
        # Mark as failed
        action.mark_failed!(e)

        # Instrument failure
        Instrumentation.action_failed(action, error: e)

        # Check if we should retry
        if action.max_attempts_reached?(action_config.max_attempts)
          # Max attempts reached, don't retry
          event.recalculate_status!
        else
          # Schedule retry with backoff
          delay = action_config.delay_for_attempt(action.attempt_count)
          action.reset_for_retry!
          self.class.set(wait: delay.seconds).perform_later(action_id, worker_id: SecureRandom.uuid)
        end

        # Re-raise to mark job as failed
        raise
      end
    end
  end
end
