# frozen_string_literal: true

class AddAdapterFileToProviders < ActiveRecord::Migration[8.0]
  def change
    add_column :captain_hook_providers, :adapter_file, :string
  end
end
