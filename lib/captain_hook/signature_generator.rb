# frozen_string_literal: true

require "openssl"
require "json"

module CaptainHook
  # Generates HMAC-SHA256 signatures for outgoing webhooks
  # Implements: HMAC_SHA256(timestamp.canonical_json)
  class SignatureGenerator
    attr_reader :secret

    def initialize(secret = nil)
      @secret = secret
    end

    # Generate signature for payload
    # @param payload [String, Hash] The webhook payload
    # @param secret [String] The signing secret
    # @param algorithm [Symbol] Hash algorithm (:sha256 or :sha1)
    # @return [String] The hexadecimal signature
    def generate(payload, secret, algorithm: :sha256)
      raise ArgumentError, "payload cannot be nil" if payload.nil?

      # Convert to string if hash
      payload_string = payload.is_a?(String) ? payload : JSON.generate(payload)

      # Normalize algorithm name
      algo_name = algorithm.to_s.upcase.sub("SHA", "SHA")

      # Generate HMAC signature
      OpenSSL::HMAC.hexdigest(algo_name, secret, payload_string)
    end

    # Verify a signature
    # @param payload [String, Hash] The webhook payload
    # @param secret [String] The signing secret
    # @param signature [String] The signature to verify
    # @param algorithm [Symbol] Hash algorithm (:sha256 or :sha1)
    # @return [Boolean] true if signature is valid
    def verify(payload, secret, signature, algorithm: :sha256)
      return false if signature.blank?

      expected = generate(payload, secret, algorithm: algorithm)

      # Constant-time comparison
      secure_compare(signature, expected)
    end

    private

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
