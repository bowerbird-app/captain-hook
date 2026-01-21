# Handles Stripe charge.updated events in the dummy app
return if defined?(StripeChargeUpdatedAction)

class StripeChargeUpdatedAction
  def handle(event:, payload:, metadata:)
    Rails.logger.info "[DUMMY] charge.updated: #{payload.dig('data', 'object', 'id')}"
  end
end
