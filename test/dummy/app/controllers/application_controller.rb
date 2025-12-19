class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  # Only call if the method is available (importmap-rails gem is loaded)
  stale_when_importmap_changes if respond_to?(:stale_when_importmap_changes)
end
