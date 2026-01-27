# Action Management

## Overview

Action Management in CaptainHook involves viewing, editing, and controlling webhook actions through the admin interface and programmatically via the Rails console. Actions are stored in the database and can be modified at runtime without requiring code changes or application restarts (though discovery of new actions does require a restart).

## Key Concepts

- **Database Actions**: Actions synced from code to the database during application boot
- **Registry Actions**: In-memory actions registered via initializers (used as fallback)
- **Soft Delete**: Actions can be "deleted" without actually removing them, preventing execution
- **Priority Management**: Control execution order when multiple actions match an event
- **Retry Configuration**: Customize retry behavior for failed actions
- **Action Execution**: Monitor and track action processing through IncomingEventAction records

## Action Lifecycle

```
Action Discovered (code)
    ↓
Synced to Database
    ↓
Active in Database
    ↓
Webhook Event Arrives
    ↓
IncomingEventAction Created
    ↓
IncomingActionJob Enqueued
    ↓
Action Executed
    ↓
Marked as Success/Failed
    ↓
Retried if Failed (up to max_attempts)
```

## Admin UI Overview

### Accessing Actions

Navigate to actions through the admin UI:

1. Go to `/captain_hook/admin/providers`
2. Click on a provider (e.g., "Stripe")
3. Click "Actions" in the provider detail view
4. View all actions for that provider

**URL Pattern**: `/captain_hook/admin/providers/:provider_id/actions`

### Actions Index Page

The actions index shows two sections:

#### 1. Active Actions (Database)

Actions that are currently active and will execute for matching webhooks:

- **Action Class**: The Ruby class name (e.g., `Stripe::PaymentIntentSucceededAction`)
- **Event Type**: The event pattern (e.g., `payment_intent.succeeded` or `payment_intent.*`)
- **Incoming Events**: Count of received events (click to view events)
- **Edit**: Button to modify action settings

#### 2. Registered Actions (In-Memory Registry)

Actions registered in code but not yet synced to the database:

- Shows actions that will be created on next application restart
- Displays configuration from code (priority, async, max_attempts, retry_delays)
- Cannot be edited until synced to database

### Action States

Actions can be in one of three states:

1. **Active**: Normal state, will execute for matching webhooks
2. **Soft-Deleted**: Marked as deleted, won't execute, but record preserved
3. **Registry-Only**: Not yet synced to database, shows in "Registered Actions" section

## Managing Actions

### Viewing Action Details

Click on an action in the admin UI to view:

- Provider and event type
- Action class name
- Execution mode (async/sync)
- Priority level
- Max retry attempts
- Retry delay schedule
- Associated incoming events

### Editing Actions

Actions can be edited to customize their runtime behavior:

**Editable Fields**:
- Event type (change which events trigger this action)
- Execution mode (async vs sync)
- Priority (control execution order)
- Max attempts (number of retries)
- Retry delays (backoff schedule)

**Non-Editable Fields**:
- Provider (determined by action location)
- Action class (would break class mapping)

#### Edit Action Form

Navigate to: `/captain_hook/admin/providers/:provider_id/actions/:id/edit`

```
Event Type:     [payment_intent.succeeded    ]
                The webhook event type this action processes

Execution Mode: ⚫ Async (Run in background job)
                ⚪ Sync (Run immediately in request)
                
Priority:       [100                         ]
                Lower numbers execute first (e.g., 10 runs before 100)

Max Attempts:   [5                           ]
                Number of times to retry on failure (minimum 1)

Retry Delays:   [30, 60, 300, 900, 3600      ]
                Comma-separated list of delay times in seconds between retries
                Example: 30, 60, 300, 900, 3600 means wait 30s, then 60s, 
                then 5min, then 15min, then 1hr between retries
```

### Soft-Deleting Actions

Soft-delete prevents an action from executing without permanently removing it from the database.

