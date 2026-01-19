# frozen_string_literal: true

class CreateCaptainHookHandlers < ActiveRecord::Migration[7.0]
  def change
    create_table :captain_hook_handlers, id: :uuid do |t|
      t.string :provider, null: false
      t.string :event_type, null: false
      t.string :handler_class, null: false
      t.boolean :async, null: false, default: true
      t.integer :max_attempts, null: false, default: 5
      t.integer :priority, null: false, default: 100
      t.jsonb :retry_delays, null: false, default: [30, 60, 300, 900, 3600]
      t.datetime :deleted_at

      t.timestamps

      # Unique constraint to prevent duplicate action registrations
      t.index [:provider, :event_type, :handler_class], unique: true, name: "idx_captain_hook_handlers_unique"
      
      # Index for finding actions by provider
      t.index :provider
      
      # Index for finding active actions
      t.index :deleted_at
    end
  end
end
