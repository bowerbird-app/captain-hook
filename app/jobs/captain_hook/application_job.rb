# frozen_string_literal: true

module CaptainHook
  # Base ApplicationJob for CaptainHook background jobs
  class ApplicationJob < ActiveJob::Base
    # Automatically retry jobs that encounter deadlocks
    retry_on ActiveRecord::Deadlocked

    # Most jobs are safe to ignore if the underlying records are no longer available
    discard_on ActiveJob::DeserializationError
  end
end