**Why Soft Delete?**
- Preserves action history and configuration
- Prevents action from being re-created during next discovery
- Can be restored if needed
- Maintains referential integrity with IncomingEventAction records

**How to Soft Delete**:

1. Navigate to the action edit page
2. Scroll to the "Danger Zone" section
3. Click "Delete Action"
4. Confirm deletion

The action will be marked with `deleted_at` timestamp and:
- Won't execute for new webhooks
- Won't appear in active actions list
- Won't be re-created during discovery
- Registry fallback is disabled for this action

**Effect on Discovery**:
```ruby
# Action exists in code
module Stripe
  class PaymentIntentAction
    def self.details
      { event_type: "payment_intent.succeeded" }
    end
    # ...
  end
end

# After soft-delete:
# - Action discovery finds the file
# - Database has soft-deleted record
# - Sync service skips it (respects deletion)
# - Action won't execute
# - No registry fallback
```

### Restoring Soft-Deleted Actions

Soft-deleted actions can be restored via Rails console:

```ruby
# Find the soft-deleted action
action = CaptainHook::Action.with_deleted.find_by(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::PaymentIntentSucceededAction"
)

# Restore it
action.restore!

# Or manually:
action.update!(deleted_at: nil)
```

After restoration, the action will:
- Execute for new matching webhooks
- Appear in the admin UI active actions list
- Sync normally during discovery

## Priority Management

### Understanding Priority

Priority determines the execution order when multiple actions match the same event:

- **Lower numbers = Higher priority** (execute first)
- Default priority: `100`
- Common ranges:
  - `1-50`: Critical/high priority actions
  - `51-100`: Normal priority actions
  - `101-200`: Low priority actions
  - `201+`: Very low priority actions

### Priority Use Cases

**Sequential Processing**:
```ruby
# Run validation first (priority 10)
class ValidatePaymentAction
  def self.details
    { event_type: "payment.received", priority: 10 }
  end
end

# Then process payment (priority 50)
class ProcessPaymentAction
  def self.details
    { event_type: "payment.received", priority: 50 }
  end
end

# Finally send notifications (priority 100)
class NotifyPaymentAction
  def self.details
    { event_type: "payment.received", priority: 100 }
  end
end
```

**Wildcard Override**:
```ruby
# Specific handler runs first (priority 50)
class PaymentSucceededAction
  def self.details
    { event_type: "payment.succeeded", priority: 50 }
  end
end

# Generic logger runs after (priority 100)
class AllPaymentsLoggerAction
  def self.details
    { event_type: "payment.*", priority: 100 }
  end
end
```

### Modifying Priority

**Via Admin UI**:
1. Edit the action
2. Change the "Priority" field
3. Save changes
4. New value applies immediately to new webhooks

**Via Rails Console**:
```ruby
action = CaptainHook::Action.find_by(
  provider: "stripe",
  action_class: "Stripe::PaymentIntentAction"
)

action.update!(priority: 50)
```

**Via Code** (requires restart):
```ruby
# captain_hook/stripe/actions/payment_intent_action.rb
module Stripe
  class PaymentIntentAction
    def self.details
      {
        event_type: "payment_intent.succeeded",
        priority: 50  # Changed from 100
      }
    end
  end
end
```

## Execution Modes

### Async Mode (Recommended)

**Default**: `async: true`

Actions run in background jobs via `IncomingActionJob`:

- Webhook request completes immediately (fast response)
- Action executes asynchronously in job queue
- Retries handled by job system
- Won't block other webhooks
- Can handle long-running operations

**Best for**:
- Database writes
- API calls to external services
- Email sending
- Complex business logic
- Operations that might fail

**Example**:
```ruby
def self.details
  { event_type: "payment.succeeded", async: true }
end

def webhook_action(event:, payload:, metadata: {})
  # This runs in a background job
  order = Order.find_by(payment_id: payload["id"])
  order.update!(status: "paid")
  OrderMailer.confirmation(order).deliver_later
end
```

