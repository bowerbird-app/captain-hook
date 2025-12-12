# frozen_string_literal: true

# This migration comes from captain_hook (originally 20250101000004)
class CreateCaptainHookOutgoingEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :captain_hook_outgoing_events, id: :uuid do |t|
      t.string :provider, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :target_url, null: false
      t.jsonb :headers
      t.jsonb :payload
      t.jsonb :metadata
      t.integer :attempt_count, null: false, default: 0
      t.datetime :last_attempt_at
      t.text :error_message
      t.datetime :queued_at
      t.datetime :delivered_at
      t.integer :response_code
      t.text :response_body
      t.integer :response_time_ms
      t.string :request_id
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0

      t.timestamps

      # Indexes for common queries
      t.index :provider
      t.index :event_type
      t.index :status
      t.index :created_at
      t.index :archived_at
      t.index %i[status last_attempt_at], name: "idx_captain_hook_outgoing_events_retry"
    end
  end
end
