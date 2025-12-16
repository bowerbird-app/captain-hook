# frozen_string_literal: true

# Example handler for processing incoming webhooks
# This represents a handler from a hypothetical gem that processes webhook responses
class SearchResponseHandler
  # Handler must implement `handle` method with this signature
  # @param event [CaptainHook::IncomingEvent] The incoming event record
  # @param payload [Hash] The webhook payload
  # @param metadata [Hash] The webhook metadata
  def handle(event:, payload:, metadata:)
    Rails.logger.info "SearchResponseHandler: Processing webhook event #{event.id}"
    
    # Extract data from payload
    search_request_id = payload.dig("data", "search_request_id")
    results = payload.dig("data", "results")
    
    # Find the search request
    search_request = SearchRequest.find_by(id: search_request_id)
    
    unless search_request
      Rails.logger.warn "SearchResponseHandler: Search request #{search_request_id} not found"
      return # Exit gracefully, don't raise
    end
    
    # Update the search request with results
    search_request.update!(
      status: "completed",
      results: results,
      completed_at: Time.current
    )
    
    Rails.logger.info "SearchResponseHandler: Updated search request #{search_request_id} with #{results&.size || 0} results"
    
    # Log metadata for debugging
    Rails.logger.debug "Source: #{metadata[:source]}, Version: #{metadata[:version]}" if metadata
  rescue ActiveRecord::RecordInvalid => e
    # Log error but don't re-raise - let CaptainHook handle retries
    Rails.logger.error "SearchResponseHandler: Failed to update search request: #{e.message}"
  end
end
