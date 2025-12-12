# frozen_string_literal: true

module CaptainHook
  # Base ApplicationRecord for CaptainHook models
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    # Use UUID primary keys by default
    self.implicit_order_column = "created_at"
  end
end
