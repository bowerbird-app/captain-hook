# frozen_string_literal: true

# rubocop:disable Metrics/BlockLength
namespace :webhook_site do
  desc "Send a test ping webhook to Webhook.site"
  task ping: :environment do
    # Get configuration from environment or use defaults
    webhook_url = ENV["WEBHOOK_SITE_URL"] || "https://webhook.site/400efa14-c6e1-4e77-8a54-51e8c4026a5e"

    puts "Sending test.ping event to Webhook.site..."
    puts "URL: #{webhook_url}"

    # Create the outgoing event
    event = CaptainHook::OutgoingEvent.create!(
      provider: "webhook_site",
      event_type: "test.ping",
      target_url: webhook_url,
      payload: {
        provider: "webhook_site",
        event_type: "test.ping",
        sent_at: Time.current.iso8601,
        request_id: SecureRandom.uuid,
        data: { message: "hello from webhook gem" }
      },
      headers: {
        "X-Webhook-Provider" => "webhook_site",
        "X-Webhook-Event" => "test.ping"
      }
    )

    puts "Created OutgoingEvent with ID: #{event.id}"
    puts "Enqueueing job..."

    # Enqueue the job synchronously for testing
    CaptainHook::OutgoingJob.perform_later(event.id)

    puts "Job enqueued! Check Webhook.site for the request."
    puts "Event ID: #{event.id}"
    puts "\nTo check status, run:"
    puts "  rails console"
    puts "  CaptainHook::OutgoingEvent.find('#{event.id}')"
  end
end
# rubocop:enable Metrics/BlockLength
