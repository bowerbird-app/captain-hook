# Webhook Tester

The Webhook Tester is a simple utility page in the dummy app for testing CaptainHook's incoming and outgoing webhook functionality.

## Access

Navigate to: `/webhook_tester`

## Features

### 1. Incoming Webhook Testing
Test webhooks being received by the CaptainHook engine.

- **Provider**: The webhook provider name (e.g., "stripe", "github")
- **Token**: Authentication token for the webhook
- **Payload**: JSON payload to send

The form will send a POST request to: `http://localhost:3000/captain_hook/{provider}/{token}`

### 2. Outgoing Webhook Testing
Test sending webhooks to external services (webhook.site).

- **Payload**: JSON payload to send

The form will send a POST request to the configured webhook.site URL.

## Configuration

Webhook.site credentials are currently hardcoded in `WebhookTesterController::WEBHOOK_CONFIG`:

```ruby
WEBHOOK_CONFIG = {
  unique_url: "https://webhook.site/83c6777b-45cf-40db-a013-7e8085db26d6",
  email_address: "83c6777b-45cf-40db-a013-7e8085db26d6@emailhook.site",
  dns_name: "83c6777b-45cf-40db-a013-7e8085db26d6.dnshook.site",
  token: "83c6777b-45cf-40db-a013-7e8085db26d6"
}
```

**TODO**: Move these to environment variables or Rails credentials for production use.

## Styling

The page uses MakeupArtist gem styling conventions with CSS custom properties:
- `--ma-color-brand`: Primary brand color
- `--ma-color-accent`: Accent color for links and highlights
- `--ma-color-bg`: Background color
- `--ma-color-text`: Text color
- `--ma-radius-*`: Border radius tokens
- `--ma-shadow-card`: Card shadow

This ensures consistency with the rest of the application's UI.

## Quick Links

The page provides quick access to:
- CaptainHook Admin Interface
- Webhook.site Dashboard
- MakeupArtist Style Guide

## Usage Example

1. Start the server: `cd test/dummy && bin/dev`
2. Navigate to: `http://localhost:3000/webhook_tester`
3. To test an incoming webhook:
   - Fill in provider name (e.g., "stripe")
   - Fill in token (e.g., "secret_token_123")
   - Edit the JSON payload as needed
   - Click "Send Incoming Webhook"
   - Check the CaptainHook admin interface to see the received webhook
4. To test an outgoing webhook:
   - Edit the JSON payload as needed
   - Click "Send Outgoing Webhook"
   - Visit the webhook.site URL shown on the page to see the received request
