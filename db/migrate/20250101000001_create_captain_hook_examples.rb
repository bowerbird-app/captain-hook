# frozen_string_literal: true

# Example migration for CaptainHook engine.
#
# This migration creates a sample table to demonstrate the migration generator.
# Replace or remove this migration with your actual engine tables.
#
# After renaming the gem, update the table name and class name accordingly.
#
class CreateCaptainHookExamples < ActiveRecord::Migration[7.1]
  def id_type
    ActiveRecord::Base.connection.adapter_name.downcase.to_sym == :postgresql ? :uuid : :string
  end

  def change
    create_table :captain_hook_examples, id: id_type do |t|
      t.string :name, null: false
      t.text :description
      t.json :metadata, default: {}
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :captain_hook_examples, :name
    add_index :captain_hook_examples, :active
  end
end