### Sync Mode (Use with Caution)

**Setting**: `async: false`

Actions run immediately in the webhook request:

- Blocks webhook response until complete
- No job queue overhead
- Must complete quickly (< 5 seconds)
- Failures may result in webhook retry from provider
- Can block other webhooks if slow

**Best for**:
- Very fast operations (< 1 second)
- Critical validations
- Simple logging
- Operations that must complete before response

**Example**:
```ruby
def self.details
  { event_type: "ping", async: false }
end

def webhook_action(event:, payload:, metadata: {})
  # This runs immediately in the request
  Rails.logger.info "Received ping from #{event.provider}"
end
```

### Changing Execution Mode

**Via Admin UI**:
1. Edit the action
2. Select "Async" or "Sync" radio button
3. Save changes

**Via Rails Console**:
```ruby
action = CaptainHook::Action.find_by(action_class: "Stripe::PingAction")
action.update!(async: false)
```

## Retry Configuration

### Retry Behavior

When an action raises an exception:

1. Action is marked as `failed` with error message
2. `attempt_count` is incremented
3. If `attempt_count < max_attempts`:
   - Action is reset to `pending`
   - Job is re-enqueued with delay
4. If `attempt_count >= max_attempts`:
   - Action stays `failed`
   - No more retries

### Max Attempts

**Default**: `5`

Number of times to retry a failed action:

```ruby
def self.details
  {
    event_type: "payment.succeeded",
    max_attempts: 5  # Try up to 5 times total
  }
end
```

**Setting via Admin UI**:
1. Edit action
2. Change "Maximum Retry Attempts" field
3. Save

**Considerations**:
- Set higher for transient failures (network issues)
- Set lower for permanent failures (validation errors)
- Each attempt is logged and tracked

### Retry Delays

**Default**: `[30, 60, 300, 900, 3600]` (30s, 1m, 5m, 15m, 1h)

Array of delays (in seconds) between retry attempts:

```ruby
def self.details
  {
    event_type: "payment.succeeded",
    retry_delays: [30, 60, 300, 900, 3600]
  }
end
```

**Delay Selection**:
- Attempt 1 fails → wait `retry_delays[0]` (30 seconds)
- Attempt 2 fails → wait `retry_delays[1]` (60 seconds)
- Attempt 3 fails → wait `retry_delays[2]` (300 seconds = 5 minutes)
- If more attempts than delays → use last delay

**Setting via Admin UI**:
1. Edit action
2. Enter comma-separated delays: `30, 60, 300, 900, 3600`
3. Save

**Common Patterns**:

```ruby
# Fast retry for transient issues
retry_delays: [5, 10, 30, 60, 120]  # 5s, 10s, 30s, 1m, 2m

# Exponential backoff
retry_delays: [30, 60, 120, 240, 480]  # 30s, 1m, 2m, 4m, 8m

# Long delays for rate-limited APIs
retry_delays: [300, 600, 1800, 3600, 7200]  # 5m, 10m, 30m, 1h, 2h

# Aggressive retry
retry_delays: [1, 5, 15, 30, 60]  # 1s, 5s, 15s, 30s, 1m
```

## Monitoring Action Execution

### IncomingEventAction Records

Each action execution creates an `IncomingEventAction` record:

```ruby
# View all action executions for an event
event = CaptainHook::IncomingEvent.last
event.incoming_event_actions
```

**Record Fields**:
- `incoming_event_id`: Associated webhook event
- `action_class`: Action that should execute
- `status`: Current status (pending, processing, processed, failed)
- `priority`: Execution priority
- `attempt_count`: Number of attempts made
- `last_attempt_at`: Timestamp of last attempt
- `error_message`: Error from failed attempt
- `locked_at`: When action was locked for processing
- `locked_by`: Worker ID that locked the action

### Action Status

Actions progress through these statuses:

