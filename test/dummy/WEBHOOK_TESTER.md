# Webhook Tester

The Webhook Tester is a simple utility page in the dummy app for testing CaptainHook's incoming and outgoing webhook functionality.

## Access

Navigate to: `/webhook_tester`

## Features

### 1. Incoming Webhook Testing
Test webhooks being received by the CaptainHook engine.

- **Provider**: The webhook provider name (defaults to "webhook_site")
- **Token**: Authentication token (auto-populated from config)
- **Payload**: JSON payload to send

The form sends a POST request to: `http://localhost:3004/captain_hook/{provider}/{token}`

**Note**: Uses localhost to avoid GitHub Codespaces port visibility issues.

### 2. Outgoing Webhook Testing
Send webhooks to external services (webhook.site) using CaptainHook's OutgoingEvent system.

- **Payload**: JSON payload to send

Creates an `OutgoingEvent` record and enqueues `OutgoingJob` for asynchronous delivery. The webhook and its delivery status will be visible in the CaptainHook admin interface.

## Configuration

The app uses a flexible configuration system that loads from either:

### Option 1: Config File (Default for Development/Test)

Edit `config/webhook_config.yml`:

```yaml
development:
  webhook_site:
    token: "400efa14-c6e1-4e77-8a54-51e8c4026a5e"
    url: "https://webhook.site/83c6777b-45cf-40db-a013-7e8085db26d6"
```

**Benefit**: No environment variables needed! Just edit the file and restart.

### Option 2: Environment Variables

Set `USE_ENV_CONFIG=true` to use environment variables:

```bash
export USE_ENV_CONFIG=true
export WEBHOOK_SITE_TOKEN="your-token"
export WEBHOOK_SITE_URL="https://webhook.site/your-token"
```

### Production

In production, environment variables are **always** used, regardless of the config file.

See `config/WEBHOOK_CONFIG.md` for detailed documentation.

## Styling

The page uses Tailwind CSS with custom CSS properties for theming:
- `--ma-color-brand`: Primary brand color
- `--ma-color-accent`: Accent color for links and highlights
- `--ma-color-bg`: Background color
- `--ma-color-text`: Text color
- `--ma-radius-*`: Border radius tokens
- `--ma-shadow-card`: Card shadow

Styles are consistent with the CaptainHook admin interface.

## Quick Links

The page provides quick access to:
- CaptainHook Admin Interface (`/captain_hook`)
- Webhook.site Dashboard (opens the configured webhook URL)

## Usage Example

1. Start the server: `cd test/dummy && bin/rails server -p 3004`
2. Navigate to: `http://localhost:3004/webhook_tester` (or via Codespaces forwarded port)
3. To test an incoming webhook:
   - Provider is pre-filled with "webhook_site"
   - Token is auto-populated from config
   - Edit the JSON payload as needed
   - Click "Send Incoming Webhook"
   - Check `/captain_hook/admin/incoming_events` to see the received webhook
4. To test an outgoing webhook:
   - Edit the JSON payload as needed
   - Click "Send Outgoing Webhook"
   - Check `/captain_hook/admin/outgoing_events` to see the queued event
   - Visit the webhook.site URL shown on the page to see the delivered request

## How It Works

### Incoming Webhooks
1. Form submits to `WebhookTesterController#send_incoming`
2. Controller makes HTTP POST to `http://localhost:3004/captain_hook/webhook_site/{token}`
3. `CaptainHook::IncomingController` receives and validates the webhook
4. Creates an `IncomingEvent` record in the database
5. Success/error message is displayed

### Outgoing Webhooks
1. Form submits to `WebhookTesterController#send_outgoing`
2. Controller creates an `OutgoingEvent` record with status "pending"
3. Enqueues `CaptainHook::OutgoingJob` for asynchronous delivery
4. Job processes and sends HTTP request to webhook.site
5. Updates `OutgoingEvent` status (delivered/failed)
6. View the event in `/captain_hook/admin/outgoing_events`
