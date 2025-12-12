# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for managing incoming webhook events
    class IncomingEventsController < BaseController
      # GET /captain_hook/admin/incoming_events
      def index
        @events = CaptainHook::IncomingEvent
                  .includes(:incoming_event_handlers)
                  .order(created_at: :desc)
                  .page(params[:page])
                  .per(50)

        # Apply filters if provided
        @events = @events.by_provider(params[:provider]) if params[:provider].present?
        @events = @events.by_event_type(params[:event_type]) if params[:event_type].present?
        @events = @events.where(status: params[:status]) if params[:status].present?
      end

      # GET /captain_hook/admin/incoming_events/:id
      def show
        @event = CaptainHook::IncomingEvent
                 .includes(:incoming_event_handlers)
                 .find(params[:id])
      end
    end
  end
end
