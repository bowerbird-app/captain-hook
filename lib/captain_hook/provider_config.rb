# frozen_string_literal: true

module CaptainHook
  # Configuration for a webhook provider
  # Stores settings for rate limiting, payload size, timestamp tolerance, etc.
  ProviderConfig = Struct.new(
    :name,
    :display_name,
    :description,
    :token,
    :raw_signing_secret, # Changed from :signing_secret to store raw value
    :webhook_url,
    :timestamp_tolerance_seconds,
    :max_payload_size_bytes,
    :rate_limit_requests,
    :rate_limit_period,
    :verifier_class,
    :verifier_file,
    :active,
    :source,
    :source_file,
    keyword_init: true
  ) do
    def initialize(config_hash = nil, **kwargs)
      # Support both hash and keyword arguments
      kwargs = config_hash.symbolize_keys.merge(kwargs) if config_hash.is_a?(Hash)

      # Map 'signing_secret' to 'raw_signing_secret'
      if kwargs.key?(:signing_secret)
        kwargs[:raw_signing_secret] = kwargs.delete(:signing_secret)
      elsif kwargs.key?("signing_secret")
        kwargs[:raw_signing_secret] = kwargs.delete("signing_secret")
      end

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

      # PRIORITY ORDER:
      # 1. captain_hook.yml providers/<name> (highest)
      # 2. stripe.yml value (provider YAML)
      # 3. captain_hook.yml defaults (only if stripe.yml is nil)
      if defined?(CaptainHook::Services::GlobalConfigLoader) && kwargs[:name].present?
        provider_name = kwargs[:name]

        # Store provider YAML values (from stripe.yml)
        provider_yaml_timestamp = kwargs[:timestamp_tolerance_seconds]
        provider_yaml_max_size = kwargs[:max_payload_size_bytes]

        # Check captain_hook.yml for provider-specific overrides ONLY
        config_instance = CaptainHook::Services::GlobalConfigLoader.new
        global_config = config_instance.call

        provider_override_timestamp = global_config.dig("providers", provider_name, "timestamp_tolerance_seconds")
        provider_override_max_size = global_config.dig("providers", provider_name, "max_payload_size_bytes")

        # Priority: provider override > stripe.yml > global defaults
        kwargs[:timestamp_tolerance_seconds] =
          provider_override_timestamp || provider_yaml_timestamp || global_config.dig("defaults",
                                                                                      "timestamp_tolerance_seconds")
        kwargs[:max_payload_size_bytes] =
          provider_override_max_size || provider_yaml_max_size || global_config.dig("defaults",
                                                                                    "max_payload_size_bytes")
      end

      super(**kwargs)

      # Set defaults
      self.display_name ||= name&.titleize unless display_name.nil? # Keep explicit nil
      self.active = true if active.nil?
      self.verifier_class ||= "CaptainHook::Verifiers::Base"

      # Apply fallback defaults if still not set (after global config override)
      self.timestamp_tolerance_seconds ||= 300 # 5 minutes default
      self.max_payload_size_bytes ||= 1_048_576 # 1MB default

      # Rate limiting defaults (not in global config, provider-specific)
      self.rate_limit_requests ||= 100 # 100 requests
      self.rate_limit_period ||= 60 # per 60 seconds
    end

    # Check if provider is active
    def active?
      active == true
    end

    # Get signing secret and automatically resolve ENV variables
    # Supports format: ENV[VARIABLE_NAME]
    def signing_secret
      return nil if raw_signing_secret.blank?

      if raw_signing_secret.match?(/\AENV\[(\w+)\]\z/)
        var_name = raw_signing_secret.match(/\AENV\[(\w+)\]\z/)[1]
        ENV.fetch(var_name, nil)
      else
        raw_signing_secret
      end
    end

    # Alias for backward compatibility
    alias_method :resolve_signing_secret, :signing_secret

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

    # Get the verifier instance
    def verifier
      # Try to constantize the verifier class first (it might be a built-in verifier)
      begin
        return @verifier ||= verifier_class.constantize.new
      rescue NameError
        # Class doesn't exist yet, try to load from file
      end

      # Try to find and load the verifier file if the class doesn't exist yet
      load_verifier_file

      @verifier ||= verifier_class.constantize.new
    rescue NameError => e
      Rails.logger.error("Failed to load verifier #{verifier_class}: #{e.message}")
      raise CaptainHook::VerifierNotFoundError,
            "Verifier #{verifier_class} not found. Ensure the verifier file exists in the provider directory or use a built-in verifier (CaptainHook::Verifiers::Base, Stripe, Square, Paypal, WebhookSite)."
    end

    # Load the verifier file from the filesystem
    def load_verifier_file
      return if verifier_file.blank?

      # Try to find the verifier file in common locations
      possible_paths = [
        # Application providers directory (nested structure)
        Rails.root.join("captain_hook", "providers", name, verifier_file),
        # Application providers directory (flat structure)
        Rails.root.join("captain_hook", "providers", verifier_file)
      ]

      # Check in CaptainHook gem's built-in verifiers
      gem_verifiers_path = File.expand_path("../verifiers", __dir__)
      possible_paths << File.join(gem_verifiers_path, verifier_file) if Dir.exist?(gem_verifiers_path)

      # Also check in other loaded gems
      Bundler.load.specs.each do |spec|
        gem_providers_path = File.join(spec.full_gem_path, "captain_hook", "providers")
        next unless Dir.exist?(gem_providers_path)

        possible_paths << File.join(gem_providers_path, name, verifier_file)
        possible_paths << File.join(gem_providers_path, verifier_file)
      end

      file_path = possible_paths.find { |path| File.exist?(path) }

      if file_path
        load file_path
        Rails.logger.debug("Loaded verifier from #{file_path}")
      else
        Rails.logger.warn("Verifier file not found for #{name}, tried: #{possible_paths.inspect}")
      end
    rescue StandardError => e
      Rails.logger.error("Failed to load verifier file: #{e.message}")
    end
  end
end
