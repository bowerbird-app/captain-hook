# frozen_string_literal: true

# Example migration for SearchRequest model
# This demonstrates a model in a hypothetical gem
class CreateSearchRequests < ActiveRecord::Migration[7.2]
  def change
    create_table :search_requests do |t|
      t.string :query, null: false
      t.string :status, default: "pending", null: false
      t.jsonb :results, default: []
      t.datetime :completed_at

      t.timestamps
    end

    add_index :search_requests, :status
    add_index :search_requests, :created_at
  end
end
