# frozen_string_literal: true

# This migration comes from captain_hook (originally 20260117000002)
class AddAdapterFileToProviders < ActiveRecord::Migration[8.0]
  def change
    add_column :captain_hook_providers, :adapter_file, :string
  end
end
