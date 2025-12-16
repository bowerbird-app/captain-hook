# frozen_string_literal: true

class RemoveOutgoingEventsAddProviders < ActiveRecord::Migration[8.0]
  def up
    # Drop outgoing_events table
    drop_table :captain_hook_outgoing_events, if_exists: true

    # Create providers table
    create_table :captain_hook_providers, id: :uuid do |t|
      t.string :name, null: false
      t.string :display_name
      t.text :description
      t.string :token, null: false
      t.string :signing_secret
      t.string :adapter_class, default: "CaptainHook::Adapters::Base"
      t.integer :timestamp_tolerance_seconds, default: 300
      t.integer :max_payload_size_bytes, default: 1_048_576
      t.integer :rate_limit_requests, default: 100
      t.integer :rate_limit_period, default: 60
      t.boolean :active, default: true, null: false
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index :name, unique: true
      t.index :token, unique: true
      t.index :active
    end
  end

  def down
    drop_table :captain_hook_providers, if_exists: true

    # Recreate outgoing_events table
    create_table :captain_hook_outgoing_events, id: :uuid do |t|
      t.string :provider, null: false
      t.string :event_type, null: false
      t.string :target_url, null: false
      t.jsonb :payload, default: {}
      t.jsonb :headers, default: {}
      t.jsonb :metadata, default: {}
      t.string :status, null: false, default: "pending"
      t.integer :attempt_count, default: 0
      t.integer :response_code
      t.text :response_body
      t.integer :response_time_ms
      t.text :error_message
      t.datetime :queued_at
      t.datetime :delivered_at
      t.datetime :last_attempt_at
      t.datetime :archived_at
      t.integer :lock_version, default: 0, null: false
      t.timestamps

      t.index :provider
      t.index :event_type
      t.index :status
      t.index :created_at
      t.index :archived_at
      t.index [:provider, :created_at]
    end
  end
end
