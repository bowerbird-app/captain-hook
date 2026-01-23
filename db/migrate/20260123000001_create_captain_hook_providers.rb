# frozen_string_literal: true

class CreateCaptainHookProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :captain_hook_providers, id: :uuid do |t|
      t.string :name, null: false
      t.string :token, null: false
      t.boolean :active, default: true, null: false
      t.integer :rate_limit_requests, default: 100
      t.integer :rate_limit_period, default: 60

      t.timestamps

      t.index :name, unique: true
      t.index :token, unique: true
      t.index :active
    end
  end
end
