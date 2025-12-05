# frozen_string_literal: true

# Example migration for GemTemplate engine.
#
# This migration creates a sample table to demonstrate the migration generator.
# Replace or remove this migration with your actual engine tables.
#
# After renaming the gem, update the table name and class name accordingly.
#
class CreateGemTemplateExamples < ActiveRecord::Migration[7.1]
  def change
    create_table :gem_template_examples, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.jsonb :metadata, default: {}
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :gem_template_examples, :name
    add_index :gem_template_examples, :active
  end
end
