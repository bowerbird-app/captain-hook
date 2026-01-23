# frozen_string_literal: true

class CreateCaptainHookIncomingEventActions < ActiveRecord::Migration[8.0]
  def id_type
    ActiveRecord::Base.connection.adapter_name.downcase.to_sym == :postgresql ? :uuid : :string
  end

  def change
    create_table :captain_hook_incoming_event_actions, id: id_type do |t|
      t.string :incoming_event_id, limit: 36, null: false
      t.string :action_class, null: false
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
      t.index %i[status priority action_class], name: "idx_captain_hook_actions_processing_order"
      t.index :locked_at
    end
  end
end
