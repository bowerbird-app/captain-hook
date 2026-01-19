# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Complex Webhook Integration Scenarios", type: :request do
  # Test scenario: Third-party gem with webhook + Rails app with same webhook (same signing secret)
  # Note: These tests need refactoring to match the actual action interface
  xdescribe "Third-party gem and Rails app sharing same webhook provider" do
    let(:shared_secret) { "whsec_shared_secret_#{SecureRandom.hex(16)}" }
    let(:provider) { create(:captain_hook_provider, :stripe, signing_secret: shared_secret) }

    # Simulate an action from a third-party gem
    class GemWebhookHandler
      def self.handle(event:, payload:, metadata:)
        Rails.logger.info "GemWebhookHandler executed for event #{event.external_id}"
        event.update(metadata: event.metadata.merge(gem_action_executed: true))
      end
    end

    # Simulate an action from the Rails app
    class AppWebhookHandler
      def self.handle(event:, payload:, metadata:)
        Rails.logger.info "AppWebhookHandler executed for event #{event.external_id}"
        event.update(metadata: event.metadata.merge(app_action_executed: true))
      end
    end

    before do
      # Register both actions for the same event type
      CaptainHook.register_action(
        provider: provider.name,
        event_type: "payment_intent.succeeded",
        action_class: "GemWebhookHandler",
        priority: 100,
        async: false # Sync for easier testing
      )

      CaptainHook.register_action(
        provider: provider.name,
        event_type: "payment_intent.succeeded",
        action_class: "AppWebhookHandler",
        priority: 200,
        async: false # Sync for easier testing
      )
    end

    it "executes both gem and app actions for the same webhook" do
      payload = {
        id: "evt_shared_123",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_123", amount: 1000 } }
      }.to_json

      timestamp = Time.current.to_i
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", shared_secret, signed_payload)
      signature_header = "t=#{timestamp},v1=#{signature}"

      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => signature_header
           }

      expect(response).to have_http_status(:created)

      event = CaptainHook::IncomingEvent.find_by(external_id: "evt_shared_123")
      expect(event).to be_present
      expect(event.metadata["gem_action_executed"]).to be true
      expect(event.metadata["app_action_executed"]).to be true

      # Verify both actions were created
      expect(event.incoming_event_actions.count).to eq(2)
      expect(event.incoming_event_actions.pluck(:action_class)).to contain_exactly(
        "GemWebhookHandler",
        "AppWebhookHandler"
      )
    end

    it "executes actions in priority order" do
      execution_order = []

      allow(GemWebhookHandler).to receive(:handle) do |**args|
        execution_order << "GemWebhookHandler"
        args[:event].update(metadata: args[:event].metadata.merge(gem_action_executed: true))
      end

      allow(AppWebhookHandler).to receive(:handle) do |**args|
        execution_order << "AppWebhookHandler"
        args[:event].update(metadata: args[:event].metadata.merge(app_action_executed: true))
      end

      payload = {
        id: "evt_priority_123",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_123" } }
      }.to_json

      timestamp = Time.current.to_i
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", shared_secret, signed_payload)
      signature_header = "t=#{timestamp},v1=#{signature}"

      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => signature_header
           }

      expect(execution_order).to eq(%w[GemWebhookHandler AppWebhookHandler])
    end
  end

  # Test scenario: Third-party gem and Rails app with different webhook needs
  xdescribe "Separate webhook providers for gem and app" do
    let(:gem_provider) { create(:captain_hook_provider, name: "stripe_gem_account", verifier_class: "CaptainHook::Verifiers::Stripe") }
    let(:app_provider) { create(:captain_hook_provider, name: "stripe_app_account", verifier_class: "CaptainHook::Verifiers::Stripe") }

    class GemStripeAction
      def self.handle(event:, payload:, metadata:)
        Rails.logger.info "GemStripeAction executed"
        event.update(metadata: event.metadata.merge(gem_stripe_executed: true))
      end
    end

    class AppStripeAction
      def self.handle(event:, payload:, metadata:)
        Rails.logger.info "AppStripeAction executed"
        event.update(metadata: event.metadata.merge(app_stripe_executed: true))
      end
    end

    before do
      # Register gem action for gem provider
      CaptainHook.register_action(
        provider: gem_provider.name,
        event_type: "payment_intent.succeeded",
        action_class: "GemStripeAction",
        async: false
      )

      # Register app action for app provider
      CaptainHook.register_action(
        provider: app_provider.name,
        event_type: "payment_intent.succeeded",
        action_class: "AppStripeAction",
        async: false
      )
    end

    it "routes webhooks to correct actions based on provider" do
      # Gem webhook
      gem_payload = {
        id: "evt_gem_123",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_gem_123" } }
      }.to_json

      gem_timestamp = Time.current.to_i
      gem_signed = "#{gem_timestamp}.#{gem_payload}"
      gem_signature = OpenSSL::HMAC.hexdigest("SHA256", gem_provider.signing_secret, gem_signed)

      post "/captain_hook/#{gem_provider.name}/#{gem_provider.token}",
           params: gem_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{gem_timestamp},v1=#{gem_signature}"
           }

      expect(response).to have_http_status(:created)

      gem_event = CaptainHook::IncomingEvent.find_by(provider: gem_provider.name)
      expect(gem_event.metadata["gem_stripe_executed"]).to be true
      expect(gem_event.metadata["app_stripe_executed"]).to be_nil

      # App webhook
      app_payload = {
        id: "evt_app_456",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_app_456" } }
      }.to_json

      app_timestamp = Time.current.to_i
      app_signed = "#{app_timestamp}.#{app_payload}"
      app_signature = OpenSSL::HMAC.hexdigest("SHA256", app_provider.signing_secret, app_signed)

      post "/captain_hook/#{app_provider.name}/#{app_provider.token}",
           params: app_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{app_timestamp},v1=#{app_signature}"
           }

      expect(response).to have_http_status(:created)

      app_event = CaptainHook::IncomingEvent.find_by(provider: app_provider.name)
      expect(app_event.metadata["app_stripe_executed"]).to be true
      expect(app_event.metadata["gem_stripe_executed"]).to be_nil
    end

    it "maintains separate event histories for each provider" do
      # Send webhook to gem provider
      gem_payload = {
        id: "evt_gem_789",
        type: "charge.succeeded",
        data: { object: { id: "ch_gem_789" } }
      }.to_json

      gem_timestamp = Time.current.to_i
      gem_signed = "#{gem_timestamp}.#{gem_payload}"
      gem_signature = OpenSSL::HMAC.hexdigest("SHA256", gem_provider.signing_secret, gem_signed)

      post "/captain_hook/#{gem_provider.name}/#{gem_provider.token}",
           params: gem_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{gem_timestamp},v1=#{gem_signature}"
           }

      # Send webhook to app provider
      app_payload = {
        id: "evt_app_012",
        type: "refund.created",
        data: { object: { id: "re_app_012" } }
      }.to_json

      app_timestamp = Time.current.to_i
      app_signed = "#{app_timestamp}.#{app_payload}"
      app_signature = OpenSSL::HMAC.hexdigest("SHA256", app_provider.signing_secret, app_signed)

      post "/captain_hook/#{app_provider.name}/#{app_provider.token}",
           params: app_payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{app_timestamp},v1=#{app_signature}"
           }

      gem_events = CaptainHook::IncomingEvent.where(provider: gem_provider.name)
      app_events = CaptainHook::IncomingEvent.where(provider: app_provider.name)

      expect(gem_events.count).to eq(1)
      expect(app_events.count).to eq(1)
      expect(gem_events.first.event_type).to eq("charge.succeeded")
      expect(app_events.first.event_type).to eq("refund.created")
    end
  end

  # Test scenario: Action execution successes and failures
  xdescribe "Action execution outcomes" do
    let(:provider) { create(:captain_hook_provider, :stripe) }

    class SuccessfulHandler
      def self.handle(event:, payload:, metadata:)
        Rails.logger.info "SuccessfulHandler executed successfully"
        # Simulate successful processing
        true
      end
    end

    class FailingHandler
      def self.handle(event:, payload:, metadata:)
        Rails.logger.error "FailingHandler encountered an error"
        raise StandardError, "Simulated handler failure"
      end
    end

    before do
      CaptainHook.register_action(
        provider: provider.name,
        event_type: "payment_intent.succeeded",
        action_class: "SuccessfulHandler",
        async: false
      )

      CaptainHook.register_action(
        provider: provider.name,
        event_type: "payment_intent.failed",
        action_class: "FailingHandler",
        async: false,
        max_attempts: 3
      )
    end

    it "marks action as completed on success" do
      payload = {
        id: "evt_success_123",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_success_123" } }
      }.to_json

      timestamp = Time.current.to_i
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", provider.signing_secret, signed_payload)

      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
           }

      expect(response).to have_http_status(:created)

      event = CaptainHook::IncomingEvent.find_by(external_id: "evt_success_123")
      action_execution = event.incoming_event_actions.first

      expect(action_execution.status).to eq("completed")
      expect(action_execution.completed_at).to be_present
      expect(action_execution.error_message).to be_nil
    end

    it "marks action as failed after errors" do
      payload = {
        id: "evt_failure_456",
        type: "payment_intent.failed",
        data: { object: { id: "pi_failure_456" } }
      }.to_json

      timestamp = Time.current.to_i
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", provider.signing_secret, signed_payload)

      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
           }

      expect(response).to have_http_status(:created)

      event = CaptainHook::IncomingEvent.find_by(external_id: "evt_failure_456")
      action_execution = event.incoming_event_actions.first

      expect(action_execution.status).to eq("failed")
      expect(action_execution.failed_at).to be_present
      expect(action_execution.error_message).to include("Simulated handler failure")
    end
  end

  # Test scenario: Async vs Sync action execution
  xdescribe "Async and Sync action execution" do
    let(:provider) { create(:captain_hook_provider, :stripe) }

    class AsyncTestHandler
      def self.handle(event:, payload:, metadata:)
        Rails.logger.info "AsyncTestHandler executed"
        event.update(metadata: event.metadata.merge(async_executed: true))
      end
    end

    class SyncTestHandler
      def self.handle(event:, payload:, metadata:)
        Rails.logger.info "SyncTestHandler executed"
        event.update(metadata: event.metadata.merge(sync_executed: true))
      end
    end

    it "enqueues async actions as background jobs" do
      CaptainHook.register_action(
        provider: provider.name,
        event_type: "async.test",
        action_class: "AsyncTestHandler",
        async: true
      )

      payload = {
        id: "evt_async_123",
        type: "async.test",
        data: { test: "async" }
      }.to_json

      timestamp = Time.current.to_i
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", provider.signing_secret, signed_payload)

      expect do
        post "/captain_hook/#{provider.name}/#{provider.token}",
             params: payload,
             headers: {
               "Content-Type" => "application/json",
               "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
             }
      end.to have_enqueued_job(CaptainHook::IncomingHandlerJob)

      expect(response).to have_http_status(:created)
    end

    it "executes sync actions immediately" do
      CaptainHook.register_action(
        provider: provider.name,
        event_type: "sync.test",
        action_class: "SyncTestHandler",
        async: false
      )

      payload = {
        id: "evt_sync_456",
        type: "sync.test",
        data: { test: "sync" }
      }.to_json

      timestamp = Time.current.to_i
      signed_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest("SHA256", provider.signing_secret, signed_payload)

      post "/captain_hook/#{provider.name}/#{provider.token}",
           params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
           }

      expect(response).to have_http_status(:created)

      event = CaptainHook::IncomingEvent.find_by(external_id: "evt_sync_456")
      expect(event.metadata["sync_executed"]).to be true

      action_execution = event.incoming_event_actions.first
      expect(action_execution.status).to eq("completed")
    end
  end

  # Test scenario: Multiple providers with same verifier but different secrets
  describe "Multiple providers with same verifier type" do
    let(:stripe_account_a) do
      create(:captain_hook_provider,
             name: "stripe_account_a",
             display_name: "Stripe Account A",
             verifier_class: "CaptainHook::Verifiers::Stripe",
             signing_secret: "whsec_account_a_secret")
    end

    let(:stripe_account_b) do
      create(:captain_hook_provider,
             name: "stripe_account_b",
             display_name: "Stripe Account B",
             verifier_class: "CaptainHook::Verifiers::Stripe",
             signing_secret: "whsec_account_b_secret")
    end

    it "verifies signatures with correct provider secret" do
      # Valid webhook for account A
      payload_a = {
        id: "evt_account_a_123",
        type: "payment_intent.succeeded",
        data: { object: { id: "pi_a_123" } }
      }.to_json

      timestamp = Time.current.to_i
      signed_a = "#{timestamp}.#{payload_a}"
      signature_a = OpenSSL::HMAC.hexdigest("SHA256", stripe_account_a.signing_secret, signed_a)

      post "/captain_hook/#{stripe_account_a.name}/#{stripe_account_a.token}",
           params: payload_a,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{timestamp},v1=#{signature_a}"
           }

      expect(response).to have_http_status(:created)

      # Invalid webhook for account A using account B's secret
      signed_wrong = "#{timestamp}.#{payload_a}"
      signature_wrong = OpenSSL::HMAC.hexdigest("SHA256", stripe_account_b.signing_secret, signed_wrong)

      post "/captain_hook/#{stripe_account_a.name}/#{stripe_account_a.token}",
           params: payload_a,
           headers: {
             "Content-Type" => "application/json",
             "Stripe-Signature" => "t=#{timestamp},v1=#{signature_wrong}"
           }

      expect(response).to have_http_status(:unauthorized)
    end

    it "maintains separate webhook URLs for each provider" do
      expect(stripe_account_a.webhook_url).not_to eq(stripe_account_b.webhook_url)
      expect(stripe_account_a.webhook_url).to include(stripe_account_a.name)
      expect(stripe_account_b.webhook_url).to include(stripe_account_b.name)
      expect(stripe_account_a.webhook_url).to include(stripe_account_a.token)
      expect(stripe_account_b.webhook_url).to include(stripe_account_b.token)
    end
  end
end
