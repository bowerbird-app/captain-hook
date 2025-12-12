# frozen_string_literal: true

module CaptainHook
  module Admin
    # Admin controller for managing outgoing webhook events
    class OutgoingEventsController < BaseController
      # GET /captain_hook/admin/outgoing_events
      def index
        @events = CaptainHook::OutgoingEvent
                  .order(created_at: :desc)
                  .page(params[:page])
                  .per(50)

        # Apply filters if provided
        @events = @events.by_provider(params[:provider]) if params[:provider].present?
        @events = @events.where(status: params[:status]) if params[:status].present?
      end

      # GET /captain_hook/admin/outgoing_events/:id
      def show
        @event = CaptainHook::OutgoingEvent.find(params[:id])
      end
    end
  end
end
