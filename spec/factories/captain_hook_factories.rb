# frozen_string_literal: true

FactoryBot.define do
  factory :captain_hook_provider, class: "CaptainHook::Provider" do
    sequence(:name) { |n| "test_provider_#{n}" }
    display_name { "Test Provider" }
    adapter_class { "CaptainHook::Adapters::Stripe" }
    signing_secret { "whsec_test_secret_#{SecureRandom.hex(16)}" }
    token { SecureRandom.urlsafe_base64(32) }
    active { true }
    timestamp_tolerance_seconds { 300 }
    rate_limit_requests { 100 }
    rate_limit_period { 60 }
    max_payload_size_bytes { 1_048_576 }

    trait :inactive do
      active { false }
    end

    trait :stripe do
      name { "stripe" }
      display_name { "Stripe" }
      adapter_class { "CaptainHook::Adapters::Stripe" }
    end

    trait :square do
      name { "square" }
      display_name { "Square" }
      adapter_class { "CaptainHook::Adapters::Square" }
    end

    trait :paypal do
      name { "paypal" }
      display_name { "PayPal" }
      adapter_class { "CaptainHook::Adapters::Paypal" }
    end

    trait :webhook_site do
      name { "webhook_site" }
      display_name { "Webhook.site" }
      adapter_class { "CaptainHook::Adapters::WebhookSite" }
    end

    trait :with_rate_limiting do
      rate_limit_requests { 10 }
      rate_limit_period { 60 }
    end

    trait :without_rate_limiting do
      rate_limit_requests { nil }
      rate_limit_period { nil }
    end

    trait :with_payload_limit do
      max_payload_size_bytes { 1024 }
    end

    trait :without_payload_limit do
      max_payload_size_bytes { nil }
    end
  end

  factory :captain_hook_incoming_event, class: "CaptainHook::IncomingEvent" do
    provider { "test_provider" }
    sequence(:external_id) { |n| "evt_test_#{n}" }
    event_type { "test.event" }
    payload { { data: { test: "value" } } }
    headers { { "Content-Type" => "application/json" } }
    metadata { {} }
    status { :received }
    dedup_state { :unique }

    trait :duplicate do
      dedup_state { :duplicate }
    end

    trait :processing do
      status { :processing }
    end

    trait :completed do
      status { :completed }
    end

    trait :failed do
      status { :failed }
    end
  end

  factory :captain_hook_handler, class: "CaptainHook::Handler" do
    provider { "test_provider" }
    event_type { "test.event" }
    handler_class { "TestHandler" }
    priority { 100 }
    async { true }
    max_attempts { 3 }
    retry_delays { [30, 60, 300] }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :sync do
      async { false }
    end

    trait :high_priority do
      priority { 10 }
    end

    trait :low_priority do
      priority { 1000 }
    end
  end

  factory :captain_hook_incoming_event_handler, class: "CaptainHook::IncomingEventHandler" do
    association :incoming_event, factory: :captain_hook_incoming_event
    handler_class { "TestHandler" }
    status { :pending }
    priority { 100 }
    attempt_count { 0 }

    trait :processing do
      status { :processing }
      started_at { Time.current }
    end

    trait :completed do
      status { :completed }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { :failed }
      started_at { 1.minute.ago }
      failed_at { Time.current }
      error_message { "Test error" }
      attempt_count { 3 }
    end
  end
end
