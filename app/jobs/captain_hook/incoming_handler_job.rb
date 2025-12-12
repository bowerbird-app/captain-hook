# frozen_string_literal: true

module CaptainHook
  # Job to process incoming webhook event handlers
  # Supports retry logic, priority ordering, and optimistic locking
  class IncomingHandlerJob < ApplicationJob
    queue_as :captain_hook_incoming

    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    # Process a specific handler for an incoming event
    # @param handler_id [String] UUID of the IncomingEventHandler
    # @param worker_id [String] Unique identifier for this worker
    def perform(handler_id, worker_id: SecureRandom.uuid)
      handler = IncomingEventHandler.find(handler_id)
      event = handler.incoming_event

      # Try to acquire lock
      return unless handler.acquire_lock!(worker_id)

      # Get handler configuration from registry
      handler_config = CaptainHook.handler_registry.find_handler_config(
        provider: event.provider,
        event_type: event.event_type,
        handler_class: handler.handler_class
      )

      return unless handler_config

      # Instrument start
      Instrumentation.handler_started(handler, event: event)
      start_time = Time.current

      begin
        # Increment attempt count
        handler.increment_attempts!

        # Execute handler
        handler_class = handler.handler_class.constantize
        handler_instance = handler_class.new
        
        # Call handle method with event payload
        handler_instance.handle(event: event, payload: event.payload, metadata: event.metadata)

        # Mark as processed
        handler.mark_processed!

        # Update event status
        event.recalculate_status!

        # Instrument completion
        duration = (Time.current - start_time).to_f
        Instrumentation.handler_completed(handler, duration: duration)

      rescue StandardError => e
        # Mark as failed
        handler.mark_failed!(e)

        # Instrument failure
        Instrumentation.handler_failed(handler, error: e)

        # Check if we should retry
        if handler.max_attempts_reached?(handler_config.max_attempts)
          # Max attempts reached, don't retry
          event.recalculate_status!
        else
          # Schedule retry with backoff
          delay = handler_config.delay_for_attempt(handler.attempt_count)
          handler.reset_for_retry!
          self.class.set(wait: delay.seconds).perform_later(handler_id, worker_id: SecureRandom.uuid)
        end

        # Re-raise to mark job as failed
        raise
      end
    end
  end
end
