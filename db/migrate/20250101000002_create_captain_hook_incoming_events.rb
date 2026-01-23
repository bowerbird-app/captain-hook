# frozen_string_literal: true

class CreateCaptainHookIncomingEvents < ActiveRecord::Migration[7.0]
  def id_type
    ActiveRecord::Base.connection.adapter_name.downcase.to_sym == :postgresql ? :uuid : :string
  end

  def change
    create_table :captain_hook_incoming_events, id: id_type do |t|
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "received"
      t.string :dedup_state, null: false, default: "unique"
      t.json :payload
      t.json :headers
      t.json :metadata
      t.string :request_id
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0

      t.timestamps

      # Unique index for idempotency
      t.index %i[provider external_id], unique: true, name: "idx_captain_hook_incoming_events_idempotency"

      # Indexes for common queries
      t.index :provider
      t.index :event_type
      t.index :status
      t.index :created_at
      t.index :archived_at
    end
  end
end
