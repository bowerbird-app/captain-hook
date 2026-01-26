# 📊 Metrics & Monitoring Guide

This guide explains how to track success rates, latency, and throughput in Captain Hook using the built-in instrumentation system.

## Table of Contents

- [Overview](#overview)
- [Available Events](#available-events)
- [Quick Start](#quick-start)
- [Tracking Success Rates](#tracking-success-rates)
- [Tracking Latency](#tracking-latency)
- [Tracking Throughput](#tracking-throughput)
- [Integration Examples](#integration-examples)
  - [StatsD / DataDog](#statsd--datadog)
  - [Prometheus](#prometheus)
  - [New Relic](#new-relic)
  - [Custom Database](#custom-database)
- [Complete Implementation Example](#complete-implementation-example)
- [Dashboard Recommendations](#dashboard-recommendations)
- [Alerting Guidelines](#alerting-guidelines)

## Overview

Captain Hook emits [ActiveSupport::Notifications](https://api.rubyonrails.org/classes/ActiveSupport/Notifications.html) throughout the webhook processing lifecycle. You can subscribe to these events to collect metrics and send them to your monitoring service.

**Key Benefits:**
- 🎯 **Zero-overhead** when not subscribed
- 📊 **Rich context** - Provider, event type, duration, error details
- 🔌 **Easy integration** with popular metrics services
- 🚀 **Real-time monitoring** - Events emitted as they happen

## Available Events

Captain Hook emits these instrumentation events:

| Event Name | When Emitted | Payload |
|-----------|--------------|---------|
| `incoming_event.received.captain_hook` | Webhook received and stored | `event_id`, `provider`, `event_type`, `external_id` |
| `incoming_event.processing.captain_hook` | Event processing started | `event_id`, `provider`, `event_type` |
| `incoming_event.processed.captain_hook` | Event fully processed | `event_id`, `provider`, `event_type`, `duration`, `actions_count` |
| `incoming_event.failed.captain_hook` | Event processing failed | `event_id`, `provider`, `event_type`, `error`, `error_message` |
| `action.started.captain_hook` | Action execution started | `action_id`, `action_class`, `event_id`, `provider`, `attempt` |
| `action.completed.captain_hook` | Action succeeded | `action_id`, `action_class`, `duration` |
| `action.failed.captain_hook` | Action failed | `action_id`, `action_class`, `error`, `error_message`, `attempt` |
| `rate_limit.exceeded.captain_hook` | Rate limit hit | `provider`, `current_count`, `limit` |
| `signature.verified.captain_hook` | Signature valid | `provider` |
| `signature.failed.captain_hook` | Signature invalid | `provider`, `reason` |

**Note:** The `start` and `finish` times are automatically provided by ActiveSupport::Notifications, allowing you to calculate duration for any event.

## Quick Start

Create an initializer to subscribe to Captain Hook events:

```ruby
# config/initializers/captain_hook_metrics.rb
Rails.application.config.after_initialize do
  # Subscribe to all Captain Hook events
  ActiveSupport::Notifications.subscribe(/captain_hook/) do |name, start, finish, id, payload|
    duration_ms = (finish - start) * 1000
    
    Rails.logger.info "[CaptainHook Metrics] #{name}: #{duration_ms.round(2)}ms"
    Rails.logger.info "  Payload: #{payload.inspect}"
  end
end
```

This will log all Captain Hook events with timing information.

## Tracking Success Rates

Success rate = (successful actions / total actions) × 100

### Basic Implementation

```ruby
# config/initializers/captain_hook_metrics.rb
Rails.application.config.after_initialize do
  # Track successful actions
  ActiveSupport::Notifications.subscribe("action.completed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    # Increment success counter
    $redis.incr("captain_hook:actions:success")
    $redis.incr("captain_hook:actions:success:#{event.payload[:provider]}")
    $redis.incr("captain_hook:actions:success:#{event.payload[:action_class]}")
  end
  
  # Track failed actions
  ActiveSupport::Notifications.subscribe("action.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    # Increment failure counter
    $redis.incr("captain_hook:actions:failed")
    $redis.incr("captain_hook:actions:failed:#{event.payload[:provider]}")
    $redis.incr("captain_hook:actions:failed:#{event.payload[:action_class]}")
  end
end
```

### Calculate Success Rate

```ruby
# Get overall success rate
def captain_hook_success_rate
  success = $redis.get("captain_hook:actions:success").to_i
  failed = $redis.get("captain_hook:actions:failed").to_i
  total = success + failed
  
  return 0 if total.zero?
  (success.to_f / total * 100).round(2)
end

# Get success rate by provider
def captain_hook_success_rate_by_provider(provider)
  success = $redis.get("captain_hook:actions:success:#{provider}").to_i
  failed = $redis.get("captain_hook:actions:failed:#{provider}").to_i
  total = success + failed
  
  return 0 if total.zero?
  (success.to_f / total * 100).round(2)
end

# Usage
captain_hook_success_rate           # => 98.5
captain_hook_success_rate_by_provider("stripe")  # => 99.2
```

## Tracking Latency

Latency measures how long it takes to process webhooks and execute actions.

### Track Action Execution Latency

```ruby
# config/initializers/captain_hook_metrics.rb
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe("action.completed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    duration_ms = event.payload[:duration] * 1000  # Convert to milliseconds
    
    # Store latency metrics
    $redis.lpush("captain_hook:latency:action", duration_ms)
    $redis.ltrim("captain_hook:latency:action", 0, 999)  # Keep last 1000 samples
    
    # By provider
    provider = extract_provider_from_action(event.payload[:action_class])
    $redis.lpush("captain_hook:latency:action:#{provider}", duration_ms)
    $redis.ltrim("captain_hook:latency:action:#{provider}", 0, 999)
  end
end

def extract_provider_from_action(action_class)
  # Extract provider from "Stripe::PaymentIntentSucceededAction"
  action_class.split("::").first.downcase
end
```

### Calculate Latency Percentiles

```ruby
def captain_hook_latency_stats(key = "captain_hook:latency:action")
  samples = $redis.lrange(key, 0, -1).map(&:to_f).sort
  
  return { count: 0 } if samples.empty?
  
  {
    count: samples.size,
    min: samples.first.round(2),
    max: samples.last.round(2),
    avg: (samples.sum / samples.size).round(2),
    p50: percentile(samples, 50),
    p95: percentile(samples, 95),
    p99: percentile(samples, 99)
  }
end

def percentile(sorted_array, p)
  return 0 if sorted_array.empty?
  
  index = (p / 100.0 * sorted_array.length).ceil - 1
  sorted_array[index].round(2)
end

# Usage
captain_hook_latency_stats
# => {
#   count: 1000,
#   min: 5.2,
#   max: 2450.8,
#   avg: 156.3,
#   p50: 120.5,
#   p95: 450.2,
#   p99: 890.1
# }
```

### Track End-to-End Latency

```ruby
ActiveSupport::Notifications.subscribe("incoming_event.processed.captain_hook") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  duration_ms = event.payload[:duration] * 1000
  
  # Track how long it took from receiving webhook to completing all actions
  $redis.lpush("captain_hook:latency:end_to_end", duration_ms)
  $redis.ltrim("captain_hook:latency:end_to_end", 0, 999)
  
  # By provider
  $redis.lpush("captain_hook:latency:end_to_end:#{event.payload[:provider]}", duration_ms)
  $redis.ltrim("captain_hook:latency:end_to_end:#{event.payload[:provider]}", 0, 999)
end
```

## Tracking Throughput

Throughput measures how many webhooks/actions are processed per unit of time.

### Track Webhook Throughput

```ruby
# config/initializers/captain_hook_metrics.rb
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe("incoming_event.received.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    timestamp = Time.current.to_i / 60  # Group by minute
    
    # Increment counters
    $redis.incr("captain_hook:throughput:webhooks:#{timestamp}")
    $redis.incr("captain_hook:throughput:webhooks:#{event.payload[:provider]}:#{timestamp}")
    
    # Expire old keys after 24 hours
    $redis.expire("captain_hook:throughput:webhooks:#{timestamp}", 86400)
    $redis.expire("captain_hook:throughput:webhooks:#{event.payload[:provider]}:#{timestamp}", 86400)
  end
end
```

### Calculate Throughput Rates

```ruby
def captain_hook_throughput_per_minute(minutes_ago: 5)
  now = Time.current.to_i / 60
  counts = []
  
  minutes_ago.times do |i|
    timestamp = now - i
    count = $redis.get("captain_hook:throughput:webhooks:#{timestamp}").to_i
    counts << count
  end
  
  {
    current: counts.first,
    avg: (counts.sum.to_f / counts.size).round(2),
    max: counts.max,
    min: counts.min
  }
end

def captain_hook_throughput_by_provider(provider, minutes_ago: 5)
  now = Time.current.to_i / 60
  counts = []
  
  minutes_ago.times do |i|
    timestamp = now - i
    count = $redis.get("captain_hook:throughput:webhooks:#{provider}:#{timestamp}").to_i
    counts << count
  end
  
  {
    provider: provider,
    current: counts.first,
    avg: (counts.sum.to_f / counts.size).round(2),
    max: counts.max,
    min: counts.min
  }
end

# Usage
captain_hook_throughput_per_minute(minutes_ago: 5)
# => { current: 42, avg: 38.4, max: 52, min: 28 }

captain_hook_throughput_by_provider("stripe", minutes_ago: 5)
# => { provider: "stripe", current: 25, avg: 22.6, max: 30, min: 18 }
```

## Integration Examples

### StatsD / DataDog

```ruby
# config/initializers/captain_hook_metrics.rb
require 'datadog/statsd'

Rails.application.config.after_initialize do
  statsd = Datadog::Statsd.new('localhost', 8125, namespace: 'captain_hook')
  
  # Action completed
  ActiveSupport::Notifications.subscribe("action.completed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = [
      "action_class:#{event.payload[:action_class]}",
      "provider:#{extract_provider(event.payload[:action_class])}"
    ]
    
    statsd.increment('action.success', tags: tags)
    statsd.histogram('action.duration', event.payload[:duration] * 1000, tags: tags)
  end
  
  # Action failed
  ActiveSupport::Notifications.subscribe("action.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = [
      "action_class:#{event.payload[:action_class]}",
      "error:#{event.payload[:error]}",
      "attempt:#{event.payload[:attempt]}"
    ]
    
    statsd.increment('action.failure', tags: tags)
  end
  
  # Webhook received
  ActiveSupport::Notifications.subscribe("incoming_event.received.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = [
      "provider:#{event.payload[:provider]}",
      "event_type:#{event.payload[:event_type]}"
    ]
    
    statsd.increment('webhook.received', tags: tags)
  end
  
  # Rate limit exceeded
  ActiveSupport::Notifications.subscribe("rate_limit.exceeded.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = ["provider:#{event.payload[:provider]}"]
    statsd.increment('rate_limit.exceeded', tags: tags)
    statsd.gauge('rate_limit.current', event.payload[:current_count], tags: tags)
  end
  
  # Signature verification
  ActiveSupport::Notifications.subscribe("signature.verified.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    statsd.increment('signature.verified', tags: ["provider:#{event.payload[:provider]}"])
  end
  
  ActiveSupport::Notifications.subscribe("signature.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = [
      "provider:#{event.payload[:provider]}",
      "reason:#{event.payload[:reason]}"
    ]
    
    statsd.increment('signature.failed', tags: tags)
  end
  
  def extract_provider(action_class)
    action_class.split("::").first.downcase
  end
end
```

### Prometheus

```ruby
# config/initializers/captain_hook_metrics.rb
require 'prometheus/client'

Rails.application.config.after_initialize do
  prometheus = Prometheus::Client.registry
  
  # Define metrics
  webhooks_received = prometheus.counter(
    :captain_hook_webhooks_received_total,
    docstring: 'Total number of webhooks received',
    labels: [:provider, :event_type]
  )
  
  actions_total = prometheus.counter(
    :captain_hook_actions_total,
    docstring: 'Total number of actions executed',
    labels: [:provider, :action_class, :status]
  )
  
  action_duration = prometheus.histogram(
    :captain_hook_action_duration_seconds,
    docstring: 'Action execution duration in seconds',
    labels: [:provider, :action_class]
  )
  
  signature_verifications = prometheus.counter(
    :captain_hook_signature_verifications_total,
    docstring: 'Total signature verifications',
    labels: [:provider, :status]
  )
  
  # Subscribe to events
  ActiveSupport::Notifications.subscribe("incoming_event.received.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    webhooks_received.increment(
      labels: {
        provider: event.payload[:provider],
        event_type: event.payload[:event_type]
      }
    )
  end
  
  ActiveSupport::Notifications.subscribe("action.completed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    provider = extract_provider(event.payload[:action_class])
    
    actions_total.increment(
      labels: {
        provider: provider,
        action_class: event.payload[:action_class],
        status: 'success'
      }
    )
    
    action_duration.observe(
      event.payload[:duration],
      labels: {
        provider: provider,
        action_class: event.payload[:action_class]
      }
    )
  end
  
  ActiveSupport::Notifications.subscribe("action.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    provider = extract_provider(event.payload[:action_class])
    
    actions_total.increment(
      labels: {
        provider: provider,
        action_class: event.payload[:action_class],
        status: 'failure'
      }
    )
  end
  
  ActiveSupport::Notifications.subscribe("signature.verified.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    signature_verifications.increment(
      labels: {
        provider: event.payload[:provider],
        status: 'success'
      }
    )
  end
  
  ActiveSupport::Notifications.subscribe("signature.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    signature_verifications.increment(
      labels: {
        provider: event.payload[:provider],
        status: 'failure'
      }
    )
  end
  
  def extract_provider(action_class)
    action_class.split("::").first.downcase
  end
end

# Mount Prometheus metrics endpoint
# config/routes.rb
require 'prometheus/middleware/exporter'
mount Prometheus::Middleware::Exporter => '/metrics'
```

### New Relic

```ruby
# config/initializers/captain_hook_metrics.rb
Rails.application.config.after_initialize do
  # Action metrics
  ActiveSupport::Notifications.subscribe("action.completed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    NewRelic::Agent.record_metric(
      'Custom/CaptainHook/Action/Success',
      1
    )
    
    NewRelic::Agent.record_metric(
      'Custom/CaptainHook/Action/Duration',
      event.payload[:duration] * 1000
    )
    
    # Custom attributes for transaction tracing
    NewRelic::Agent.add_custom_attributes(
      captain_hook_action: event.payload[:action_class],
      captain_hook_provider: extract_provider(event.payload[:action_class])
    )
  end
  
  ActiveSupport::Notifications.subscribe("action.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    NewRelic::Agent.record_metric(
      'Custom/CaptainHook/Action/Failure',
      1
    )
    
    NewRelic::Agent.notice_error(
      StandardError.new(event.payload[:error_message]),
      custom_params: {
        action_class: event.payload[:action_class],
        error: event.payload[:error],
        attempt: event.payload[:attempt]
      }
    )
  end
  
  # Webhook metrics
  ActiveSupport::Notifications.subscribe("incoming_event.received.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    NewRelic::Agent.record_metric(
      "Custom/CaptainHook/Webhook/Received/#{event.payload[:provider]}",
      1
    )
  end
  
  def extract_provider(action_class)
    action_class.split("::").first.downcase
  end
end
```

### Custom Database

Store metrics in your database for custom analytics:

```ruby
# app/models/captain_hook_metric.rb
class CaptainHookMetric < ApplicationRecord
  # Table: captain_hook_metrics
  # - event_type (string) - e.g., "action.completed", "webhook.received"
  # - provider (string)
  # - action_class (string, nullable)
  # - duration_ms (float, nullable)
  # - status (string) - "success", "failure"
  # - error (string, nullable)
  # - metadata (jsonb)
  # - created_at (timestamp)
end

# config/initializers/captain_hook_metrics.rb
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe(/captain_hook/) do |name, start, finish, id, payload|
    duration_ms = ((finish - start) * 1000).round(2)
    
    CaptainHookMetric.create!(
      event_type: name.sub('.captain_hook', ''),
      provider: payload[:provider],
      action_class: payload[:action_class],
      duration_ms: duration_ms,
      status: determine_status(name),
      error: payload[:error],
      metadata: payload
    )
  rescue => e
    # Don't let metrics collection break webhook processing
    Rails.logger.error "Failed to record Captain Hook metric: #{e.message}"
  end
  
  def determine_status(event_name)
    case event_name
    when /completed/, /verified/, /received/
      'success'
    when /failed/, /exceeded/
      'failure'
    else
      'unknown'
    end
  end
end

# Query examples
CaptainHookMetric.where(provider: 'stripe').where('created_at > ?', 1.hour.ago).average(:duration_ms)
CaptainHookMetric.where(status: 'failure').group(:error).count
CaptainHookMetric.where(event_type: 'action.completed').group(:action_class).count
```

## Complete Implementation Example

Here's a production-ready metrics implementation that tracks everything:

```ruby
# config/initializers/captain_hook_metrics.rb
Rails.application.config.after_initialize do
  # Initialize metrics service (choose one: StatsD, Prometheus, etc.)
  metrics = if ENV['STATSD_HOST']
    require 'datadog/statsd'
    Datadog::Statsd.new(ENV['STATSD_HOST'], ENV['STATSD_PORT'] || 8125, namespace: 'captain_hook')
  end
  
  # Helper to extract provider from action class
  extract_provider = ->(action_class) do
    action_class.to_s.split("::").first.downcase
  end
  
  # Track all webhook receipts
  ActiveSupport::Notifications.subscribe("incoming_event.received.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = [
      "provider:#{event.payload[:provider]}",
      "event_type:#{event.payload[:event_type]}"
    ]
    
    metrics&.increment('webhook.received', tags: tags)
    metrics&.timing('webhook.receive_time', event.duration * 1000, tags: tags)
  end
  
  # Track successful actions
  ActiveSupport::Notifications.subscribe("action.completed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    provider = extract_provider.call(event.payload[:action_class])
    
    tags = [
      "provider:#{provider}",
      "action_class:#{event.payload[:action_class]}"
    ]
    
    metrics&.increment('action.success', tags: tags)
    metrics&.histogram('action.duration', event.payload[:duration] * 1000, tags: tags)
    
    # Log for debugging
    Rails.logger.info(
      "[CaptainHook Metrics] Action succeeded: " \
      "#{event.payload[:action_class]} in #{(event.payload[:duration] * 1000).round(2)}ms"
    )
  end
  
  # Track failed actions
  ActiveSupport::Notifications.subscribe("action.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    provider = extract_provider.call(event.payload[:action_class])
    
    tags = [
      "provider:#{provider}",
      "action_class:#{event.payload[:action_class]}",
      "error:#{event.payload[:error]}",
      "attempt:#{event.payload[:attempt]}"
    ]
    
    metrics&.increment('action.failure', tags: tags)
    
    # Alert on critical failures
    if event.payload[:attempt] >= 3
      Rails.logger.error(
        "[CaptainHook Alert] Action failing after #{event.payload[:attempt]} attempts: " \
        "#{event.payload[:action_class]} - #{event.payload[:error_message]}"
      )
    end
  end
  
  # Track end-to-end processing time
  ActiveSupport::Notifications.subscribe("incoming_event.processed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = [
      "provider:#{event.payload[:provider]}",
      "event_type:#{event.payload[:event_type]}"
    ]
    
    metrics&.histogram('webhook.processing_time', event.payload[:duration] * 1000, tags: tags)
    metrics&.gauge('webhook.actions_count', event.payload[:actions_count], tags: tags)
  end
  
  # Track signature verification
  ActiveSupport::Notifications.subscribe("signature.verified.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    metrics&.increment('signature.verified', tags: ["provider:#{event.payload[:provider]}"])
  end
  
  ActiveSupport::Notifications.subscribe("signature.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = [
      "provider:#{event.payload[:provider]}",
      "reason:#{event.payload[:reason]}"
    ]
    
    metrics&.increment('signature.failed', tags: tags)
    
    # Alert on signature failures (potential security issue)
    Rails.logger.warn(
      "[CaptainHook Security] Signature verification failed for #{event.payload[:provider]}: " \
      "#{event.payload[:reason]}"
    )
  end
  
  # Track rate limiting
  ActiveSupport::Notifications.subscribe("rate_limit.exceeded.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    tags = ["provider:#{event.payload[:provider]}"]
    
    metrics&.increment('rate_limit.exceeded', tags: tags)
    metrics&.gauge('rate_limit.current', event.payload[:current_count], tags: tags)
    
    Rails.logger.warn(
      "[CaptainHook Alert] Rate limit exceeded for #{event.payload[:provider]}: " \
      "#{event.payload[:current_count]}/#{event.payload[:limit]}"
    )
  end
  
  Rails.logger.info "✅ CaptainHook metrics initialized"
end
```

## Dashboard Recommendations

### Key Metrics to Display

**Webhook Health Dashboard:**
1. **Webhooks Received** (per minute) - Line chart by provider
2. **Action Success Rate** (percentage) - Gauge by provider
3. **Average Action Duration** (milliseconds) - Line chart by action class
4. **Failed Actions** (count) - Bar chart by error type
5. **Rate Limit Status** (current/limit) - Progress bar by provider
6. **Signature Failures** (count) - Alert indicator

**Sample Datadog Dashboard Query:**

```
# Webhook throughput
sum:captain_hook.webhook.received{*}.as_rate()

# Action success rate
(sum:captain_hook.action.success{*}.as_count() / 
 (sum:captain_hook.action.success{*}.as_count() + sum:captain_hook.action.failure{*}.as_count())) * 100

# P95 action latency
p95:captain_hook.action.duration{*}

# Failed actions by error type
sum:captain_hook.action.failure{*} by {error}.as_count()
```

## Alerting Guidelines

### Recommended Alerts

**Critical Alerts:**
- ❌ Action success rate < 95% (5-minute window)
- ❌ Signature verification failures > 5 per minute
- ❌ Action P95 latency > 5 seconds
- ❌ No webhooks received for 10+ minutes (if expected)

**Warning Alerts:**
- ⚠️ Action success rate < 98% (15-minute window)
- ⚠️ Rate limit usage > 80%
- ⚠️ Action retry attempts > 2
- ⚠️ Webhook processing time > 30 seconds

**Sample Alert Configuration (PagerDuty/Slack):**

```ruby
# config/initializers/captain_hook_alerts.rb
Rails.application.config.after_initialize do
  # Alert on low success rate
  ActiveSupport::Notifications.subscribe("action.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    # Check if this is a repeated failure
    key = "captain_hook:failures:#{event.payload[:action_class]}"
    count = $redis.incr(key)
    $redis.expire(key, 300)  # 5-minute window
    
    if count >= 10
      SlackNotifier.alert(
        channel: '#ops-alerts',
        text: "🚨 CaptainHook: #{event.payload[:action_class]} failing repeatedly " \
              "(#{count} failures in 5 minutes)",
        priority: 'high'
      )
    end
  end
  
  # Alert on signature failures
  ActiveSupport::Notifications.subscribe("signature.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    
    SlackNotifier.alert(
      channel: '#security-alerts',
      text: "🔒 CaptainHook: Signature verification failed for " \
            "#{event.payload[:provider]}: #{event.payload[:reason]}",
      priority: 'high'
    )
  end
end
```

---

## Summary

To track **success rates, latency, and throughput** in Captain Hook:

1. **Subscribe** to ActiveSupport::Notifications events in an initializer
2. **Extract** the metrics you need (duration, provider, status, etc.)
3. **Send** them to your metrics service (StatsD, Prometheus, etc.)
4. **Visualize** in your dashboard (Datadog, Grafana, etc.)
5. **Alert** when metrics exceed thresholds

The instrumentation is already built into Captain Hook - you just need to subscribe to the events and forward them to your monitoring system!

For questions or issues, see the [main README](../README.md) or open an issue on GitHub.
