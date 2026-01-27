# Action Discovery and Registration

## Overview

CaptainHook uses an **automatic action discovery system** that scans your filesystem for action classes and registers them with the system. Actions are discovered at application boot and synced to the database, where they can be managed and executed when matching webhook events arrive.

## Key Concepts

- **Action**: A Ruby class that processes a specific webhook event type
- **Action Discovery**: Automatic scanning of `captain_hook/<provider>/actions/` directories for action classes
- **Action Registry**: In-memory registry that holds action configurations (used as fallback)
- **Action Sync**: Process that syncs discovered actions to the database
- **Action Lookup**: Service that finds actions (database-first, with registry fallback)

## How Action Discovery Works

### Discovery Process

1. **Application Boot**: When Rails starts, CaptainHook automatically scans for actions
2. **Filesystem Scan**: Searches all load paths for `captain_hook/<provider>/actions/**/*.rb` files
3. **Class Loading**: Loads action files and finds action classes
4. **Metadata Extraction**: Reads action metadata from the `.details` class method
5. **Database Sync**: Creates or updates `Action` records in the database

### Discovery Flow

```
Application Boot
    ↓
Engine Initializer
    ↓
ActionDiscovery.new.call
    ↓
┌─────────────────────────────────────┐
│ Scan Rails.root/captain_hook/       │
│ - Find stripe/actions/*.rb          │
│ - Load action classes               │
│ - Extract metadata from .details    │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ Scan All Loaded Gems                │
│ - Check $LOAD_PATH for actions      │
│ - Find captain_hook/*/actions/*.rb  │
│ - Load and extract metadata         │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│ Sync to Database (ActionSync)       │
│ - Create new Action records         │
│ - Update existing Action records    │
│ - Skip soft-deleted actions         │
└─────────────────────────────────────┘
    ↓
Actions Ready to Execute
```

## Action File Structure

### Directory Structure

Actions must be placed in the correct directory structure to be discovered:

```
captain_hook/
└── <provider_name>/
    └── actions/
        ├── <event_name>_action.rb
        ├── <another_event>_action.rb
        └── subdirectory/           # Subdirectories are supported
            └── <more_actions>.rb
```

### Example Structure

```
captain_hook/
└── stripe/
    └── actions/
        ├── payment_intent_created_action.rb
        ├── payment_intent_succeeded_action.rb
        ├── charge_refunded_action.rb
        └── subscriptions/
            ├── subscription_created_action.rb
            └── subscription_cancelled_action.rb
```

## Creating an Action Class

### Basic Action Template

```ruby
# captain_hook/stripe/actions/payment_intent_created_action.rb
module Stripe
  class PaymentIntentCreatedAction
    # Required: Define action metadata
    def self.details
      {
        event_type: "payment_intent.created",
        description: "Process new payment intents",
        priority: 100,           # Lower = higher priority (default: 100)
        async: true,             # Run in background job (default: true)
        max_attempts: 5,         # Number of retry attempts (default: 5)
        retry_delays: [30, 60, 300, 900, 3600]  # Retry delays in seconds (optional)
      }
    end

    # Required: Process the webhook event
    def webhook_action(event:, payload:, metadata: {})
      # event: CaptainHook::IncomingEvent record
      # payload: Parsed JSON payload as Hash
      # metadata: Additional metadata (reserved for future use)
      
      payment_intent_id = payload.dig("data", "object", "id")
      amount = payload.dig("data", "object", "amount")
      
      Rails.logger.info "Processing payment intent: #{payment_intent_id}"
      
      # Your business logic here
      # - Create/update records
      # - Send notifications
      # - Trigger other processes
    end
  end
end
```

### Action Metadata (`.details` method)

The `.details` class method must return a hash with the following fields:

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `event_type` | String | **Yes** | N/A | Event type to match (e.g., `"payment_intent.created"`) |
| `description` | String | No | `nil` | Human-readable description |
| `priority` | Integer | No | `100` | Execution priority (lower = higher priority) |
| `async` | Boolean | No | `true` | Whether to run in background job |
| `max_attempts` | Integer | No | `5` | Maximum retry attempts on failure |
| `retry_delays` | Array | No | `[30, 60, 300, 900, 3600]` | Retry delays in seconds |

### Event Type Matching

