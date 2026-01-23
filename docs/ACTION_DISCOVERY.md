# Action Discovery System

## Overview

CaptainHook uses automatic filesystem scanning to discover webhook action handlers. This eliminates the need for manual action registration and makes it easier to add new webhook handlers.

## How It Works

### 1. Boot-Time Scanning

When your Rails application boots, CaptainHook automatically scans for action files in all load paths:

```
captain_hook/<provider>/actions/**/*.rb
```

This includes:
- Host application files (e.g., `/path/to/app/captain_hook/stripe/actions/*.rb`)
- Gem files (e.g., `/path/to/gems/my_gem/captain_hook/stripe/actions/*.rb`)

### 2. Action Structure

Each action file must:
1. Define a class namespaced under the provider name
2. Include a `self.details` class method
3. Include a `webhook_action` instance method

Example:
```ruby
# captain_hook/stripe/actions/payment_succeeded_action.rb
module Stripe
  class PaymentSucceededAction
    # REQUIRED: Metadata for discovery
    def self.details
      {
        description: "Handles Stripe payment succeeded events",
        event_type: "payment.succeeded",  # REQUIRED
        priority: 100,                    # Optional (default: 100)
        async: true,                      # Optional (default: true)
        max_attempts: 5,                  # Optional (default: 5)
        retry_delays: [30, 60, 300]      # Optional (default: [30, 60, 300, 900, 3600])
      }
    end

    # REQUIRED: Webhook processing method
    def webhook_action(event:, payload:, metadata:)
      # Your business logic here
    end
  end
end
```

### 3. Class Name Transformation

When storing actions in the database, class names are transformed:

**From gems or engines:**
- Input: `CaptainHook::Stripe::Actions::PaymentSucceededAction`
- Stored: `Stripe::PaymentSucceededAction`
- Removes: `CaptainHook::` prefix and `::Actions::` namespace

**From host applications:**
- Input: `Stripe::PaymentSucceededAction`
- Stored: `Stripe::PaymentSucceededAction`
- No transformation needed

**The transformation ensures consistent naming regardless of where the action is defined.**

### 4. Provider Extraction

The provider name is extracted from the directory structure:

```
captain_hook/stripe/actions/payment_action.rb  → provider: "stripe"
captain_hook/paypal/actions/payment_action.rb  → provider: "paypal"
captain_hook/square/actions/payment_action.rb  → provider: "square"
```

### 5. Database Synchronization

After discovery, actions are synced to the `captain_hook_actions` table:

```ruby
CaptainHook::Action.create!(
  provider: "stripe",
  event_type: "payment.succeeded",
  action_class: "Stripe::PaymentSucceededAction",
  priority: 100,
  async: true,
  max_attempts: 5,
  retry_delays: [30, 60, 300, 900, 3600]
)
```

## File Naming Conventions

### File Names
Files should be in snake_case and end with `_action.rb`:

✅ Good:
- `payment_succeeded_action.rb`
- `charge_updated_action.rb`
- `invoice_payment_failed_action.rb`

❌ Bad:
- `PaymentSucceededAction.rb` (PascalCase)
- `payment_succeeded.rb` (missing `_action`)
- `payment-succeeded-action.rb` (hyphens)

### Class Names
Classes should be in PascalCase and match the file name:

✅ Good:
- File: `payment_succeeded_action.rb` → Class: `PaymentSucceededAction`
- File: `charge_updated_action.rb` → Class: `ChargeUpdatedAction`

❌ Bad:
- File: `payment_succeeded_action.rb` → Class: `PaymentSucceeded`
- File: `payment_succeeded_action.rb` → Class: `payment_succeeded_action`

### Provider Prefix in File Names

**You can optionally prefix file names with the provider name**, but it will be stripped when determining the class name:

✅ Both work:
- `stripe_payment_action.rb` → expects `class PaymentAction`
- `payment_action.rb` → expects `class PaymentAction`

The discovery system automatically removes the provider prefix if present.

## Event Type Wildcards

Actions can use wildcards to match multiple event types:

```ruby
module Square
  class BankAccountAction
    def self.details
      {
        event_type: "bank_account.*",  # Matches bank_account.created, bank_account.verified, etc.
        priority: 100,
        async: true
      }
    end

    def webhook_action(event:, payload:, metadata:)
      # event.event_type contains the specific event (e.g., "bank_account.verified")
      case event.event_type
      when "bank_account.created"
        # Handle created
      when "bank_account.verified"
        # Handle verified
      end
    end
  end
end
```

## Discovery Process Flow

```
1. Rails Boot
   ↓
2. CaptainHook::Engine initializer runs
   ↓
3. ActionDiscovery.new.call scans filesystem
   ↓
4. For each action file:
   - Extract provider from path
   - Require the file
   - Find the action class
   - Call .details to get metadata
   - Transform class name
   - Create action definition hash
   ↓
5. ActionSync.new(definitions).call syncs to database
   ↓
6. Actions are ready to process webhooks
```

## Debugging Discovery

### Enable Debug Logging

In your Rails console or initializer:
```ruby
# config/initializers/captain_hook.rb
Rails.logger.level = :debug
```

You'll see messages like:
```
🔍 CaptainHook: Auto-scanning providers and actions...
✅ Discovered action: Stripe::PaymentSucceededAction for stripe:payment.succeeded
✅ Discovered action: Square::BankAccountAction for square:bank_account.*
✅ CaptainHook: Synced actions - Created: 2, Updated: 0, Skipped: 0
```

### Manual Discovery

You can manually trigger discovery in the Rails console:

