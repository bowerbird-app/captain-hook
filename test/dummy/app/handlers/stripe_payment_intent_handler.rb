# Handler for Stripe payment_intent.* events
class StripePaymentIntentHandler
  # Called by the job system
  # @param event [CaptainHook::IncomingEvent] The incoming event
  # @param payload [Hash] The parsed JSON payload
  # @param metadata [Hash] Additional metadata
  def handle(event:, payload:, metadata: {})
    Rails.logger.info "💳 ========================================"
    Rails.logger.info "💳 STRIPE PAYMENT INTENT HANDLER EXECUTED"
    Rails.logger.info "💳 ========================================"
    Rails.logger.info "💳 Provider: #{event.provider}"
    Rails.logger.info "💳 Event Type: #{event.event_type}"
    Rails.logger.info "💳 Event ID: #{event.external_id}"
    Rails.logger.info "💳 Timestamp: #{event.created_at}"
    
    # Extract Stripe-specific data from payload
    payment_intent = payload.dig("data", "object")
    
    if payment_intent
      Rails.logger.info "💳 ----------------------------------------"
      Rails.logger.info "💳 Payment Intent ID: #{payment_intent['id']}"
      Rails.logger.info "💳 Amount: #{format_amount(payment_intent['amount'], payment_intent['currency'])}"
      Rails.logger.info "💳 Status: #{payment_intent['status']}"
      Rails.logger.info "💳 Customer: #{payment_intent['customer'] || 'guest'}"
      Rails.logger.info "💳 Description: #{payment_intent['description'] || 'N/A'}"
      
      # Show if it's a success event
      if event.event_type == "payment_intent.succeeded"
        Rails.logger.info "💳 ✅ PAYMENT SUCCESSFUL!"
        Rails.logger.info "💳 🎉 This is where you'd:"
        Rails.logger.info "💳    - Send receipt email"
        Rails.logger.info "💳    - Fulfill order"
        Rails.logger.info "💳    - Update user subscription"
        Rails.logger.info "💳    - Trigger analytics event"
      elsif event.event_type == "payment_intent.created"
        Rails.logger.info "💳 📝 Payment intent created, awaiting payment"
      elsif event.event_type == "payment_intent.payment_failed"
        Rails.logger.info "💳 ❌ Payment failed!"
        Rails.logger.info "💳 Last error: #{payment_intent.dig('last_payment_error', 'message')}"
      end
    end
    
    Rails.logger.info "💳 ========================================"
    Rails.logger.info "💳 Handler completed successfully!"
    Rails.logger.info "💳 ========================================"
    
    # Return success (no DB writes)
    true
  end

  private

  def format_amount(amount_cents, currency)
    amount_dollars = amount_cents / 100.0
    "#{currency.upcase} #{amount_dollars}"
  end
end

