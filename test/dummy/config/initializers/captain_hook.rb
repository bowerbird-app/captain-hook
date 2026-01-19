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
#   provider.verifier_class = "CaptainHook::Verifiers::Stripe"
#   provider.timestamp_tolerance_seconds = 300
#   provider.rate_limit_requests = 100
#   provider.rate_limit_period = 60
#   provider.active = true
# end

# Register actions for webhook processing
Rails.application.config.after_initialize do
  # Action for webhook.site test events
  # To trigger this, send a webhook with: { "type": "test", ... }
  # Or: { "event_type": "test", ... }
  # Or: { "event": "test", ... }
  CaptainHook.register_action(
    provider: "webhook_site",
    event_type: "test",
    action_class: "WebhookSiteTestAction",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  # Action for Square bank_account events
  # Handles: bank_account.created, bank_account.verified, bank_account.disabled, bank_account.updated
  CaptainHook.register_action(
    provider: "square",
    event_type: "bank_account.created",
    action_class: "SquareBankAccountAction",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  CaptainHook.register_action(
    provider: "square",
    event_type: "bank_account.verified",
    action_class: "SquareBankAccountAction",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  CaptainHook.register_action(
    provider: "square",
    event_type: "bank_account.disabled",
    action_class: "SquareBankAccountAction",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  CaptainHook.register_action(
    provider: "square",
    event_type: "bank_account.updated",
    action_class: "SquareBankAccountAction",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  # Explicit registrations for dummy app Stripe actions
  CaptainHook.register_action(
    provider: "stripe",
    event_type: "payment_intent.created",
    action_class: "StripePaymentIntentCreatedAction",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  CaptainHook.register_action(
    provider: "stripe",
    event_type: "charge.updated",
    action_class: "StripeChargeUpdatedAction",
    priority: 100,
    async: true,
    max_attempts: 3
  )

  Rails.logger.info "🎣 Registered WebhookSiteTestAction for webhook_site:test events"
  Rails.logger.info "💳 Registered StripePaymentIntentAction for stripe payment_intent.* events"
  Rails.logger.info "🟦 Registered SquareBankAccountAction for square bank_account.* events"
end

