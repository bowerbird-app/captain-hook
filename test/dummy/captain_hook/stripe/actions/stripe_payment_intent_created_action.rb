# frozen_string_literal: true

# Handles Stripe payment_intent.created events in the dummy app
module Stripe
  class PaymentIntentCreatedAction
    def self.details
      {
        description: "Handles Stripe payment_intent.created events",
        event_type: "payment_intent.created",
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
      Rails.logger.info "[DUMMY] payment_intent.created: #{payload.dig('data', 'object', 'id')}"
    end
  end
end
