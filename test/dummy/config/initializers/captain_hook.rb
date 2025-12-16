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

