# frozen_string_literal: true

module CaptainHook
  # Registry for incoming webhook actions
  # Manages action registrations with priority and retry configuration
  class ActionRegistry
    ActionConfig = Struct.new(
      :provider,
      :event_type,
      :action_class,
      :async,
      :retry_delays,
      :max_attempts,
      :priority,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        super
        self.async = true if async.nil?
        self.retry_delays ||= [30, 60, 300, 900, 3600]
        self.max_attempts ||= 5
        self.priority ||= 100
      end

      # Get delay for a given attempt (0-indexed)
      def delay_for_attempt(attempt)
        retry_delays[attempt] || retry_delays.last || 3600
      end
    end

    def initialize
      @registry = {}
      @mutex = Mutex.new
    end

    # Register an action for a provider and event type
    def register(provider:, event_type:, action_class:, **options)
      @mutex.synchronize do
        key = registry_key(provider, event_type)
        @registry[key] ||= []

        config = ActionConfig.new(
          provider: provider,
          event_type: event_type,
          action_class: action_class,
          **options
        )

        @registry[key] << config

        # Sort by priority (lower number = higher priority), then by action class name for determinism
        @registry[key].sort_by! { |h| [h.priority, h.action_class.to_s] }
      end
    end

    # Get all actions for a provider and event type
    def actions_for(provider:, event_type:)
      @mutex.synchronize do
        key = registry_key(provider, event_type)
        @registry[key] || []
      end
    end

    # Check if any actions are registered for a provider and event type
    def actions_registered?(provider:, event_type:)
      actions_for(provider: provider, event_type: event_type).any?
    end

    # Get all registered providers
    def providers
      @mutex.synchronize do
        @registry.keys.map { |key| key.split(":").first }.uniq
      end
    end

    # Get all registered actions across all providers
    def all_actions
      @mutex.synchronize do
        @registry.values.flatten
      end
    end

    # Get all actions for a specific provider (all event types)
    def actions_for_provider(provider)
      @mutex.synchronize do
        @registry.select { |key, _| key.start_with?("#{provider}:") }.values.flatten
      end
    end

    # Clear all registrations
    def clear!
      @mutex.synchronize do
        @registry.clear
      end
    end

    # Get action config by class name
    def find_action_config(provider:, event_type:, action_class:)
      actions_for(provider: provider, event_type: event_type).find do |config|
        config.action_class.to_s == action_class.to_s
      end
    end

    private

    def registry_key(provider, event_type)
      "#{provider}:#{event_type}"
    end
  end
end
