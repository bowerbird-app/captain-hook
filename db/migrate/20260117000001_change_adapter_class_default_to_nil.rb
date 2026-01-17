# frozen_string_literal: true

class ChangeAdapterClassDefaultToNil < ActiveRecord::Migration[8.0]
  def up
    change_column_default :captain_hook_providers, :adapter_class, from: "CaptainHook::Adapters::Base", to: nil
  end

  def down
    change_column_default :captain_hook_providers, :adapter_class, from: nil, to: "CaptainHook::Adapters::Base"
  end
end
