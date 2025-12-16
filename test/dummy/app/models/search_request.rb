# frozen_string_literal: true

# Example model demonstrating inter-gem communication
# This represents a model from a hypothetical "SearchGem" that emits events
class SearchRequest < ApplicationRecord
  # Use after_commit to ensure transaction is complete before emitting event
  after_commit :emit_search_event, on: :create

  private

  def emit_search_event
    # Emit ActiveSupport::Notifications event
    # This keeps the gem decoupled from CaptainHook
    ActiveSupport::Notifications.instrument(
      "search_gem.search.requested",
      search_request_id: id,
      query: query,
      status: status,
      requested_at: created_at
    )
  end
end
