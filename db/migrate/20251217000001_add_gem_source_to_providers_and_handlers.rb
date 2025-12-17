# frozen_string_literal: true

class AddGemSourceToProvidersAndHandlers < ActiveRecord::Migration[8.0]
  def change
    add_column :captain_hook_providers, :gem_source, :string
    add_column :captain_hook_incoming_event_handlers, :gem_source, :string

    add_index :captain_hook_providers, :gem_source
    add_index :captain_hook_incoming_event_handlers, :gem_source
  end
end
