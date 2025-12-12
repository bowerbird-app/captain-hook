# frozen_string_literal: true

module CaptainHook
  # Job to archive old webhook events
  # Runs periodically to manage data retention
  class ArchivalJob < ApplicationJob
    queue_as :captain_hook_maintenance

    # Archive events older than the retention period
    # @param retention_days [Integer] Number of days to retain events (default from config)
    # @param batch_size [Integer] Number of events to archive per batch
    def perform(retention_days: nil, batch_size: 1000)
      retention_days ||= CaptainHook.configuration.retention_days
      cutoff_date = retention_days.days.ago

      # Archive incoming events
      archive_incoming_events(cutoff_date, batch_size)

      # Archive outgoing events
      archive_outgoing_events(cutoff_date, batch_size)
    end

    private

    def archive_incoming_events(cutoff_date, batch_size)
      archived_count = 0

      loop do
        # Find unarchived events older than cutoff
        events = CaptainHook::IncomingEvent
          .not_archived
          .where("created_at < ?", cutoff_date)
          .limit(batch_size)

        break if events.empty?

        # Archive each event
        events.each do |event|
          event.archive!
          archived_count += 1
        end

        Rails.logger.info "Archived #{archived_count} incoming events so far..."
      end

      Rails.logger.info "Archived #{archived_count} incoming events total"
      archived_count
    end

    def archive_outgoing_events(cutoff_date, batch_size)
      archived_count = 0

      loop do
        # Find unarchived events older than cutoff
        events = CaptainHook::OutgoingEvent
          .not_archived
          .where("created_at < ?", cutoff_date)
          .limit(batch_size)

        break if events.empty?

        # Archive each event
        events.each do |event|
          event.archive!
          archived_count += 1
        end

        Rails.logger.info "Archived #{archived_count} outgoing events so far..."
      end

      Rails.logger.info "Archived #{archived_count} outgoing events total"
      archived_count
    end
  end
end
