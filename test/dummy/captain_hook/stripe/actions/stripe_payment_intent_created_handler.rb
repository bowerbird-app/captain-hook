# Handles Stripe payment_intent.created events in the dummy app
class StripePaymentIntentCreatedHandler
  def handle(event:, payload:, metadata:)
    Rails.logger.info "[DUMMY] payment_intent.created: #{payload.dig('data', 'object', 'id')}"
  end
end
