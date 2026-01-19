# frozen_string_literal: true

class RenameHandlersToActions < ActiveRecord::Migration[8.1]
  def change
    # Rename handlers table to actions
    rename_table :captain_hook_handlers, :captain_hook_actions

    # Rename incoming_event_handlers table to incoming_event_actions
    rename_table :captain_hook_incoming_event_handlers, :captain_hook_incoming_event_actions

    # Rename handler_class column to action_class in actions table
    rename_column :captain_hook_actions, :handler_class, :action_class

    # Rename handler_class column to action_class in incoming_event_actions table
    rename_column :captain_hook_incoming_event_actions, :handler_class, :action_class

    # Rename the unique index
    remove_index :captain_hook_actions, name: "idx_captain_hook_handlers_unique"
    add_index :captain_hook_actions, %i[provider event_type action_class], unique: true, name: "idx_captain_hook_actions_unique"
  end
end
