# frozen_string_literal: true

require "rails_helper"

RSpec.describe CaptainHook::Provider, type: :model do
  describe "validations" do
    subject { build(:captain_hook_provider) }

    it { is_expected.to validate_presence_of(:name) }

    # Token has presence validation but also has auto-generation callback
    # So we test that token is set after save even if not provided
    it "ensures token is present after save" do
      provider = build(:captain_hook_provider, token: nil)
      expect(provider).to be_valid
      provider.save!
      expect(provider.token).to be_present
    end

    # Uniqueness validations exist but can't be tested with shoulda-matchers due to encryption
    it "validates uniqueness of name" do
      create(:captain_hook_provider, name: "test_provider")
      provider2 = build(:captain_hook_provider, name: "test_provider")
      expect(provider2).not_to be_valid
      expect(provider2.errors[:name]).to be_present
    end

    it "validates uniqueness of token" do
      provider1 = create(:captain_hook_provider)
      provider2 = build(:captain_hook_provider, token: provider1.token)
      expect(provider2).not_to be_valid
      expect(provider2.errors[:token]).to be_present
    end

    it "validates name format" do
      # Test empty name - normalization will make it empty string which fails presence validation
      provider = build(:captain_hook_provider, name: "")
      expect(provider).not_to be_valid
      expect(provider.errors[:name]).to be_present
    end

    it "validates rate_limit_requests is positive" do
      provider = build(:captain_hook_provider, rate_limit_requests: -1)
      expect(provider).not_to be_valid
    end

    it "validates rate_limit_period is positive" do
      provider = build(:captain_hook_provider, rate_limit_period: -1)
      expect(provider).not_to be_valid
    end
  end

  describe "callbacks" do
    it "normalizes name before validation" do
      provider = build(:captain_hook_provider, name: "Test-Provider-123")
      provider.valid?
      expect(provider.name).to eq("test_provider_123")
    end

    it "generates token before validation if not present" do
      provider = build(:captain_hook_provider, token: nil)
      provider.valid?
      expect(provider.token).to be_present
      expect(provider.token.length).to be > 20
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:incoming_events).with_primary_key(:name).with_foreign_key(:provider) }
    it { is_expected.to have_many(:actions).with_primary_key(:name).with_foreign_key(:provider) }
  end

  describe "scopes" do
    let!(:active_provider) { create(:captain_hook_provider, active: true) }
    let!(:inactive_provider) { create(:captain_hook_provider, :inactive) }

    describe ".active" do
      it "returns only active providers" do
        expect(described_class.active).to include(active_provider)
        expect(described_class.active).not_to include(inactive_provider)
      end
    end

    describe ".inactive" do
      it "returns only inactive providers" do
        expect(described_class.inactive).to include(inactive_provider)
        expect(described_class.inactive).not_to include(active_provider)
      end
    end

    describe ".by_name" do
      it "orders providers by name" do
        create(:captain_hook_provider, name: "aaa_provider")
        create(:captain_hook_provider, name: "zzz_provider")

        providers = described_class.by_name
        expect(providers.first.name).to eq("aaa_provider")
        expect(providers.last.name).to eq("zzz_provider")
      end
    end
  end

  describe "#webhook_url" do
    let(:provider) { create(:captain_hook_provider, name: "test_provider") }

    it "generates webhook URL with provider name and token" do
      url = provider.webhook_url
      expect(url).to include("captain_hook")
      expect(url).to include(provider.name)
      expect(url).to include(provider.token)
    end

    it "uses custom base URL if provided" do
      url = provider.webhook_url(base_url: "https://custom.example.com")
      expect(url).to start_with("https://custom.example.com")
    end

    it "detects GitHub Codespaces environment" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CODESPACES").and_return("true")
      allow(ENV).to receive(:[]).with("CODESPACE_NAME").and_return("test-codespace")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("PORT", "3004").and_return("3000")

      url = provider.webhook_url
      # The actual codespace name format uses the PORT that's configured
      expect(url).to include("-3000.app.github.dev")
    end

    it "uses APP_URL environment variable if set" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("APP_URL").and_return("https://app-url.example.com")

      url = provider.webhook_url
      expect(url).to start_with("https://app-url.example.com")
    end
  end

  describe "#rate_limiting_enabled?" do
    it "returns true when both rate_limit_requests and rate_limit_period are present" do
      provider = build(:captain_hook_provider, :with_rate_limiting)
      expect(provider.rate_limiting_enabled?).to be true
    end

    it "returns false when rate_limit_requests is nil" do
      provider = build(:captain_hook_provider, rate_limit_requests: nil, rate_limit_period: 60)
      expect(provider.rate_limiting_enabled?).to be false
    end

    it "returns false when rate_limit_period is nil" do
      provider = build(:captain_hook_provider, rate_limit_requests: 100, rate_limit_period: nil)
      expect(provider.rate_limiting_enabled?).to be false
    end
  end

  describe "#activate!" do
    let(:provider) { create(:captain_hook_provider, active: false) }

    it "sets active to true" do
      expect { provider.activate! }.to change { provider.active }.from(false).to(true)
    end
  end

  describe "#deactivate!" do
    let(:provider) { create(:captain_hook_provider, active: true) }

    it "sets active to false" do
      expect { provider.deactivate! }.to change { provider.active }.from(true).to(false)
    end
  end
end
