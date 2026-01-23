# frozen_string_literal: true

class CreateCaptainHookActions < ActiveRecord::Migration[8.0]
  def id_type
    ActiveRecord::Base.connection.adapter_name.downcase.to_sym == :postgresql ? :uuid : :string
  end

  def change
    create_table :captain_hook_actions, id: id_type do |t|
      t.string :provider, null: false
      t.string :event_type, null: false
      t.string :action_class, null: false
      t.boolean :async, null: false, default: true
      t.integer :max_attempts, null: false, default: 5
      t.integer :priority, null: false, default: 100
      t.json :retry_delays, null: false, default: [30, 60, 300, 900, 3600]
      t.datetime :deleted_at

      t.timestamps

      # Unique constraint to prevent duplicate action registrations
      t.index %i[provider event_type action_class], unique: true, name: "idx_captain_hook_actions_unique"

      # Index for finding actions by provider
      t.index :provider

      # Index for finding active actions
      t.index :deleted_at
    end
  end
end
