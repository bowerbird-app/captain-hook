# frozen_string_literal: true

require "openssl"
require "json"

module CaptainHook
  # Generates HMAC-SHA256 signatures for outgoing webhooks
  # Implements: HMAC_SHA256(timestamp.canonical_json)
  class SignatureGenerator
    attr_reader :secret

    def initialize(secret)
      @secret = secret
    end

    # Generate signature for payload
    # @param payload [Hash] The webhook payload
    # @param timestamp [Integer, nil] Unix timestamp (defaults to current time)
    # @return [Hash] Hash containing signature, timestamp, and signed_data
    def generate(payload, timestamp: nil)
      timestamp ||= Time.current.to_i

      # Convert payload to canonical JSON (sorted keys)
      canonical_json = canonical_json(payload)

      # Create signed data: timestamp.json
      signed_data = "#{timestamp}.#{canonical_json}"

      # Generate HMAC signature
      signature = OpenSSL::HMAC.hexdigest("SHA256", secret, signed_data)

      {
        signature: signature,
        timestamp: timestamp,
        signed_data: signed_data
      }
    end

    # Verify a signature
    # @param payload [Hash] The webhook payload
    # @param signature [String] The signature to verify
    # @param timestamp [Integer] The timestamp used in signing
    # @param tolerance [Integer] Tolerance in seconds for timestamp validation
    # @return [Boolean] true if signature is valid
    def verify(payload:, signature:, timestamp:, tolerance: 300)
      # Check timestamp tolerance
      return false unless timestamp_valid?(timestamp, tolerance)

      # Regenerate signature
      expected = generate(payload, timestamp: timestamp)

      # Constant-time comparison
      secure_compare(signature, expected[:signature])
    end

    private

    # Convert hash to canonical JSON (sorted keys)
    def canonical_json(hash)
      JSON.generate(sort_hash(hash))
    end

    # Recursively sort hash keys for canonical representation
    def sort_hash(obj)
      case obj
      when Hash
        obj.keys.sort.to_h { |k| [k, sort_hash(obj[k])] }
      when Array
        obj.map { |item| sort_hash(item) }
      else
        obj
      end
    end

    # Check if timestamp is within tolerance
    def timestamp_valid?(timestamp, tolerance)
      current_time = Time.current.to_i
      (current_time - timestamp.to_i).abs <= tolerance
    end

    # Constant-time string comparison
    def secure_compare(a, b)
      return false if a.blank? || b.blank? || a.bytesize != b.bytesize

      l = a.unpack "C#{a.bytesize}"
      res = 0
      b.each_byte { |byte| res |= byte ^ l.shift }
      res.zero?
    end
  end
end
