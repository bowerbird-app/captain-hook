# frozen_string_literal: true

# Stripe webhook verifier
# Implements Stripe's webhook signature verification scheme
# https://stripe.com/docs/webhooks/signatures
return if defined?(StripeVerifier)

class StripeVerifier
  include CaptainHook::VerifierHelpers

  SIGNATURE_HEADER = "Stripe-Signature" unless defined?(SIGNATURE_HEADER)
  TIMESTAMP_TOLERANCE = 300 unless defined?(TIMESTAMP_TOLERANCE) # 5 minutes

  # Verify Stripe webhook signature
  # Stripe sends signature as: t=timestamp,v1=signature
  def verify_signature(payload:, headers:, provider_config:)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return false if signature_header.blank?

    # Parse signature header: t=timestamp,v1=signature,v0=old_signature
    parsed = parse_kv_header(signature_header)
    timestamp = parsed["t"]
    signatures = [parsed["v1"], parsed["v0"]].flatten.compact
    
    return false if timestamp.blank? || signatures.empty?

    # Check timestamp tolerance
    if provider_config.timestamp_validation_enabled?
      tolerance = provider_config.timestamp_tolerance_seconds || TIMESTAMP_TOLERANCE
      return false unless timestamp_within_tolerance?(timestamp.to_i, tolerance)
    end

    # Generate expected signature
    signed_payload = "#{timestamp}.#{payload}"
    expected_signature = generate_hmac(provider_config.signing_secret, signed_payload)

    # Check if any of the signatures match (Stripe sends both v1 and v0 sometimes)
    signatures.any? { |sig| secure_compare(sig, expected_signature) }
  end

  # Extract timestamp from Stripe signature header
  def extract_timestamp(headers)
    signature_header = extract_header(headers, SIGNATURE_HEADER)
    return nil if signature_header.blank?

    parsed = parse_kv_header(signature_header)
    parsed["t"]&.to_i
  end

  # Extract event ID from Stripe payload
  def extract_event_id(payload)
    payload["id"]
  end

  # Extract event type from Stripe payload
  def extract_event_type(payload)
    payload["type"]
  end
end
