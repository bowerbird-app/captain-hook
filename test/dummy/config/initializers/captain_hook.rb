# frozen_string_literal: true

CaptainHook.configure do |config|
  # Register webhook_site provider for incoming webhooks
  config.register_provider(
    "webhook_site",
    token: ENV["WEBHOOK_SITE_TOKEN"],
    adapter_class: "CaptainHook::Adapters::WebhookSite",
    timestamp_tolerance_seconds: 300,
    rate_limit_requests: 100,
    rate_limit_period: 60
  )

  # Register outgoing endpoint for webhook_site
  config.register_outgoing_endpoint(
    "webhook_site",
    base_url: ENV["WEBHOOK_SITE_URL"],
    signing_secret: nil,  # No signing for webhook.site
    default_headers: {
      "Content-Type" => "application/json",
      "User-Agent" => "CaptainHook/#{CaptainHook::VERSION}"
    }
  )
end
