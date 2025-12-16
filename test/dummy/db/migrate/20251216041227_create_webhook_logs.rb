class CreateWebhookLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_logs, id: :uuid do |t|
      t.string :provider
      t.string :event_type
      t.string :external_id
      t.jsonb :payload
      t.datetime :processed_at

      t.timestamps
    end

    add_index :webhook_logs, [:provider, :event_type]
    add_index :webhook_logs, :external_id
  end
end
