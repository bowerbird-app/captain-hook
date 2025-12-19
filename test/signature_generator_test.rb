# frozen_string_literal: true

require "test_helper"

module CaptainHook
  class SignatureGeneratorTest < Minitest::Test
    def setup
      @generator = SignatureGenerator.new
      @secret = "test_secret_key"
      @payload = '{"event":"test","data":"value"}'
    end

    # === Basic Signature Generation Tests ===

    def test_generates_signature_with_secret_and_payload
      signature = @generator.generate(@payload, @secret)

      refute_nil signature
      refute_empty signature
    end

    def test_generates_consistent_signature_for_same_inputs
      signature1 = @generator.generate(@payload, @secret)
      signature2 = @generator.generate(@payload, @secret)

      assert_equal signature1, signature2
    end

    def test_generates_different_signature_for_different_payloads
      payload1 = '{"event":"test1"}'
      payload2 = '{"event":"test2"}'

      signature1 = @generator.generate(payload1, @secret)
      signature2 = @generator.generate(payload2, @secret)

      refute_equal signature1, signature2
    end

    def test_generates_different_signature_for_different_secrets
      secret1 = "secret1"
      secret2 = "secret2"

      signature1 = @generator.generate(@payload, secret1)
      signature2 = @generator.generate(@payload, secret2)

      refute_equal signature1, signature2
    end

    # === Signature Verification Tests ===

    def test_verifies_valid_signature
      signature = @generator.generate(@payload, @secret)

      assert @generator.verify(@payload, @secret, signature)
    end

    def test_rejects_invalid_signature
      signature = @generator.generate(@payload, @secret)
      tampered_signature = "#{signature}tampered"

      refute @generator.verify(@payload, @secret, tampered_signature)
    end

    def test_rejects_signature_with_wrong_secret
      signature = @generator.generate(@payload, @secret)
      wrong_secret = "wrong_secret"

      refute @generator.verify(@payload, wrong_secret, signature)
    end

    def test_rejects_signature_with_modified_payload
      signature = @generator.generate(@payload, @secret)
      modified_payload = '{"event":"modified"}'

      refute @generator.verify(modified_payload, @secret, signature)
    end

    # === HMAC Algorithm Tests ===

    def test_generates_hmac_sha256_signature
      signature = @generator.generate(@payload, @secret, algorithm: :sha256)

      # HMAC-SHA256 generates 64 hex characters
      assert_equal 64, signature.length
      assert_match(/^[a-f0-9]{64}$/, signature)
    end

    def test_generates_hmac_sha1_signature
      signature = @generator.generate(@payload, @secret, algorithm: :sha1)

      # HMAC-SHA1 generates 40 hex characters
      assert_equal 40, signature.length
      assert_match(/^[a-f0-9]{40}$/, signature)
    end

    def test_supports_different_hash_algorithms
      sha256_sig = @generator.generate(@payload, @secret, algorithm: :sha256)
      sha1_sig = @generator.generate(@payload, @secret, algorithm: :sha1)

      refute_equal sha256_sig, sha1_sig
    end

    # === Edge Cases ===

    def test_handles_empty_payload
      signature = @generator.generate("", @secret)

      refute_nil signature
      refute_empty signature
    end

    def test_handles_empty_secret
      signature = @generator.generate(@payload, "")

      refute_nil signature
      refute_empty signature
    end

    def test_handles_unicode_payload
      unicode_payload = '{"message":"Hello 世界 🌍"}'
      signature = @generator.generate(unicode_payload, @secret)

      refute_nil signature
      assert @generator.verify(unicode_payload, @secret, signature)
    end

    def test_handles_large_payload
      large_payload = "{\"data\":\"#{'x' * 100_000}\"}"
      signature = @generator.generate(large_payload, @secret)

      refute_nil signature
      assert @generator.verify(large_payload, @secret, signature)
    end

    def test_handles_special_characters_in_secret
      special_secret = "secret!@#$%^&*()_+-=[]{}|;:',.<>?/~`"
      signature = @generator.generate(@payload, special_secret)

      refute_nil signature
      assert @generator.verify(@payload, special_secret, signature)
    end

    # === Format Tests ===

    def test_signature_format_is_hex_string
      signature = @generator.generate(@payload, @secret)

      # Should be a hex string (only 0-9 and a-f characters)
      assert_match(/^[a-f0-9]+$/, signature)
    end

    def test_signature_length_is_consistent_for_same_algorithm
      signatures = Array.new(10) { @generator.generate(@payload + rand.to_s, @secret) }
      lengths = signatures.map(&:length).uniq

      assert_equal 1, lengths.size, "All signatures should have the same length"
    end

    # === Timing Attack Prevention ===

    def test_verification_uses_secure_comparison
      signature = @generator.generate(@payload, @secret)
      wrong_signature = "0" * signature.length

      # Test that verification doesn't short-circuit on first difference
      # (timing attack prevention)
      time_correct = measure_time { @generator.verify(@payload, @secret, signature) }
      time_wrong = measure_time { @generator.verify(@payload, @secret, wrong_signature) }

      # Times should be similar (within 50% of each other)
      # This is a basic test and may not always pass due to system variations
      ratio = [time_correct / time_wrong, time_wrong / time_correct].max
      assert ratio < 2.0, "Verification should use constant-time comparison"
    end

    # === Nil and Type Handling ===

    def test_handles_nil_payload_gracefully
      assert_raises(ArgumentError, TypeError, NoMethodError) do
        @generator.generate(nil, @secret)
      end
    end

    def test_handles_nil_secret_gracefully
      assert_raises(ArgumentError, TypeError, NoMethodError) do
        @generator.generate(@payload, nil)
      end
    end

    def test_handles_nil_signature_in_verification
      refute @generator.verify(@payload, @secret, nil)
    end

    # === Performance Tests ===

    def test_generation_is_fast
      start_time = Time.now
      1000.times do
        @generator.generate(@payload, @secret)
      end
      elapsed = Time.now - start_time

      # Should be able to generate 1000 signatures in less than 0.5 seconds
      assert elapsed < 0.5, "Signature generation should be fast, took #{elapsed} seconds"
    end

    def test_verification_is_fast
      signature = @generator.generate(@payload, @secret)

      start_time = Time.now
      1000.times do
        @generator.verify(@payload, @secret, signature)
      end
      elapsed = Time.now - start_time

      # Should be able to verify 1000 signatures in less than 0.5 seconds
      assert elapsed < 0.5, "Signature verification should be fast, took #{elapsed} seconds"
    end

    private

    def measure_time(&)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      100.times(&)
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    end
  end
end
