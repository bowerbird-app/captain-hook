# frozen_string_literal: true

module CaptainHook
  module Admin
    class SandboxController < ApplicationController
      layout "captain_hook/admin"

      def index
        @providers = CaptainHook::Provider.active.order(:name)
      end

      def test_webhook
        provider = CaptainHook::Provider.find(params[:provider_id])

        # Parse the payload
        begin
          payload_hash = JSON.parse(params[:payload])
        rescue JSON::ParserError => e
          render json: {
            success: false,
            error: "Invalid JSON: #{e.message}"
          }, status: :bad_request
          return
        end

        # Get the adapter
        adapter_class = provider.adapter_class.constantize
        adapter = adapter_class.new(provider)

        # Extract event details (dry run - no database)
        event_type = adapter.extract_event_type(payload_hash)
        external_id = adapter.extract_event_id(payload_hash)
        timestamp = adapter.extract_timestamp({})

        # Find matching handlers
        handler_configs = CaptainHook.handler_registry.handlers_for(
          provider: provider.name,
          event_type: event_type
        )

        # Build result
        result = {
          success: true,
          dry_run: true,
          provider: {
            name: provider.name,
            display_name: provider.display_name,
            adapter: provider.adapter_class
          },
          extracted: {
            event_type: event_type,
            external_id: external_id,
            timestamp: timestamp
          },
          handlers: handler_configs.map do |config|
            {
              class: config.handler_class.to_s,
              priority: config.priority,
              async: config.async,
              max_attempts: config.max_attempts
            }
          end,
          would_process: handler_configs.any?,
          message: if handler_configs.any?
                     "✓ Would trigger #{handler_configs.count} handler(s)"
                   else
                     "⚠ No handlers registered for event type '#{event_type}'"
                   end
        }

        render json: result
      rescue StandardError => e
        render json: {
          success: false,
          error: e.message,
          backtrace: Rails.env.development? ? e.backtrace.first(5) : nil
        }, status: :internal_server_error
      end
    end
  end
end
