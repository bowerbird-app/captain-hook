# frozen_string_literal: true

# This migration comes from captain_hook (originally 20250101000001)
# Example migration for CaptainHook engine.
#
# This migration creates a sample table to demonstrate the migration generator.
# Replace or remove this migration with your actual engine tables.
#
# After renaming the gem, update the table name and class name accordingly.
#
class CreateCaptainHookExamples < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_hook_examples, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :metadata, default: {}
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :captain_hook_examples, :name
    add_index :captain_hook_examples, :active
  end
end