1. **pending**: Waiting to be processed
2. **processing**: Currently being executed
3. **processed**: Successfully completed
4. **failed**: All retry attempts exhausted

### Viewing Action Executions

**In Admin UI**:

Navigate to an incoming event detail page to see all associated actions:

```
Event: stripe:payment_intent.succeeded

Actions Executed:
┌──────────────────────────────────┬───────────┬──────────┬──────────┐
│ Action                           │ Status    │ Attempts │ Duration │
├──────────────────────────────────┼───────────┼──────────┼──────────┤
│ Stripe::PaymentIntentAction      │ processed │ 1        │ 0.234s   │
│ Stripe::NotificationAction       │ processed │ 1        │ 1.123s   │
│ Stripe::LoggingAction           │ failed    │ 5        │ -        │
└──────────────────────────────────┴───────────┴──────────┴──────────┘
```

**Via Rails Console**:

```ruby
# Find failed actions
failed_actions = CaptainHook::IncomingEventAction.failed

# Check specific action execution
action_execution = CaptainHook::IncomingEventAction.find_by(
  action_class: "Stripe::PaymentIntentAction",
  status: :failed
)

puts action_execution.error_message
puts "Attempts: #{action_execution.attempt_count}"
puts "Last attempt: #{action_execution.last_attempt_at}"

# Retry a failed action manually
action_execution.reset_for_retry!
CaptainHook::IncomingActionJob.perform_later(action_execution.id)
```

### Action Metrics

Query action performance and reliability:

```ruby
# Success rate for an action
total = CaptainHook::IncomingEventAction
  .where(action_class: "Stripe::PaymentIntentAction")
  .count

successful = CaptainHook::IncomingEventAction
  .where(action_class: "Stripe::PaymentIntentAction", status: :processed)
  .count

success_rate = (successful.to_f / total * 100).round(2)
# => 98.5%

# Actions by status
CaptainHook::IncomingEventAction
  .group(:status)
  .count
# => {"processed"=>1523, "failed"=>12, "pending"=>5}

# Average attempts before success
CaptainHook::IncomingEventAction
  .where(status: :processed)
  .average(:attempt_count)
# => 1.08

# Find actions with high failure rate
CaptainHook::IncomingEventAction
  .where(status: :failed)
  .group(:action_class)
  .count
  .sort_by { |_, count| -count }
# => [["Stripe::HighFailureAction", 45], ...]
```

## Programmatic Management

### Via Rails Console

Complete programmatic control over actions:

#### List Actions

```ruby
# All active actions
CaptainHook::Action.active.by_priority

# Actions for specific provider
CaptainHook::Action.active.for_provider("stripe").by_priority

# Actions for specific event type
CaptainHook::Action.active.for_event_type("payment_intent.succeeded")

# Find specific action
action = CaptainHook::Action.find_by(
  provider: "stripe",
  event_type: "payment_intent.succeeded",
  action_class: "Stripe::PaymentIntentSucceededAction"
)
```

#### Create Action Manually

```ruby
CaptainHook::Action.create!(
  provider: "stripe",
  event_type: "custom.event",
  action_class: "Stripe::CustomAction",
  async: true,
  priority: 100,
  max_attempts: 5,
  retry_delays: [30, 60, 300, 900, 3600]
)
```

#### Update Action

```ruby
action = CaptainHook::Action.find_by(
  action_class: "Stripe::PaymentIntentAction"
)

action.update!(
  priority: 50,
  max_attempts: 10,
  retry_delays: [10, 30, 60, 300, 600]
)
```

#### Soft Delete Action

```ruby
action = CaptainHook::Action.find_by(
  action_class: "Stripe::UnwantedAction"
)

action.soft_delete!
# or
action.update!(deleted_at: Time.current)
```

#### Restore Action

