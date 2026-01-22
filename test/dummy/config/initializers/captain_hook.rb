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

# Actions are now automatically discovered from the filesystem!
# CaptainHook scans captain_hook/<provider>/actions/**/*.rb directories
# and registers actions based on their self.details method.
#
# No manual registration needed - just create action files with:
#   - Proper namespacing (e.g., module Stripe; class PaymentIntentAction)
#   - A self.details class method returning event_type, priority, async, etc.
#
# See action files in captain_hook/stripe/actions/ for examples.

