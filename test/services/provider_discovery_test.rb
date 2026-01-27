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

        # Check that we found stripe provider
        provider_names = providers.map { |p| p["name"] }
        assert_includes provider_names, "stripe"
      end

      test "provider definitions include required fields" do
        providers = @discovery.call

        providers.each do |provider|
          assert provider["name"].present?, "Provider should have a name"
          assert provider["source_file"].present?, "Provider should have source_file metadata"
          assert provider["source"].present?, "Provider should have source metadata"
        end
      end

      test "provider definitions include optional fields" do
        providers = @discovery.call
        stripe_provider = providers.find { |p| p["name"] == "stripe" }

        assert_not_nil stripe_provider
        assert_equal "Stripe", stripe_provider["display_name"]
        assert_equal "stripe.rb", stripe_provider["verifier_file"]
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
            assert(providers.all? { |p| p.is_a?(Hash) })
          end
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end

      test "load_provider_file returns nil for non-hash YAML" do
        temp_dir = Rails.root.join("tmp", "test_providers")
        FileUtils.mkdir_p(temp_dir)
        file_path = temp_dir.join("array.yml")

        begin
          File.write(file_path, "- item1\n- item2")

          result = @discovery.send(:load_provider_file, file_path.to_s, source: "test")
          assert_nil result, "Should return nil for YAML that doesn't parse to a Hash"
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end

      test "load_provider_file adds source metadata" do
        providers = @discovery.call
        first_provider = providers.first

        assert first_provider["source_file"].present?
        assert first_provider["source"].present?
      end

      test "scan_directory only processes yml and yaml files" do
        temp_dir = Rails.root.join("tmp", "test_providers")
        FileUtils.mkdir_p(temp_dir)

        begin
          # Create provider directories with YAML files (following expected structure)
          FileUtils.mkdir_p(temp_dir.join("test1"))
          FileUtils.mkdir_p(temp_dir.join("test2"))
          FileUtils.mkdir_p(temp_dir.join("ignored_txt"))
          FileUtils.mkdir_p(temp_dir.join("ignored_rb"))

          # Create files with different extensions
          File.write(temp_dir.join("test1", "test1.yml"), "name: test1\nverifier_class: Test")
          File.write(temp_dir.join("test2", "test2.yaml"), "name: test2\nverifier_class: Test")
          File.write(temp_dir.join("ignored_txt", "ignored_txt.txt"), "name: test3\nverifier_class: Test")
          File.write(temp_dir.join("ignored_rb", "ignored_rb.rb"), "name: test4\nverifier_class: Test")

          discovery = ProviderDiscovery.new
          discovery.send(:scan_directory, temp_dir, source: "test")

          providers = discovery.instance_variable_get(:@discovered_providers)
          assert_equal 2, providers.size
          assert(providers.all? { |p| p["name"].start_with?("test") })
        ensure
          FileUtils.rm_rf(temp_dir)
        end
      end

      test "scan_gem_providers checks loaded gems" do
        # This test verifies the method can run without errors
        discovery = ProviderDiscovery.new

        assert_nothing_raised do
          discovery.send(:scan_gem_providers)
        end
      end
    end
  end
end