Actions can match specific events or use wildcards:

```ruby
# Exact match
def self.details
  { event_type: "payment_intent.created" }
end

# Wildcard match (all payment_intent.* events)
def self.details
  { event_type: "payment_intent.*" }
end

# Match all events for a provider
def self.details
  { event_type: "*" }
end
```

**Note**: Multiple actions can match the same event. They will be executed in priority order.

### Priority and Execution Order

When multiple actions match an event, they execute in order:

1. **Priority** (ascending): Lower numbers run first
2. **Action Class Name** (alphabetically): For deterministic ordering when priorities are equal

```ruby
# Runs first (priority 50)
class HighPriorityAction
  def self.details
    { event_type: "payment.created", priority: 50 }
  end
end

# Runs second (priority 100, default)
class NormalPriorityAction
  def self.details
    { event_type: "payment.created" }
  end
end

# Runs last (priority 200)
class LowPriorityAction
  def self.details
    { event_type: "payment.created", priority: 200 }
  end
end
```

## Naming Conventions

### Module Namespace

Actions **must** be namespaced under a module matching the provider name:

```ruby
# ✅ CORRECT: Namespaced under provider module
module Stripe
  class PaymentIntentAction
    # ...
  end
end

# ❌ WRONG: Not namespaced
class StripePaymentIntentAction
  # ...
end
```

### File Naming

File names should follow this pattern:

- Use snake_case
- Typically end with `_action.rb`
- Should match the class name (snake_cased)

```
payment_intent_created_action.rb  → Stripe::PaymentIntentCreatedAction
charge_refunded_action.rb         → Stripe::ChargeRefundedAction
webhook_handler.rb                → Stripe::WebhookHandler (custom name)
```

### Provider Detection

The provider is automatically detected from the directory structure:

```
captain_hook/stripe/actions/...    → Provider: "stripe"
captain_hook/github/actions/...    → Provider: "github"
captain_hook/custom_api/actions/...→ Provider: "custom_api"
```

## Gem-Based Actions

### Creating Actions in Gems

Gems can provide webhook actions by including `captain_hook/<provider>/actions/` directories:

```
your_gem/
├── lib/
│   └── your_gem.rb
└── captain_hook/
    └── stripe/
        └── actions/
            ├── payment_intent_action.rb
            └── charge_action.rb
```

### Gem Action Namespacing

Actions from gems are automatically namespaced to prevent conflicts:

```ruby
# In your gem: captain_hook/stripe/actions/payment_action.rb
module Stripe
  class PaymentAction
    def self.details
      { event_type: "payment.created" }
    end
    # ...
  end
end
```

**Stored in database as**: `YourGem::Stripe::PaymentAction`

This allows multiple gems to provide actions for the same event without conflicts.

### Host App vs Gem Precedence

When both a gem and the host application provide actions for the same event:

