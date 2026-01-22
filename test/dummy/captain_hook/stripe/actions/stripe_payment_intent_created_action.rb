# Handles Stripe payment_intent.created events in the dummy app
return if defined?(StripePaymentIntentCreatedAction)

class StripePaymentIntentCreatedAction
  def webhook_action(event:, payload:, metadata:)
    Rails.logger.info "[DUMMY] payment_intent.created: #{payload.dig('data', 'object', 'id')}"
  end
end
