# frozen_string_literal: true

class SimplifyProvidersTable < ActiveRecord::Migration[8.0]
  def up
    # Remove columns that are now managed by the registry
    remove_column :captain_hook_providers, :display_name, :string
    remove_column :captain_hook_providers, :description, :text
    remove_column :captain_hook_providers, :signing_secret, :string
    remove_column :captain_hook_providers, :verifier_class, :string
    remove_column :captain_hook_providers, :verifier_file, :string
    remove_column :captain_hook_providers, :timestamp_tolerance_seconds, :integer
    remove_column :captain_hook_providers, :max_payload_size_bytes, :integer
    remove_column :captain_hook_providers, :metadata, :jsonb
  end

  def down
    # Restore removed columns with their original defaults
    add_column :captain_hook_providers, :display_name, :string
    add_column :captain_hook_providers, :description, :text
    add_column :captain_hook_providers, :signing_secret, :string
    add_column :captain_hook_providers, :verifier_class, :string
    add_column :captain_hook_providers, :verifier_file, :string
    add_column :captain_hook_providers, :timestamp_tolerance_seconds, :integer, default: 300
    add_column :captain_hook_providers, :max_payload_size_bytes, :integer, default: 1_048_576
    add_column :captain_hook_providers, :metadata, :jsonb, default: {}
  end
end
