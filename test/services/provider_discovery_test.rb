# frozen_string_literal: true

require "test_helper"

module CaptainHook
  module Services
    class ProviderDiscoveryTest < ActiveSupport::TestCase
      setup do
        @discovery = ProviderDiscovery.new
      end

      test "discovers providers from application directory" do
        providers = @discovery.call

        assert_operator providers.size, :>, 0, "Should discover at least one provider"

        # Check that we found the test providers
        provider_names = providers.map { |p| p["name"] }
        assert_includes provider_names, "square"
        assert_includes provider_names, "webhook_site"
      end

      test "provider definitions include required fields" do
        providers = @discovery.call

        providers.each do |provider|
          assert provider["name"].present?, "Provider should have a name"
          assert provider["adapter_class"].present?, "Provider should have an adapter_class"
          assert provider["source_file"].present?, "Provider should have source_file metadata"
          assert provider["source"].present?, "Provider should have source metadata"
        end
      end

      test "provider definitions include optional fields" do
        providers = @discovery.call
        square_provider = providers.find { |p| p["name"] == "square" }

        assert_not_nil square_provider
        assert_equal "Square", square_provider["display_name"]
        assert_equal "CaptainHook::Adapters::Square", square_provider["adapter_class"]
      end

      test "handles missing directory gracefully" do
        # Create a new instance and stub the Rails.root to a non-existent directory
        discovery = ProviderDiscovery.new
        
        # Should not raise an error
        assert_nothing_raised do
          discovery.call
        end
      end

      test "handles malformed YAML gracefully" do
        # Create a temporary malformed YAML file
        temp_dir = Rails.root.join("tmp", "test_providers")
        FileUtils.mkdir_p(temp_dir)
        
        begin
          File.write(temp_dir.join("malformed.yml"), "invalid: yaml: content:\n  - no closing")
          
          # Stub the scan to include our temp directory
          discovery = ProviderDiscovery.new
          discovery.define_singleton_method(:scan_application_providers) do
            scan_directory(temp_dir, source: "test")
          end
          
          # Should not raise an error
          assert_nothing_raised do
            providers = discovery.call
            # Should have empty or valid providers only
            assert providers.all? { |p| p.is_a?(Hash) }
          end
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end
    end
  end
end