- **Both actions execute** (they don't override each other)
- Execution order is determined by **priority**, not source
- You can disable a gem's action by soft-deleting it in the admin UI

## Action Discovery Locations

The discovery system searches for actions in these locations (in order):

### 1. Rails Root Directory

```
Rails.root/captain_hook/<provider>/actions/**/*.rb
```

Example: `/app/captain_hook/stripe/actions/payment_action.rb`

### 2. Ruby Load Path ($LOAD_PATH)

```
$LOAD_PATH[*]/captain_hook/<provider>/actions/**/*.rb
```

Includes directories added by gems via `lib/` directories.

### 3. Loaded Gem Directories

```
Gem.loaded_specs[*].full_gem_path/captain_hook/<provider>/actions/**/*.rb
```

All gems with `captain_hook/` directories are scanned.

## Manual Action Registration

While automatic discovery is recommended, you can also manually register actions:

### Using Configuration Block

```ruby
# config/initializers/captain_hook.rb
CaptainHook.configure do |config|
  config.action_registry.register(
    provider: "stripe",
    event_type: "payment_intent.succeeded",
    action_class: "Stripe::PaymentIntentSucceededAction",
    async: true,
    priority: 100,
    max_attempts: 5,
    retry_delays: [30, 60, 300, 900, 3600]
  )
end
```

### Using Convenience Method

```ruby
# config/initializers/captain_hook.rb
CaptainHook.register_action(
  provider: "stripe",
  event_type: "charge.failed",
  action_class: "Stripe::ChargeFailedAction",
  async: true,
  priority: 50
)
```

**Note**: Manually registered actions:
- Are stored in the **in-memory registry only** (not synced to database)
- Will be used as fallback if no database records exist
- Won't appear in the admin UI unless manually created in the database

## Action Lookup (Runtime)

When a webhook arrives, CaptainHook looks up actions using **ActionLookup** service:

### Lookup Priority

1. **Database (Active Actions)**: Check for active actions in database
2. **Skip if Soft-Deleted**: If deleted records exist, respect deletion (don't fall back)
3. **Registry Fallback**: If no database records at all, fall back to in-memory registry

```ruby
# Internal lookup process
actions = ActionLookup.actions_for(
  provider: "stripe",
  event_type: "payment_intent.created"
)

# Returns ActionConfig objects ready for execution
```

### Soft-Delete Behavior

When you delete an action through the admin UI:

- The action is **soft-deleted** (marked as `deleted_at`)
- The action **will not execute** even if discovered in code
- Discovery won't re-create the action
- Registry fallback is disabled for that specific action

**To restore**: Manually update the database or use the admin UI

## Triggering Manual Discovery

### Rescan Actions

Force a re-scan of the filesystem and sync to database:

```ruby
# In Rails console or code
CaptainHook::Engine.sync_actions
```

This will:
- Scan all action files
- Create new Action records
- Update existing Action records
- Skip soft-deleted actions
- Log results

### Discovery Service (Low-Level)

For discovery without database sync:

```ruby
# Returns array of action definition hashes
action_definitions = CaptainHook::Services::ActionDiscovery.new.call

action_definitions.each do |definition|
  puts "#{definition['provider']}:#{definition['event']} → #{definition['action']}"
end

# Example output:
# stripe:payment_intent.created → Stripe::PaymentIntentCreatedAction
# stripe:charge.refunded → Stripe::ChargeRefundedAction
```

## Database Schema

Actions are stored in the `captain_hook_actions` table:

| Column | Type | Description |
|--------|------|-------------|
| `provider` | String | Provider name (e.g., "stripe") |
| `event_type` | String | Event type (e.g., "payment_intent.created") |
| `action_class` | String | Full class name (e.g., "Stripe::PaymentIntentAction") |
| `async` | Boolean | Whether to run asynchronously |
| `max_attempts` | Integer | Maximum retry attempts |
| `priority` | Integer | Execution priority (lower = first) |
| `retry_delays` | JSON | Array of retry delays in seconds |
| `deleted_at` | DateTime | Soft-delete timestamp |

**Unique Key**: `[provider, event_type, action_class]`

## Action Execution

When a webhook event arrives:

1. **Event Received**: Webhook is validated and saved as `IncomingEvent`
2. **Action Lookup**: Find all matching actions via ActionLookup
3. **Execution Records Created**: Create `IncomingEventAction` records
4. **Job Enqueue**: Enqueue background jobs for each action
5. **Retry Logic**: Failed actions retry based on `retry_delays` configuration

```
Webhook Arrives
    ↓
IncomingEvent Created
    ↓
ActionLookup.actions_for(provider, event_type)
    ↓
Create IncomingEventAction Records
    ↓
Enqueue ProcessWebhookJob(s)
    ↓
Execute action.webhook_action(...)
    ↓
Mark as success/failed
    ↓
Retry if failed (up to max_attempts)
```

## Complete Example

### File: `captain_hook/stripe/actions/payment_intent_succeeded_action.rb`

```ruby
# frozen_string_literal: true

module Stripe
  class PaymentIntentSucceededAction
    # Define action metadata
    def self.details
      {
        event_type: "payment_intent.succeeded",
        description: "Process successful payment intents and update orders",
        priority: 100,
        async: true,
        max_attempts: 5,
        retry_delays: [30, 60, 300, 900, 3600]
      }
    end

    # Process the webhook event
    def webhook_action(event:, payload:, metadata: {})
      # Extract Stripe data
      payment_intent = payload.dig("data", "object")
      payment_intent_id = payment_intent["id"]
      amount = payment_intent["amount"]
      currency = payment_intent["currency"]
      
      # Log the event
      Rails.logger.info "💰 Payment succeeded: #{payment_intent_id}"
      Rails.logger.info "   Amount: #{amount} #{currency.upcase}"
      
      # Your business logic
      order = Order.find_by(stripe_payment_intent_id: payment_intent_id)
      
      if order
        order.update!(
          status: "paid",
          paid_at: Time.current,
          payment_amount: amount,
          payment_currency: currency
        )
        
        # Send confirmation email
        OrderMailer.payment_confirmation(order).deliver_later
        
        Rails.logger.info "   Order ##{order.id} marked as paid"
      else
        Rails.logger.warn "   No order found for payment intent #{payment_intent_id}"
      end
      
    rescue StandardError => e
      # Log the error - it will be retried automatically
      Rails.logger.error "❌ Failed to process payment intent: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Re-raise to trigger retry
      raise
    end
  end
end
```

### Application Boot

After placing the file, restart your application. You should see:

```
🔍 CaptainHook: Found 1 registered action(s)
✅ Created action: Stripe::PaymentIntentSucceededAction for stripe:payment_intent.succeeded
✅ CaptainHook: Synced actions - Created: 1, Updated: 0, Skipped: 0
```

### When Webhook Arrives

```
POST /captain_hook/stripe/:token
Content-Type: application/json
{
  "type": "payment_intent.succeeded",
  "data": {
    "object": {
      "id": "pi_123456",
      "amount": 5000,
      "currency": "usd"
    }
  }
}

→ IncomingEvent created
→ Found 1 matching action: Stripe::PaymentIntentSucceededAction
→ IncomingEventAction created
→ ProcessWebhookJob enqueued
→ webhook_action executed
→ Order marked as paid
→ Email sent
```

## Troubleshooting

### Action Not Discovered

**Problem**: Action file exists but isn't discovered

**Solutions**:
1. Check file is in correct directory: `captain_hook/<provider>/actions/**/*.rb`
2. Verify class is namespaced correctly: `module Stripe; class ActionName; end; end`
3. Ensure `.details` method exists and returns required fields
4. Check Rails logs for loading errors
5. Manually trigger discovery: `CaptainHook::Engine.sync_actions`

### Action Not Executing

**Problem**: Action discovered but doesn't execute for webhooks

**Solutions**:
1. Check `event_type` in `.details` matches webhook event type exactly
2. Verify action is active in database: `CaptainHook::Action.where(deleted_at: nil)`
3. Check action wasn't soft-deleted: `CaptainHook::Action.with_deleted.find_by(...)`
4. Review logs for execution errors
5. Verify webhook was received: `CaptainHook::IncomingEvent.last`

### Multiple Actions Execute

**Problem**: Multiple actions run for one event (unexpected)

**Explanation**: This is **by design**. Multiple actions can match one event:
- Specific event: `payment_intent.created`
- Wildcard: `payment_intent.*`
- Catch-all: `*`

**Solutions**:
- Use priority to control execution order
- Soft-delete unwanted actions in admin UI
- Use more specific event types

### Gem Actions Conflict

**Problem**: Gem action conflicts with host app action

**Solution**: Both will execute. Use priority to control order, or soft-delete the unwanted one.

## Best Practices

1. **Use Descriptive Names**: `PaymentIntentSucceededAction` > `PaymentAction`
2. **Namespace Correctly**: Always use provider module namespace
3. **Set Appropriate Priorities**: High-priority actions < 100, normal = 100, low > 100
4. **Handle Errors Gracefully**: Use begin/rescue, re-raise to trigger retry
5. **Log Meaningful Messages**: Include event ID, amounts, and actions taken
6. **Keep Actions Focused**: One action per event type (or use wildcards carefully)
7. **Test Actions Thoroughly**: Unit test the `webhook_action` method
8. **Use Idempotency**: Actions may be retried, ensure they're idempotent
9. **Leverage Async**: Use `async: true` for slow operations
10. **Document Event Types**: Comment what events the action handles

## See Also

- [Action Management](ACTION_MANAGEMENT.md) - Managing actions in the admin UI
- [TECHNICAL_PROCESS.md](../TECHNICAL_PROCESS.md) - Complete technical documentation
- [Provider Discovery](PROVIDER_DISCOVERY.md) - How providers are discovered
