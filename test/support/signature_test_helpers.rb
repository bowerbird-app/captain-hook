# frozen_string_literal: true

# Shared signature generation helpers for webhook testing
module SignatureTestHelpers
  # Generate Stripe signature
  # Stripe uses: HMAC-SHA256(timestamp.payload)
  def generate_stripe_signature(payload, timestamp, secret)
    signed_payload = "#{timestamp}.#{payload}"
    OpenSSL::HMAC.hexdigest("SHA256", secret, signed_payload)
  end

  # Build Stripe signature header
  def build_stripe_signature_header(payload, timestamp, secret)
    signature = generate_stripe_signature(payload, timestamp, secret)
    "t=#{timestamp},v1=#{signature}"
  end

  # Generate Square signature
  # Square uses: Base64(HMAC-SHA256(notification_url + payload))
  def generate_square_signature(payload, notification_url, secret)
    signed_payload = "#{notification_url}#{payload}"
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, signed_payload))
  end

  # Build PayPal headers
  def build_paypal_headers(signature: nil, transmission_id: nil, transmission_time: nil, webhook_id: nil)
    headers = {}
    headers["Paypal-Transmission-Sig"] = signature if signature
    headers["Paypal-Transmission-Id"] = transmission_id if transmission_id
    headers["Paypal-Transmission-Time"] = transmission_time if transmission_time
    headers["Paypal-Webhook-Id"] = webhook_id if webhook_id
    headers
  end

  # Build provider config for testing
  def build_provider_config(signing_secret: nil, timestamp_tolerance_seconds: 300, timestamp_validation_enabled: true, token: nil)
    config = OpenStruct.new(
      signing_secret: signing_secret,
      timestamp_tolerance_seconds: timestamp_tolerance_seconds,
      token: token
    )

    config.define_singleton_method(:timestamp_validation_enabled?) do
      timestamp_validation_enabled
    end

    config
  end
end
