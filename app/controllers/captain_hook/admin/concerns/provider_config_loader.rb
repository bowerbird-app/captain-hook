# frozen_string_literal: true

module CaptainHook
  module Admin
    module Concerns
      # Concern for loading provider configuration from registry
      # Extracts common pattern of:
      # 1. Running ProviderDiscovery
      # 2. Finding provider config data
      # 3. Creating ProviderConfig object
      #
      # Usage:
      #   class MyController < BaseController
      #     include ProviderConfigLoader
      #
      #     def show
      #       @registry_config = load_registry_config_for_provider(@provider.name)
      #     end
      #   end
      module ProviderConfigLoader
        extend ActiveSupport::Concern

        private

        # Load provider configuration from registry by provider name
        # Returns CaptainHook::ProviderConfig or nil if not found
        #
        # @param provider_name [String] The provider name (e.g., "stripe")
        # @return [CaptainHook::ProviderConfig, nil] Provider configuration or nil
        def load_registry_config_for_provider(provider_name)
          return nil if provider_name.blank?

          # Use Configuration's provider method which handles discovery and caching
          CaptainHook.configuration.provider(provider_name)
        end

        # Discover all provider definitions from filesystem
        # Returns array of provider config data hashes
        #
        # @return [Array<Hash>] Array of provider configuration hashes
        def discover_all_providers
          discovery = CaptainHook::Services::ProviderDiscovery.new
          discovery.call
        end

        # Load all providers as ProviderConfig objects
        # Useful for index pages that list all providers
        #
        # @return [Array<CaptainHook::ProviderConfig>] Array of provider configurations
        def load_all_provider_configs
          provider_definitions = discover_all_providers

          provider_definitions.map do |config_data|
            CaptainHook::ProviderConfig.new(config_data)
          end.sort_by(&:name)
        end

        # Find raw provider config data by name
        # Returns hash of provider configuration before being wrapped in ProviderConfig
        #
        # @param provider_name [String] The provider name
        # @return [Hash, nil] Raw provider configuration hash or nil
        def find_provider_config_data(provider_name)
          provider_definitions = discover_all_providers
          provider_definitions.find { |p| p["name"] == provider_name }
        end
      end
    end
  end
end
