# frozen_string_literal: true

# Handles Stripe charge.updated events in the dummy app
module Stripe
  class ChargeUpdatedAction
    def self.details
      {
        description: "Handles Stripe charge.updated events",
        event_type: "charge.updated",
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
      Rails.logger.info "[DUMMY] charge.updated: #{payload.dig('data', 'object', 'id')}"
    end
  end
end
