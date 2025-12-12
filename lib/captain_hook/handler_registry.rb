# frozen_string_literal: true

module CaptainHook
  # Registry for incoming webhook handlers
  # Manages handler registrations with priority and retry configuration
  class HandlerRegistry
    HandlerConfig = Struct.new(
      :provider,
      :event_type,
      :handler_class,
      :async,
      :retry_delays,
      :max_attempts,
      :priority,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        super
        self.async ||= true
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

    # Register a handler for a provider and event type
    def register(provider:, event_type:, handler_class:, **options)
      @mutex.synchronize do
        key = registry_key(provider, event_type)
        @registry[key] ||= []
        
        config = HandlerConfig.new(
          provider: provider,
          event_type: event_type,
          handler_class: handler_class,
          **options
        )
        
        @registry[key] << config
        
        # Sort by priority (lower number = higher priority), then by handler class name for determinism
        @registry[key].sort_by! { |h| [h.priority, h.handler_class.to_s] }
      end
    end

    # Get all handlers for a provider and event type
    def handlers_for(provider:, event_type:)
      @mutex.synchronize do
        key = registry_key(provider, event_type)
        @registry[key] || []
      end
    end

    # Check if any handlers are registered for a provider and event type
    def handlers_registered?(provider:, event_type:)
      handlers_for(provider: provider, event_type: event_type).any?
    end

    # Get all registered providers
    def providers
      @mutex.synchronize do
        @registry.keys.map { |key| key.split(":").first }.uniq
      end
    end

    # Clear all registrations
    def clear!
      @mutex.synchronize do
        @registry.clear
      end
    end

    # Get handler config by class name
    def find_handler_config(provider:, event_type:, handler_class:)
      handlers_for(provider: provider, event_type: event_type).find do |config|
        config.handler_class.to_s == handler_class.to_s
      end
    end

    private

    def registry_key(provider, event_type)
      "#{provider}:#{event_type}"
    end
  end
end
