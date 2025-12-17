# Handler for Square bank_account.* events
class SquareBankAccountHandler
  # Called by the job system
  # @param event [CaptainHook::IncomingEvent] The incoming event
  # @param payload [Hash] The parsed JSON payload
  # @param metadata [Hash] Additional metadata
  def handle(event:, payload:, metadata: {})
    Rails.logger.info "🟦 ========================================"
    Rails.logger.info "🟦 SQUARE BANK ACCOUNT HANDLER EXECUTED"
    Rails.logger.info "🟦 ========================================"
    Rails.logger.info "🟦 Provider: #{event.provider}"
    Rails.logger.info "🟦 Event Type: #{event.event_type}"
    Rails.logger.info "🟦 Event ID: #{event.external_id}"
    Rails.logger.info "🟦 Timestamp: #{event.created_at}"
    
    # Extract Square-specific data from payload
    bank_account = payload.dig("data", "object", "bank_account")
    
    if bank_account
      Rails.logger.info "🟦 ----------------------------------------"
      Rails.logger.info "🟦 Bank Account ID: #{bank_account['id']}"
      Rails.logger.info "🟦 Account Type: #{bank_account['account_type']}"
      Rails.logger.info "🟦 Bank Name: #{bank_account['bank_name']}"
      Rails.logger.info "🟦 Holder Name: #{bank_account['holder_name']}"
      Rails.logger.info "🟦 Last 4: #{bank_account['account_number_suffix']}"
      Rails.logger.info "🟦 Status: #{bank_account['status']}"
      Rails.logger.info "🟦 Currency: #{bank_account['currency']}"
      Rails.logger.info "🟦 Creditable: #{bank_account['creditable']}"
      Rails.logger.info "🟦 Debitable: #{bank_account['debitable']}"
      
      # Show different messages based on event type
      case event.event_type
      when "bank_account.verified"
        Rails.logger.info "🟦 ✅ BANK ACCOUNT VERIFIED!"
        Rails.logger.info "🟦 🎉 This account can now be used for:"
        Rails.logger.info "🟦    - Receiving payments (creditable: #{bank_account['creditable']})"
        Rails.logger.info "🟦    - Making payouts (debitable: #{bank_account['debitable']})"
        Rails.logger.info "🟦    - Process refunds"
        Rails.logger.info "🟦    - Update customer records"
      when "bank_account.created"
        Rails.logger.info "🟦 📝 Bank account created, verification pending"
      when "bank_account.disabled"
        Rails.logger.info "🟦 ⛔ Bank account disabled"
      when "bank_account.updated"
        Rails.logger.info "🟦 🔄 Bank account updated"
      end
    end
    
    Rails.logger.info "🟦 ========================================"
    Rails.logger.info "🟦 Handler completed successfully!"
    Rails.logger.info "🟦 ========================================"
    
    # Return success (no DB writes)
    true
  end
end