```ruby
action = CaptainHook::Action.with_deleted.find_by(
  action_class: "Stripe::RestoredAction"
)

action.restore!
# or
action.update!(deleted_at: nil)
```

#### Bulk Operations

```ruby
# Increase priority for all Stripe actions
CaptainHook::Action
  .for_provider("stripe")
  .update_all("priority = priority - 10")

# Increase max attempts for all async actions
CaptainHook::Action
  .where(async: true)
  .update_all(max_attempts: 10)

# Soft delete all actions for a provider
CaptainHook::Action
  .for_provider("old_provider")
  .update_all(deleted_at: Time.current)
```

### Via ActionRegistry API

For in-memory registry manipulation (rarely needed):

```ruby
# Access registry
registry = CaptainHook.action_registry

# Check if actions registered
registry.actions_registered?(
  provider: "stripe",
  event_type: "payment_intent.succeeded"
)

# Get actions for provider/event
configs = registry.actions_for(
  provider: "stripe",
  event_type: "payment_intent.succeeded"
)

# Get all providers with registered actions
registry.providers
# => ["stripe", "github", "custom"]

# Get all actions for a provider
registry.actions_for_provider("stripe")

# Clear all registrations (for testing)
registry.clear!
```

## Action Discovery Sync

### Triggering Manual Sync

Force re-discovery and database sync:

```ruby
# In Rails console or rake task
CaptainHook::Engine.sync_actions
```

This will:
- Scan filesystem for action files
- Load action classes
- Extract metadata from `.details` methods
- Create new Action records
- Update existing Action records
- Skip soft-deleted actions
- Log results

**Output**:
```
🔍 CaptainHook: Found 12 registered action(s)
✅ Created action: Stripe::NewAction for stripe:new.event
🔄 Updated action: Stripe::UpdatedAction for stripe:updated.event
⏭️  Skipped deleted action: Stripe::DeletedAction for stripe:deleted.event
✅ CaptainHook: Synced actions - Created: 3, Updated: 5, Skipped: 4
```

### Sync Behavior

**New Actions**:
- Created in database with settings from code
- Immediately available for execution

**Existing Actions**:
- Settings updated from code (priority, async, max_attempts, retry_delays)
- Database values overwritten with code values

**Soft-Deleted Actions**:
- Skipped during sync
- Not updated
- Not restored automatically
- Code changes ignored until manually restored

**Removed from Code**:
- Action stays in database
- Still executes if active
- Manual deletion required

## Best Practices

### 1. Use Meaningful Priorities

Set priorities that reflect execution dependencies:

```ruby
# ✅ GOOD: Clear priority hierarchy
class ValidateAction
  def self.details
    { event_type: "payment.received", priority: 10 }  # Validate first
  end
end

class ProcessAction
  def self.details
    { event_type: "payment.received", priority: 50 }  # Then process
  end
end

class NotifyAction
  def self.details
    { event_type: "payment.received", priority: 100 } # Finally notify
  end
end

# ❌ BAD: All same priority (execution order undefined)
class ActionA
  def self.details
    { event_type: "payment.received", priority: 100 }
  end
end

class ActionB
  def self.details
    { event_type: "payment.received", priority: 100 }
  end
end
```

### 2. Choose Appropriate Execution Modes

```ruby
# ✅ GOOD: Async for slow operations
class SendEmailAction
  def self.details
    { event_type: "payment.succeeded", async: true }
  end
  
  def webhook_action(event:, payload:, metadata: {})
    OrderMailer.confirmation(payload["order_id"]).deliver_now
  end
end

# ✅ GOOD: Sync for fast logging
class LoggingAction
  def self.details
    { event_type: "ping", async: false }
  end
  
  def webhook_action(event:, payload:, metadata: {})
    Rails.logger.info "Ping received"
  end
end

# ❌ BAD: Sync for slow operations (blocks webhook)
class SlowApiCallAction
  def self.details
    { event_type: "payment.succeeded", async: false }  # Should be async!
  end
  
  def webhook_action(event:, payload:, metadata: {})
    SomeSlowApi.notify(payload)  # Takes 5+ seconds
  end
end
```

