# frozen_string_literal: true

module CaptainHook
  # Reusable helper methods for webhook verifiers
  # Can be included in any verifier class to get security and utility methods
  #
  # Usage:
  #   class MyVerifier
  #     include CaptainHook::VerifierHelpers
  #
  #     def verify_signature(payload:, headers:, provider_config:)
  #       signature = extract_header(headers, "X-Signature")
  #       expected = generate_hmac(provider_config.signing_secret, payload)
  #       secure_compare(signature, expected)
  #     end
  #   end
  module VerifierHelpers
    # Constant-time string comparison to prevent timing attacks
    # Uses Rack::Utils.secure_compare if available, falls back to manual implementation
    def secure_compare(a, b)
      return false if a.blank? || b.blank?
      return false if a.bytesize != b.bytesize

      l = a.unpack("C*")
      r = b.unpack("C*")

      result = 0
      l.zip(r) { |x, y| result |= x ^ y }
      result.zero?
    end

    # Check if signature verification should be skipped
    # Returns true if signing_secret is blank or contains ENV placeholder
    def skip_verification?(signing_secret)
      signing_secret.blank? || signing_secret.start_with?("ENV[")
    end

    # Generate HMAC-SHA256 signature (hex-encoded)
    # @param secret [String] The signing secret
    # @param data [String] The data to sign
    # @return [String] Hex-encoded HMAC signature
    def generate_hmac(secret, data)
      OpenSSL::HMAC.hexdigest("SHA256", secret, data)
    end

    # Generate HMAC-SHA256 signature (Base64-encoded)
    # @param secret [String] The signing secret
    # @param data [String] The data to sign
    # @return [String] Base64-encoded HMAC signature
    def generate_hmac_base64(secret, data)
      Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, data))
    end

    # Extract header value with case-insensitive matching
    # Tries multiple keys in order and returns first non-blank value
    # @param headers [Hash] Request headers
    # @param keys [Array<String>] Header keys to try
    # @return [String, nil] Header value or nil
    def extract_header(headers, *keys)
      keys.each do |key|
        value = headers[key] || headers[key.downcase] || headers[key.upcase]
        return value if value.present?
      end
      nil
    end

    # Parse key-value header (e.g., "t=123,v1=abc,v0=xyz")
    # @param header_value [String] Header value to parse
    # @return [Hash] Parsed key-value pairs
    def parse_kv_header(header_value)
      return {} if header_value.blank?

      header_value.split(",").each_with_object({}) do |pair, hash|
        key, value = pair.split("=", 2)
        next if key.blank? || value.blank?

        key = key.strip
        value = value.strip

        # Handle multiple values for same key (e.g., v1=abc,v0=xyz)
        if hash.key?(key)
          hash[key] = [hash[key]] unless hash[key].is_a?(Array)
          hash[key] << value
        else
          hash[key] = value
        end
      end
    end

    # Check if timestamp is within acceptable tolerance
    # @param timestamp [Integer] Unix timestamp to check
    # @param tolerance [Integer] Maximum age in seconds
    # @return [Boolean] True if timestamp is recent enough
    def timestamp_within_tolerance?(timestamp, tolerance)
      return false if timestamp.nil?

      current_time = Time.current.to_i
      age = (current_time - timestamp).abs
      age <= tolerance
    end

    # Parse timestamp from various formats
    # Supports Unix timestamps, ISO8601, RFC3339
    # @param time_string [String, Integer] Timestamp to parse
    # @return [Integer, nil] Unix timestamp or nil
    def parse_timestamp(time_string)
      return nil if time_string.blank?
      return time_string.to_i if time_string.is_a?(Integer)
      return time_string.to_i if time_string.to_s.match?(/^\d+$/)

      # Try parsing as ISO8601/RFC3339
      Time.parse(time_string).to_i
    rescue ArgumentError
      nil
    end

    # Log signature verification details
    # @param provider [String] Provider name
    # @param details [Hash] Details to log
    def log_verification(provider, details)
      return unless CaptainHook.configuration.debug_mode

      message = "[#{provider.upcase}] Signature Verification:"
      details.each do |key, value|
        message += "\n  #{key}: #{value}"
      end
      Rails.logger.debug(message)
    end

    # Build full webhook URL
    # @param path [String] Webhook path (e.g., "/captain_hook/stripe")
    # @param provider_token [String, nil] Optional provider token
    # @return [String] Full webhook URL
    def build_webhook_url(path, provider_token: nil)
      base_url = ENV["WEBHOOK_BASE_URL"] || "https://#{ENV.fetch('HOST', nil)}"
      url = "#{base_url}#{path}"
      url += "?token=#{provider_token}" if provider_token.present?
      url
    end
  end
end
