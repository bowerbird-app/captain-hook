# frozen_string_literal: true

module CaptainHook
  # Configuration for a webhook provider
  # Stores settings for rate limiting, payload size, timestamp tolerance, etc.
  ProviderConfig = Struct.new(
    :name,
    :display_name,
    :description,
    :token,
    :signing_secret,
    :webhook_url,
    :timestamp_tolerance_seconds,
    :max_payload_size_bytes,
    :rate_limit_requests,
    :rate_limit_period,
    :adapter_class,
    :adapter_file,
    :active,
    :source,
    :source_file,
    keyword_init: true
  ) do
    def initialize(config_hash = nil, **kwargs)
      # Support both hash and keyword arguments
      kwargs = config_hash.symbolize_keys.merge(kwargs) if config_hash.is_a?(Hash)

      # Validate name is provided when config is completely empty
      if (config_hash.nil? || (config_hash.is_a?(Hash) && config_hash.empty?)) && kwargs.empty?
        raise ArgumentError, "name is required"
      end

      # Convert string numbers to integers (handle both symbol and string keys)
      %i[timestamp_tolerance_seconds rate_limit_requests rate_limit_period max_payload_size_bytes].each do |key|
        string_key = key.to_s
        if kwargs.key?(key) && kwargs[key].is_a?(String) && !kwargs[key].empty?
          kwargs[key] = kwargs[key].to_i
        elsif kwargs.key?(string_key) && kwargs[string_key].is_a?(String) && !kwargs[string_key].empty?
          kwargs[string_key.to_sym] = kwargs.delete(string_key).to_i
        end
      end

      super(**kwargs)
      self.display_name ||= name&.titleize unless display_name.nil? # Keep explicit nil
      self.active = true if active.nil?
      self.timestamp_tolerance_seconds ||= 300 # 5 minutes default
      self.max_payload_size_bytes ||= 1_048_576 # 1MB default
      self.rate_limit_requests ||= 100 # 100 requests
      self.rate_limit_period ||= 60 # per 60 seconds
      self.adapter_class ||= "CaptainHook::Adapters::Base"
    end

    # Check if provider is active
    def active?
      active == true
    end

    # Resolve signing secret (handle ENV variables)
    # Supports format: ENV[VARIABLE_NAME]
    def resolve_signing_secret
      return nil if signing_secret.blank?

      if signing_secret.match?(/\AENV\[(\w+)\]\z/)
        var_name = signing_secret.match(/\AENV\[(\w+)\]\z/)[1]
        ENV.fetch(var_name, nil)
      else
        signing_secret
      end
    end

    # source_file is stored as a struct attribute, no need to override

    # Convert to hash
    def to_h
      super.compact.transform_keys(&:to_s)
    end

    # Array access support
    def [](key)
      key_sym = key.to_sym
      public_send(key_sym) if respond_to?(key_sym)
    end

    # Check if rate limiting is enabled
    def rate_limiting_enabled?
      rate_limit_requests.present? && rate_limit_period.present?
    end

    # Check if timestamp tolerance is enabled
    def timestamp_validation_enabled?
      timestamp_tolerance_seconds.present? && timestamp_tolerance_seconds.positive?
    end

    # Check if payload size limit is enabled
    def payload_size_limit_enabled?
      max_payload_size_bytes.present? && max_payload_size_bytes.positive?
    end

    # Get the adapter instance
    def adapter
      # Try to find and load the adapter file if the class doesn't exist yet
      load_adapter_file unless Object.const_defined?(adapter_class)

      @adapter ||= adapter_class.constantize.new
    rescue NameError => e
      Rails.logger.error("Failed to load adapter #{adapter_class}: #{e.message}")
      raise CaptainHook::AdapterNotFoundError,
            "Adapter #{adapter_class} not found. Ensure the adapter file exists in the provider directory."
    end

    # Load the adapter file from the filesystem
    def load_adapter_file
      # Try to find the adapter file in common locations
      possible_paths = [
        # Application providers directory (nested structure)
        Rails.root.join("captain_hook", "providers", name, "#{name}.rb"),
        # Application providers directory (flat structure)
        Rails.root.join("captain_hook", "providers", "#{name}.rb")
      ]

      # Also check in loaded gems
      Bundler.load.specs.each do |spec|
        gem_providers_path = File.join(spec.full_gem_path, "captain_hook", "providers")
        next unless Dir.exist?(gem_providers_path)

        possible_paths << File.join(gem_providers_path, name, "#{name}.rb")
        possible_paths << File.join(gem_providers_path, "#{name}.rb")
      end

      adapter_file = possible_paths.find { |path| File.exist?(path) }

      if adapter_file
        load adapter_file
        Rails.logger.debug("Loaded adapter from #{adapter_file}")
      else
        Rails.logger.warn("Adapter file not found for #{name}, tried: #{possible_paths.inspect}")
      end
    rescue StandardError => e
      Rails.logger.error("Failed to load adapter file: #{e.message}")
    end
  end
end
