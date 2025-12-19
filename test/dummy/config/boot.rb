ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
# Speed up boot time by caching expensive operations (optional - only if gem is available)
begin
  require "bootsnap/setup"
rescue LoadError
  # Bootsnap not available, continue without it
end
