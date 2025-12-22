# frozen_string_literal: true

class CreateCaptainHookIncomingEventHandlers < ActiveRecord::Migration[7.0]
  def change
    create_table :captain_hook_incoming_event_handlers, id: :uuid do |t|
      t.uuid :incoming_event_id, null: false
      t.string :handler_class, null: false
      t.string :status, null: false, default: "pending"
      t.integer :priority, null: false, default: 100
      t.integer :attempt_count, null: false, default: 0
      t.datetime :last_attempt_at
      t.text :error_message
      t.datetime :locked_at
      t.string :locked_by
      t.integer :lock_version, null: false, default: 0

      t.timestamps

      # Foreign key
      t.foreign_key :captain_hook_incoming_events, column: :incoming_event_id

      # Indexes for processing and querying
      t.index :incoming_event_id
      t.index :status
      t.index %i[status priority handler_class], name: "idx_captain_hook_handlers_processing_order"
      t.index :locked_at
    end
  end
end