```ruby
# Discover all actions
discovery = CaptainHook::Services::ActionDiscovery.new
definitions = discovery.call

# View discovered actions
definitions.each do |defn|
  puts "#{defn['provider']}:#{defn['event']} → #{defn['action']}"
end

# Sync to database
sync = CaptainHook::Services::ActionSync.new(definitions, update_existing: true)
results = sync.call

puts "Created: #{results[:created].count}"
puts "Updated: #{results[:updated].count}"
puts "Skipped: #{results[:skipped].count}"
```

### Check Discovered Actions

```ruby
# View all actions in database
CaptainHook::Action.all.each do |action|
  puts "#{action.provider}:#{action.event_type} → #{action.action_class}"
end

# Check specific provider
CaptainHook::Action.where(provider: "stripe")

# Check specific event type
CaptainHook::Action.where(event_type: "payment.succeeded")
```

## Common Issues

### Action not discovered

**Symptom:** Action file exists but doesn't appear in `CaptainHook::Action.all`

**Causes:**
1. File not in `captain_hook/<provider>/actions/` directory
2. Missing `self.details` method
3. Missing `:event_type` in details hash
4. Class not properly namespaced
5. File not loaded (check `$LOAD_PATH`)
6. Server not restarted after creating file

**Solution:**
```bash
# Restart Rails server
bin/rails restart

# Or manually trigger discovery in console
CaptainHook::Engine.sync_actions
```

### Wrong class name

**Symptom:** Error like "Could not find class Stripe::StripePaymentAction"

**Cause:** File name doesn't match class name

**Example:**
```ruby
# ❌ BAD
# File: stripe_payment_action.rb
module Stripe
  class PaymentAction  # Wrong! Should be StripePaymentAction or just PaymentAction
  end
end

# ✅ GOOD - Option 1: Include provider in class name
# File: stripe_payment_action.rb  
module Stripe
  class StripePaymentAction
  end
end

# ✅ GOOD - Option 2: Omit provider from file name
# File: payment_action.rb
module Stripe
  class PaymentAction
  end
end
```

### Namespace error

**Symptom:** Error like "uninitialized constant Stripe"

**Cause:** Missing provider module

**Solution:**
```ruby
# ❌ BAD
class PaymentAction  # Not namespaced!
end

# ✅ GOOD
module Stripe
  class PaymentAction
  end
end
```

## Migration Guide

### From Manual Registration

**Old way (manual registration):**
```ruby
# lib/your_gem/engine.rb
config.after_initialize do
  CaptainHook.register_action(
    provider: "stripe",
    event_type: "payment.succeeded",
    action_class: "YourGem::Webhooks::PaymentSucceededAction",
    priority: 100,
    async: true,
    max_attempts: 3
  )
end
```

**New way (automatic discovery):**
```ruby
# captain_hook/stripe/actions/payment_succeeded_action.rb
module Stripe
  class PaymentSucceededAction
    def self.details
      {
        event_type: "payment.succeeded",
        priority: 100,
        async: true,
        max_attempts: 3
      }
    end

    def webhook_action(event:, payload:, metadata:)
      # Same business logic as before
    end
  end
end
```

### Steps to Migrate

1. **Create action files** in `captain_hook/<provider>/actions/`
2. **Add `self.details` method** to each action class
3. **Namespace classes** under provider module
4. **Remove registration calls** from initializers/engine files
5. **Restart server** to trigger discovery
6. **Verify** actions were discovered using Rails console

## Performance Considerations

### Boot Time Impact

Discovery runs once during Rails boot. Impact is minimal:
- ~1-5ms per action file to scan and load
- ~10-20ms for database sync
- Total: ~50-100ms for 10-20 actions

### Caching

Discovered actions are cached in the database. Changes require:
1. Restart Rails server, OR
2. Manual re-sync via `CaptainHook::Engine.sync_actions`

### Optimization Tips

1. **Keep action files small** - Only include webhook processing logic
2. **Use wildcards** when appropriate - Reduce number of action files
3. **Avoid heavy computations** in `self.details` - It's called during discovery
4. **Lazy load dependencies** - Don't require heavy gems at the top of action files

## Testing

### Testing Discovery

```ruby
# test/services/action_discovery_test.rb
require "test_helper"

class ActionDiscoveryTest < ActiveSupport::TestCase
  test "discovers stripe actions" do
    discovery = CaptainHook::Services::ActionDiscovery.new
    actions = discovery.call
    
    stripe_actions = actions.select { |a| a["provider"] == "stripe" }
    assert stripe_actions.size > 0
    
    payment_action = stripe_actions.find { |a| a["event"] == "payment.succeeded" }
    assert_equal "Stripe::PaymentSucceededAction", payment_action["action"]
  end
end
```

### Testing Actions

```ruby
# test/captain_hook/stripe/actions/payment_succeeded_action_test.rb
require "test_helper"

class Stripe::PaymentSucceededActionTest < ActiveSupport::TestCase
  test "has required details" do
    details = Stripe::PaymentSucceededAction.details
    
    assert details[:event_type].present?
    assert details[:priority].present?
  end

  test "processes payment succeeded webhook" do
    action = Stripe::PaymentSucceededAction.new
    event = captain_hook_incoming_events(:stripe_payment_succeeded)
    
    result = action.webhook_action(
      event: event,
      payload: JSON.parse(event.payload),
      metadata: {}
    )
    
    assert result
  end
end
```

## Best Practices

1. **One action per event type** - Keep actions focused
2. **Use descriptive class names** - `PaymentSucceededAction` not `PSA`
3. **Document business logic** - Comment what the action does
4. **Handle errors gracefully** - Use rescue blocks for external API calls
5. **Log important events** - Use Rails.logger for visibility
6. **Keep actions idempotent** - Actions may be retried
7. **Validate payloads** - Check for required fields before processing
8. **Use transactions** - For database operations
9. **Test thoroughly** - Both happy path and error cases
10. **Monitor performance** - Track action execution times
