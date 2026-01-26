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

        # Get provider config from registry to access verifier_class
        provider_config = CaptainHook.configuration.provider(provider.name)
        if provider_config.nil?
          render json: {
            success: false,
            error: "Provider '#{provider.name}' not found in registry"
          }, status: :not_found
          return
        end

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

        # Get the verifier
        # Security: Validate verifier class name before constantize
        unless valid_verifier_class_name?(provider_config.verifier_class)
          render json: {
            success: false,
            error: "Invalid verifier class"
          }, status: :bad_request
          return
        end

        begin
          verifier_class = provider_config.verifier_class.constantize
          verifier = verifier_class.new
        rescue NameError => e
          render json: {
            success: false,
            error: "Verifier class not found: #{provider_config.verifier_class}"
          }, status: :bad_request
          return
        end

        # Extract event details (dry run - no database)
        event_type = verifier.extract_event_type(payload_hash)
        external_id = verifier.extract_event_id(payload_hash)
        timestamp = verifier.extract_timestamp({})

        # Find matching actions
        action_configs = CaptainHook.action_registry.actions_for(
          provider: provider.name,
          event_type: event_type
        )

        # Build result
        result = {
          success: true,
          dry_run: true,
          provider: {
            name: provider.name,
            display_name: provider_config.display_name,
            verifier: provider_config.verifier_class
          },
          extracted: {
            event_type: event_type,
            external_id: external_id,
            timestamp: timestamp
          },
          actions: action_configs.map do |config|
            {
              class: config.action_class.to_s,
              priority: config.priority,
              async: config.async,
              max_attempts: config.max_attempts
            }
          end,
          would_process: action_configs.any?,
          message: if action_configs.any?
                     "✓ Would trigger #{action_configs.count} action(s)"
                   else
                     "⚠ No actions registered for event type '#{event_type}'"
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

      private

      # Security: Validate verifier class names to prevent code injection via constantize
      def valid_verifier_class_name?(class_name)
        return false if class_name.blank?

        # Allow only alphanumeric characters, underscores, and :: for namespacing
        # Must start with capital letter (valid Ruby class name format)
        return false unless class_name.match?(/\A[A-Z][a-zA-Z0-9_:]*\z/)

        # Block dangerous patterns
        dangerous_patterns = [
          /\.\./, # Directory traversal
          /^(Kernel|Object|Class|Module|Proc|Method|IO|File|Dir|Process|System)/, # System classes
          /Eval/ # Eval-related
        ]

        return false if dangerous_patterns.any? { |pattern| class_name.match?(pattern) }

        true
      end
    end
  end
end
