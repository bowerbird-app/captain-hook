# Example metrics initializer for Captain Hook
# Copy this to config/initializers/captain_hook_metrics.rb and customize

Rails.application.config.after_initialize do
  # Choose your metrics backend
  USE_STATSD = ENV["STATSD_HOST"].present?
  USE_PROMETHEUS = defined?(Prometheus)
  USE_LOGGING = !USE_STATSD && !USE_PROMETHEUS

  # Initialize StatsD (if available)
  if USE_STATSD
    require "datadog/statsd"
    $statsd = Datadog::Statsd.new(
      ENV.fetch("STATSD_HOST", nil),
      ENV.fetch("STATSD_PORT", 8125).to_i,
      namespace: "captain_hook"
    )
  end

  # Initialize Prometheus (if available)
  if USE_PROMETHEUS
    prometheus = Prometheus::Client.registry

    $captain_hook_webhooks = prometheus.counter(
      :captain_hook_webhooks_received_total,
      docstring: "Total webhooks received",
      labels: %i[provider event_type]
    )

    $captain_hook_actions = prometheus.counter(
      :captain_hook_actions_total,
      docstring: "Total actions executed",
      labels: %i[provider status]
    )

    $captain_hook_duration = prometheus.histogram(
      :captain_hook_action_duration_seconds,
      docstring: "Action duration in seconds",
      labels: [:provider]
    )
  end

  # Helper to extract provider from action class
  def extract_provider(action_class)
    action_class.to_s.split("::").first.downcase
  end

  # Track webhook receipts
  ActiveSupport::Notifications.subscribe("incoming_event.received.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    if USE_STATSD
      tags = [
        "provider:#{event.payload[:provider]}",
        "event_type:#{event.payload[:event_type]}"
      ]
      $statsd.increment("webhook.received", tags: tags)
    elsif USE_PROMETHEUS
      $captain_hook_webhooks.increment(
        labels: {
          provider: event.payload[:provider],
          event_type: event.payload[:event_type]
        }
      )
    elsif USE_LOGGING
      Rails.logger.info(
        "[CaptainHook Metrics] Webhook received: " \
        "#{event.payload[:provider]}/#{event.payload[:event_type]}"
      )
    end
  end

  # Track successful actions
  ActiveSupport::Notifications.subscribe("action.completed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    provider = extract_provider(event.payload[:action_class])
    duration_ms = event.payload[:duration] * 1000

    if USE_STATSD
      tags = ["provider:#{provider}"]
      $statsd.increment("action.success", tags: tags)
      $statsd.histogram("action.duration", duration_ms, tags: tags)
    elsif USE_PROMETHEUS
      $captain_hook_actions.increment(
        labels: { provider: provider, status: "success" }
      )
      $captain_hook_duration.observe(
        event.payload[:duration],
        labels: { provider: provider }
      )
    elsif USE_LOGGING
      Rails.logger.info(
        "[CaptainHook Metrics] Action succeeded: " \
        "#{event.payload[:action_class]} in #{duration_ms.round(2)}ms"
      )
    end
  end

  # Track failed actions
  ActiveSupport::Notifications.subscribe("action.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    provider = extract_provider(event.payload[:action_class])

    if USE_STATSD
      tags = [
        "provider:#{provider}",
        "error:#{event.payload[:error]}",
        "attempt:#{event.payload[:attempt]}"
      ]
      $statsd.increment("action.failure", tags: tags)
    elsif USE_PROMETHEUS
      $captain_hook_actions.increment(
        labels: { provider: provider, status: "failure" }
      )
    end

    # Always log failures
    Rails.logger.warn(
      "[CaptainHook Metrics] Action failed: " \
      "#{event.payload[:action_class]} - #{event.payload[:error_message]} " \
      "(attempt #{event.payload[:attempt]})"
    )
  end

  # Track signature verification
  ActiveSupport::Notifications.subscribe("signature.verified.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    if USE_STATSD
      $statsd.increment("signature.verified", tags: ["provider:#{event.payload[:provider]}"])
    elsif USE_LOGGING
      Rails.logger.debug(
        "[CaptainHook Metrics] Signature verified: #{event.payload[:provider]}"
      )
    end
  end

  ActiveSupport::Notifications.subscribe("signature.failed.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    if USE_STATSD
      tags = [
        "provider:#{event.payload[:provider]}",
        "reason:#{event.payload[:reason]}"
      ]
      $statsd.increment("signature.failed", tags: tags)
    end

    # Always log signature failures (security concern)
    Rails.logger.warn(
      "[CaptainHook Security] Signature verification failed: " \
      "#{event.payload[:provider]} - #{event.payload[:reason]}"
    )
  end

  # Track rate limiting
  ActiveSupport::Notifications.subscribe("rate_limit.exceeded.captain_hook") do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)

    if USE_STATSD
      tags = ["provider:#{event.payload[:provider]}"]
      $statsd.increment("rate_limit.exceeded", tags: tags)
      $statsd.gauge("rate_limit.current", event.payload[:current_count], tags: tags)
    end

    # Always log rate limit issues
    Rails.logger.warn(
      "[CaptainHook Alert] Rate limit exceeded: " \
      "#{event.payload[:provider]} (#{event.payload[:current_count]}/#{event.payload[:limit]})"
    )
  end

  Rails.logger.info "✅ CaptainHook metrics initialized (backend: #{if USE_STATSD
                                                                     'StatsD'
                                                                   else
                                                                     USE_PROMETHEUS ? 'Prometheus' : 'Logging'
                                                                   end})"
end
