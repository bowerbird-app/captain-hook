# frozen_string_literal: true

# NOTE: The setup and doctor tasks are in lib/tasks/setup.rake
# This file contains status and monitoring tasks for CaptainHook

namespace :captain_hook do
  desc "Show CaptainHook status and statistics"
  task status: :environment do
    puts "\n#{' =' * 80}"
    puts "⚓ CaptainHook Status"
    puts "#{'=' * 80}\n"

    # Providers
    providers = CaptainHook::Provider.all
    puts "📦 Providers: #{providers.count}"
    providers.each do |provider|
      provider_config = CaptainHook.configuration.provider(provider.name)
      display_name = provider_config&.display_name || provider.name.titleize
      status = provider.active? ? "✓" : "✗"
      puts "  #{status} #{display_name} (#{provider.name})"
      puts "    URL: #{provider.webhook_url}"
      if provider.rate_limit_requests
        puts "    Rate limit: #{provider.rate_limit_requests}/#{provider.rate_limit_period}s"
      end
    end

    # Actions
    actions = CaptainHook::Action.all.group_by(&:provider)
    puts "\n🎯 Actions: #{CaptainHook::Action.count}"
    actions.each do |provider_name, provider_actions|
      puts "  #{provider_name}:"
      provider_actions.each do |action|
        status_icon = action.deleted? ? "✗" : "✓"
        async_icon = action.async? ? "🔄" : "⚡"
        puts "    #{status_icon} #{async_icon} #{action.event_type} (priority: #{action.priority})"
      end
    end

    # Events
    total_events = CaptainHook::IncomingEvent.count
    recent_events = CaptainHook::IncomingEvent.where("created_at > ?", 24.hours.ago).count
    puts "\n📨 Incoming Events:"
    puts "  Total: #{total_events}"
    puts "  Last 24h: #{recent_events}"

    # Recent activity
    if total_events.positive?
      latest = CaptainHook::IncomingEvent.order(created_at: :desc).limit(5)
      puts "\n📊 Latest Events:"
      latest.each do |event|
        puts "  - #{event.provider}/#{event.event_type} (#{event.created_at.strftime('%Y-%m-%d %H:%M')})"
      end
    end

    puts "\n#{'=' * 80}\n"
  end
end
