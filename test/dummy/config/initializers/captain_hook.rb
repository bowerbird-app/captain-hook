# frozen_string_literal: true

# Load webhook configuration from file or environment
# Set USE_ENV_CONFIG=true to force using environment variables
use_env = ENV["USE_ENV_CONFIG"] == "true"

if use_env || Rails.env.production?
  # Use environment variables (production or when explicitly enabled)
  webhook_site_token = ENV["WEBHOOK_SITE_TOKEN"]
  webhook_site_url = ENV["WEBHOOK_SITE_URL"]
else
  # Use config file for development/test convenience
  config_file = Rails.root.join("config/webhook_config.yml")
  if File.exist?(config_file)
    webhook_config = YAML.load_file(config_file)[Rails.env]
    webhook_site_token = webhook_config.dig("webhook_site", "token")
    webhook_site_url = webhook_config.dig("webhook_site", "url")
  end
end

CaptainHook.configure do |config|
  # Register webhook_site provider for incoming webhooks
  config.register_provider(
    "webhook_site",
    token: webhook_site_token || "default-token-change-me",
    adapter_class: "CaptainHook::Adapters::WebhookSite",
    timestamp_tolerance_seconds: 300,
    rate_limit_requests: 100,
    rate_limit_period: 60
  )

  # Register outgoing endpoint for webhook_site
  config.register_outgoing_endpoint(
    "webhook_site",
    base_url: webhook_site_url || "https://webhook.site/default",
    signing_secret: nil,  # No signing for webhook.site
    default_headers: {
      "Content-Type" => "application/json",
      "User-Agent" => "CaptainHook/#{CaptainHook::VERSION}"
    }
  )
end
