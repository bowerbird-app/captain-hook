# frozen_string_literal: true

# Rake tasks for testing webhook_site integration
namespace :webhook_site do
  desc "Send a test ping to webhook.site"
  task ping: :environment do
    require "net/http"
    webhook_url = ENV["WEBHOOK_SITE_URL"]

    puts "Sending test ping to: #{webhook_url}"

    # Create an outgoing event
    event = CaptainHook::OutgoingEvent.create!(
      provider: "webhook_site",
      event_type: "test.ping",
      target_url: webhook_url,
      payload: {
        provider: "webhook_site",
        event_type: "test.ping",
        sent_at: Time.current.iso8601,
        request_id: SecureRandom.uuid,
        data: {
          message: "hello from captain_hook test/dummy"
        }
      },
      headers: {
        "Content-Type" => "application/json",
        "User-Agent" => "CaptainHook/#{CaptainHook::VERSION}",
        "X-Webhook-Provider" => "webhook_site",
        "X-Request-Id" => SecureRandom.uuid
      },
      status: :pending
    )

    puts "Created outgoing event: #{event.id}"
    puts "Enqueuing job..."

    # Enqueue the job to send it
    CaptainHook::OutgoingJob.perform_later(event.id)

    puts "Job enqueued! Check #{webhook_url} for the webhook."
    puts "View event at: http://localhost:3000/captain_hook/admin/outgoing_events/#{event.id}"
  end
end
