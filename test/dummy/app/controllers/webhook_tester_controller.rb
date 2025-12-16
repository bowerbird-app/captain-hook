# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

class WebhookTesterController < ApplicationController
  # Configuration for webhook.site - uses config file or environment
  helper_method :webhook_site_url, :webhook_site_token

  def webhook_site_url
    # Try ENV first, then config file, then fallback
    url = ENV["WEBHOOK_SITE_URL"]
    
    if url.blank? && !Rails.env.production?
      config_file = Rails.root.join("config/webhook_config.yml")
      if File.exist?(config_file)
        webhook_config = YAML.load_file(config_file)[Rails.env.to_s]
        url = webhook_config&.dig("webhook_site", "url")
      end
    end
    
    url || "https://webhook.site/default"
  end

  def webhook_site_token
    # Extract token from URL
    webhook_site_url.split('/').last
  end

  def index
    # Display the webhook connection testing interface
  end

  def send_incoming
    # Test webhook connection by simulating an incoming webhook to the Captain Hook engine
    provider_name = params[:provider] || "webhook_site"
    
    # Get provider from database or configuration
    provider = CaptainHook::Provider.find_by(name: provider_name)
    token = params[:token] || provider&.token || CaptainHook.configuration.provider(provider_name)&.token || "test_token"
    
    begin
      payload_hash = JSON.parse(params[:payload] || '{"event": "test"}')
    rescue JSON::ParserError => e
      flash[:alert] = "Invalid JSON payload: #{e.message}"
      redirect_to webhook_tester_path
      return
    end

    # Make a real HTTP request to the app (using localhost to avoid port visibility issues)
    uri = URI.parse("http://localhost:3004/captain_hook/#{provider_name}/#{token}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = false
    
    request_obj = Net::HTTP::Post.new(uri.request_uri)
    request_obj["Content-Type"] = "application/json"
    request_obj["X-Webhook-Timestamp"] = Time.now.to_i.to_s
    request_obj.body = payload_hash.to_json

    response = http.request(request_obj)
    body = JSON.parse(response.body) rescue { message: response.body }

    if response.code.to_i >= 200 && response.code.to_i < 300
      event_id = body['id'] || 'N/A'
      status_text = body['status'] || 'received'
      flash[:notice] = "✓ Webhook connection successful! Status: #{response.code}, Event ID: #{event_id}, Status: #{status_text}"
    else
      error_msg = body['error'] || body['message'] || 'Unknown error'
      flash[:alert] = "✗ Webhook connection failed with status #{response.code}: #{error_msg}"
    end
    
    redirect_to webhook_tester_path
  rescue StandardError => e
    flash[:alert] = "✗ Error testing webhook connection: #{e.message}"
    redirect_to webhook_tester_path
  end
end