### 3. Set Appropriate Retry Configuration

```ruby
# ✅ GOOD: Many retries for transient issues
class ExternalApiAction
  def self.details
    {
      event_type: "payment.succeeded",
      max_attempts: 10,
      retry_delays: [30, 60, 120, 300, 600, 1800, 3600, 7200, 14400, 28800]
    }
  end
end

# ✅ GOOD: Fewer retries for validation errors
class ValidationAction
  def self.details
    {
      event_type: "payment.received",
      max_attempts: 2,
      retry_delays: [10, 30]
    }
  end
end

# ❌ BAD: Too many retries for permanent failures
class WillAlwaysFailAction
  def self.details
    {
      event_type: "invalid.event",
      max_attempts: 100,  # Will spam logs
      retry_delays: [1, 1, 1, ...]
    }
  end
end
```

### 4. Monitor Failed Actions

Set up monitoring for failed actions:

```ruby
# In a scheduled job or monitoring tool
failed_count = CaptainHook::IncomingEventAction
  .where(status: :failed)
  .where("last_attempt_at > ?", 1.hour.ago)
  .count

if failed_count > 10
  AlertService.notify("High failure rate in webhook actions: #{failed_count}")
end
```

### 5. Use Soft Delete Instead of Deletion

```ruby
# ✅ GOOD: Soft delete preserves history
action.soft_delete!

# ❌ BAD: Hard delete loses data
action.destroy  # Don't do this!
```

### 6. Test Actions Thoroughly

```ruby
# spec/actions/stripe/payment_intent_action_spec.rb
RSpec.describe Stripe::PaymentIntentAction do
  describe ".details" do
    it "returns correct metadata" do
      details = described_class.details
      expect(details[:event_type]).to eq("payment_intent.succeeded")
      expect(details[:priority]).to eq(100)
      expect(details[:async]).to be true
    end
  end

  describe "#webhook_action" do
    let(:event) { create(:incoming_event, :stripe_payment_intent_succeeded) }
    let(:payload) { JSON.parse(event.payload_json) }

    it "processes payment successfully" do
      action = described_class.new
      expect { action.webhook_action(event: event, payload: payload) }
        .to change { Order.count }.by(1)
    end

    it "handles errors gracefully" do
      action = described_class.new
      allow(Order).to receive(:create!).and_raise(StandardError)
      
      expect { action.webhook_action(event: event, payload: payload) }
        .to raise_error(StandardError)
    end
  end
end
```

## Troubleshooting

### Action Not Appearing in Admin UI

**Problem**: Action exists in code but doesn't show in admin UI

**Solutions**:
1. Check if action was soft-deleted: `CaptainHook::Action.with_deleted.find_by(...)`
2. Trigger manual sync: `CaptainHook::Engine.sync_actions`
3. Check Rails logs for loading errors
4. Verify action file is in correct directory structure
5. Ensure `.details` method exists and returns required fields

### Action Not Executing

**Problem**: Webhook arrives but action doesn't run

**Solutions**:
1. Check if action is active: `action.deleted_at.nil?`
2. Verify event type matches exactly: Check `event.event_type` vs `action.event_type`
3. Check action execution records: `event.incoming_event_actions`
4. Review job queue: Jobs might be stuck or not processing
5. Check error messages: `IncomingEventAction.failed.last.error_message`

### Actions Executing Out of Order

**Problem**: Actions run in unexpected order

**Explanation**: Priority determines order, not creation order

**Solutions**:
1. Check action priorities: `CaptainHook::Action.for_provider("stripe").order(:priority)`
2. Adjust priorities via admin UI or console
3. Remember: Lower priority = runs first
4. For same priority, class name determines order (alphabetically)

### High Failure Rate

