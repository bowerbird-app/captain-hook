# Webhook Configuration

This test/dummy app uses a flexible configuration system that allows you to use either:
1. A config file for development/testing (convenient, no ENV vars needed)
2. Environment variables (for production or when you prefer)

## Default Behavior

By default, the app loads configuration from `config/webhook_config.yml`:

```yaml
development:
  webhook_site:
    token: "400efa14-c6e1-4e77-8a54-51e8c4026a5e"
    url: "https://webhook.site/83c6777b-45cf-40db-a013-7e8085db26d6"
```

This means you can start the app without setting any environment variables!

## Using Environment Variables

To use environment variables instead, set `USE_ENV_CONFIG=true`:

```bash
export USE_ENV_CONFIG=true
export WEBHOOK_SITE_TOKEN="your-token"
export WEBHOOK_SITE_URL="https://webhook.site/your-token"
```

## Production

In production, environment variables are **always** used, regardless of the `USE_ENV_CONFIG` setting. The config file is ignored.

## Configuration Locations

- **CaptainHook initializer**: `/config/initializers/captain_hook.rb`
  - Configures the incoming webhook provider and outgoing endpoint
  
- **WebhookTester controller**: `/app/controllers/webhook_tester_controller.rb`
  - Uses the same config for displaying webhook URLs in the UI

- **Config file**: `/config/webhook_config.yml`
  - Stores default values for development and test environments

## Customizing for Your Tests

Just edit `config/webhook_config.yml` with your webhook.site token:

```yaml
development:
  webhook_site:
    token: "your-new-token-here"
    url: "https://webhook.site/your-new-token-here"
```

No need to set environment variables or restart your shell!
