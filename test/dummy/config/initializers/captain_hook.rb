# frozen_string_literal: true

CaptainHook.configure do |config|
  # Optional: Configure admin settings
  # config.admin_parent_controller = "ApplicationController"
  # config.retention_days = 90
end

# Providers are now managed via the database through the admin UI at:
# /captain_hook/admin/providers
#
# To create a provider programmatically (e.g., in a seed file):
#
# CaptainHook::Provider.find_or_create_by!(name: "stripe") do |provider|
#   provider.display_name = "Stripe"
#   provider.signing_secret = ENV["STRIPE_WEBHOOK_SECRET"]
#   provider.adapter_class = "CaptainHook::Adapters::Stripe"
#   provider.timestamp_tolerance_seconds = 300
#   provider.rate_limit_requests = 100
#   provider.rate_limit_period = 60
#   provider.active = true
# end

# Register handlers for webhook processing
Rails.application.config.after_initialize do
  # Handler for webhook.site test events
  # To trigger this, send a webhook with: { "type": "test", ... }
  # Or: { "event_type": "test", ... }
  # Or: { "event": "test", ... }
  CaptainHook.register_handler(
    provider: "webhook_site",
    event_type: "test",
    handler_class: "WebhookSiteTestHandler",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  # Handler for Square bank_account events
  # Handles: bank_account.created, bank_account.verified, bank_account.disabled, bank_account.updated
  CaptainHook.register_handler(
    provider: "square",
    event_type: "bank_account.created",
    handler_class: "SquareBankAccountHandler",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  CaptainHook.register_handler(
    provider: "square",
    event_type: "bank_account.verified",
    handler_class: "SquareBankAccountHandler",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  CaptainHook.register_handler(
    provider: "square",
    event_type: "bank_account.disabled",
    handler_class: "SquareBankAccountHandler",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  CaptainHook.register_handler(
    provider: "square",
    event_type: "bank_account.updated",
    handler_class: "SquareBankAccountHandler",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  Rails.logger.info "🎣 Registered WebhookSiteTestHandler for webhook_site:test events"
  Rails.logger.info "💳 Registered StripePaymentIntentHandler for stripe payment_intent.* events"
  Rails.logger.info "🟦 Registered SquareBankAccountHandler for square bank_account.* events"
end