**Problem**: Many actions failing

**Investigation**:
```ruby
# Find failing actions
failing_actions = CaptainHook::IncomingEventAction
  .where(status: :failed)
  .where("last_attempt_at > ?", 1.day.ago)
  .group(:action_class)
  .count

# Check error messages
CaptainHook::IncomingEventAction
  .where(status: :failed)
  .limit(10)
  .pluck(:action_class, :error_message, :attempt_count)

# Look for patterns
errors = CaptainHook::IncomingEventAction
  .where(status: :failed)
  .pluck(:error_message)
  .group_by(&:itself)
  .transform_values(&:count)
  .sort_by { |_, count| -count }
```

**Common Causes**:
- External API down or rate-limited
- Database constraints violated
- Missing required data in payload
- Environment variables not set
- Network connectivity issues

**Solutions**:
- Fix underlying issue
- Increase retry delays for rate limits
- Add validation before external calls
- Improve error handling
- Reset failed actions for retry after fix

### Manually Retrying Failed Actions

```ruby
# Find failed actions for an event
event = CaptainHook::IncomingEvent.find(123)
failed_actions = event.incoming_event_actions.failed

# Reset and retry them
failed_actions.each do |action_exec|
  action_exec.reset_for_retry!
  CaptainHook::IncomingActionJob.perform_later(action_exec.id)
end

# Or bulk retry all recent failures
CaptainHook::IncomingEventAction
  .where(status: :failed)
  .where("last_attempt_at > ?", 1.hour.ago)
  .find_each do |action_exec|
    action_exec.reset_for_retry!
    CaptainHook::IncomingActionJob.perform_later(action_exec.id)
  end
```

## Advanced Topics

### Multiple Actions for Same Event

Multiple actions can match the same event and all will execute:

```ruby
# All three will execute for payment_intent.succeeded
class LogAction
  def self.details
    { event_type: "payment_intent.*", priority: 10 }  # Runs first
  end
end

class ProcessAction
  def self.details
    { event_type: "payment_intent.succeeded", priority: 50 }  # Runs second
  end
end

class NotifyAction
  def self.details
    { event_type: "payment_intent.succeeded", priority: 100 }  # Runs third
  end
end
```

### Conditional Execution

Actions can choose not to process based on payload:

```ruby
def webhook_action(event:, payload:, metadata: {})
  # Skip test mode events
  return if payload["livemode"] == false
  
  # Skip certain currencies
  return unless payload["currency"] == "usd"
  
  # Process the event
  process_payment(payload)
end
```

### Action Dependencies

While actions run independently, you can create dependencies:

```ruby
class MainAction
  def webhook_action(event:, payload:, metadata: {})
    # Store result in event metadata
    result = process_payment(payload)
    event.update!(metadata: event.metadata.merge(main_result: result))
  end
end

class DependentAction
  def webhook_action(event:, payload:, metadata: {})
    # Use result from previous action
    main_result = event.metadata["main_result"]
    return unless main_result.present?
    
    send_notification(main_result)
  end
end
```

### Custom Retry Logic

Override retry behavior in the action class:

```ruby
class CustomRetryAction
  def webhook_action(event:, payload:, metadata: {})
    begin
      risky_operation(payload)
    rescue RateLimitError => e
      # Don't retry on rate limit - will be retried by provider
      Rails.logger.warn "Rate limited, skipping retry: #{e.message}"
      return
    rescue TemporaryError => e
      # Re-raise to trigger normal retry
      raise
    end
  end
end
```

## See Also

- [Action Discovery](ACTION_DISCOVERY.md) - How actions are discovered and loaded
- [TECHNICAL_PROCESS.md](../TECHNICAL_PROCESS.md) - Complete technical documentation
- [Provider Discovery](PROVIDER_DISCOVERY.md) - How providers are discovered
- [METRICS.md](METRICS.md) - Monitoring and instrumentation
