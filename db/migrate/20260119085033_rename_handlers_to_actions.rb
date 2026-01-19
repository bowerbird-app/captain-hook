# frozen_string_literal: true

class RenameHandlersToActions < ActiveRecord::Migration[8.1]
  def change
    # Rename handlers table to actions
    rename_table :captain_hook_handlers, :captain_hook_actions

    # Rename incoming_event_handlers table to incoming_event_actions
    rename_table :captain_hook_incoming_event_handlers, :captain_hook_incoming_event_actions
  end
end
