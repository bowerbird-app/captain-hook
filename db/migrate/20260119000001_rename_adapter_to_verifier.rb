# frozen_string_literal: true

class RenameAdapterToVerifier < ActiveRecord::Migration[8.0]
  def change
    rename_column :captain_hook_providers, :adapter_class, :verifier_class
    rename_column :captain_hook_providers, :adapter_file, :verifier_file
  end
end
