# frozen_string_literal: true

require_relative "hooks"
require_relative "action_registry"
require_relative "provider_config"

module CaptainHook
  class Configuration
    attr_accessor :admin_parent_controller, :admin_layout, :retention_days
    attr_reader :hooks, :action_registry, :providers

    def initialize
      @admin_parent_controller = "ApplicationController"
      @admin_layout = "application"
      @retention_days = 90 # Default retention period
      @hooks = Hooks.new
      @action_registry = ActionRegistry.new
      @providers = {}
    end

    # Register a provider configuration (for backward compatibility)
    # Note: Providers should now be managed via the Provider model in the database
    def register_provider(name, **)
      @providers[name.to_s] = ProviderConfig.new(name: name.to_s, **)
    end

    # Get a provider configuration (combines DB, registry, and global config)
    def provider(name)
      provider_name = name.to_s

      # Get provider from database for token, rate limits, and active status
      db_provider = CaptainHook::Provider.find_by(name: provider_name)

      # If no DB provider but we have in-memory registration, return that
      return @providers[provider_name] if db_provider.nil? && @providers.key?(provider_name)

      return nil unless db_provider

      # Get registry definition for verifier, signing secret, display name, description
      registry_definition = find_registry_definition(provider_name)

      # Build combined config
      build_provider_config(db_provider, registry_definition)
    end

    private

    # Find provider definition in registry (YAML files)
    def find_registry_definition(provider_name)
      @registry_cache ||= {}

      # First check in-memory registered providers
      if @providers.key?(provider_name)
        memory_provider = @providers[provider_name]
        return {
          "name" => memory_provider.name,
          "display_name" => memory_provider.display_name,
          "description" => memory_provider.description,
          "verifier_class" => memory_provider.verifier_class,
          "verifier_file" => memory_provider.verifier_file,
          "signing_secret" => memory_provider.raw_signing_secret,
          "timestamp_tolerance_seconds" => memory_provider.timestamp_tolerance_seconds,
          "max_payload_size_bytes" => memory_provider.max_payload_size_bytes,
          "source" => "memory"
        }
      end

      # Cache registry lookups to avoid repeated file scans
      unless @registry_cache.key?(provider_name)
        provider_definitions = CaptainHook::Services::ProviderDiscovery.new.call
        @registry_cache[provider_name] = provider_definitions.find { |p| p["name"] == provider_name }
      end

      @registry_cache[provider_name]
    end

    # Build ProviderConfig from database provider and registry definition
    def build_provider_config(db_provider, registry_definition)
      config_attrs = {
        name: db_provider.name,
        token: db_provider.token,
        active: db_provider.active,
        rate_limit_requests: db_provider.rate_limit_requests,
        rate_limit_period: db_provider.rate_limit_period
      }

      # Add registry attributes if available
      if registry_definition
        config_attrs.merge!(
          display_name: registry_definition["display_name"],
          description: registry_definition["description"],
          verifier_file: registry_definition["verifier_file"],
          verifier_class: extract_verifier_class(registry_definition),
          signing_secret: registry_definition["signing_secret"],
          timestamp_tolerance_seconds: registry_definition["timestamp_tolerance_seconds"],
          max_payload_size_bytes: registry_definition["max_payload_size_bytes"],
          source: registry_definition["source"],
          source_file: registry_definition["source_file"]
        )
      else
        # Fallback defaults if not in registry
        config_attrs.merge!(
          display_name: db_provider.name.titleize,
          verifier_class: "CaptainHook::Verifiers::Base"
        )
      end

      ProviderConfig.new(**config_attrs)
    end

    # Extract verifier class name from registry definition
    def extract_verifier_class(definition)
      return definition["verifier_class"] if definition["verifier_class"].present?

      verifier_file = definition["verifier_file"]
      name = definition["name"]
      return nil if verifier_file.blank?

      # Find the file in possible locations
      possible_paths = [
        Rails.root.join("captain_hook", name, verifier_file),
        Rails.root.join("captain_hook", "providers", name, verifier_file),
        Rails.root.join("captain_hook", "providers", verifier_file)
      ]

      # Check in CaptainHook gem's built-in verifiers
      gem_verifiers_path = File.expand_path("../verifiers", __dir__)
      possible_paths << File.join(gem_verifiers_path, verifier_file) if Dir.exist?(gem_verifiers_path)

      # Also check in other gems
      if defined?(Bundler)
        Bundler.load.specs.each do |spec|
          gem_captain_hook_path = File.join(spec.gem_dir, "captain_hook")
          next unless File.directory?(gem_captain_hook_path)

          possible_paths << File.join(gem_captain_hook_path, name, verifier_file)
          possible_paths << File.join(gem_captain_hook_path, "providers", name, verifier_file)
          possible_paths << File.join(gem_captain_hook_path, "providers", verifier_file)
        end
      end

      file_path = possible_paths.find { |path| File.exist?(path) }

      if file_path
        CaptainHook::Provider.extract_verifier_class_from_file(file_path)
      else
        "CaptainHook::Verifiers::Base"
      end
    end

    public

    def to_h
      {
        admin_parent_controller: admin_parent_controller,
        admin_layout: admin_layout,
        retention_days: retention_days,
        providers: @providers.keys,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each do |k, v|
        key = k.to_s
        setter = "#{key}="
        public_send(setter, v) if respond_to?(setter)
      end
    end
  end
end
