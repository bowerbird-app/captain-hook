# Handles Stripe charge.updated events in the dummy app
class StripeChargeUpdatedHandler
  def handle(event:, payload:, metadata:)
    Rails.logger.info "[DUMMY] charge.updated: #{payload.dig('data', 'object', 'id')}"
  end
end
