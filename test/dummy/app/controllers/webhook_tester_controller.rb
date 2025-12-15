# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

class WebhookTesterController < ApplicationController
  # Configuration for webhook.site
  # TODO: Move these to environment variables or Rails credentials
  WEBHOOK_CONFIG = {
    unique_url: "https://webhook.site/83c6777b-45cf-40db-a013-7e8085db26d6",
    email_address: "83c6777b-45cf-40db-a013-7e8085db26d6@emailhook.site",
    dns_name: "83c6777b-45cf-40db-a013-7e8085db26d6.dnshook.site",
    token: "83c6777b-45cf-40db-a013-7e8085db26d6"
  }.freeze

  def index
    # Display the webhook testing interface
  end

  def send_incoming
    # Simulate an incoming webhook to the Captain Hook engine
    provider = params[:provider] || "test_provider"
    token = params[:token] || "test_token"
    
    begin
      payload = JSON.parse(params[:payload] || '{"event": "test"}')
    rescue JSON::ParserError => e
      flash[:alert] = "Invalid JSON payload: #{e.message}"
      redirect_to webhook_tester_path
      return
    end

    uri = URI.parse("#{request.base_url}/captain_hook/#{provider}/#{token}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    
    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = http.request(request)

    flash[:notice] = "Incoming webhook sent successfully! Status: #{response.code}"
    redirect_to webhook_tester_path
  rescue StandardError => e
    flash[:alert] = "Error sending incoming webhook: #{e.message}"
    redirect_to webhook_tester_path
  end

  def send_outgoing
    # Send a test webhook to webhook.site
    begin
      payload = JSON.parse(params[:payload] || '{"event": "test"}')
    rescue JSON::ParserError => e
      flash[:alert] = "Invalid JSON payload: #{e.message}"
      redirect_to webhook_tester_path
      return
    end

    uri = URI.parse(WEBHOOK_CONFIG[:unique_url])
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    
    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = http.request(request)

    flash[:notice] = "Outgoing webhook sent successfully! Status: #{response.code}. Check #{WEBHOOK_CONFIG[:unique_url]} to see the request."
    redirect_to webhook_tester_path
  rescue StandardError => e
    flash[:alert] = "Error sending outgoing webhook: #{e.message}"
    redirect_to webhook_tester_path
  end
end
