# frozen_string_literal: true

source "https://rubygems.org"

# Pin FlatPack to the current 0.1.27 revision until an upstream tag is published
gem "flat_pack", github: "bowerbird-app/flatpack", ref: "12ef99c5a29e8b5506cc3c9427d686c2477f774c"

# Specify your gem's dependencies in captain_hook.gemspec
gemspec

gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "benchmark-ips", "~> 2.13"
  gem "debug"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.2"
  gem "memory_profiler", "~> 1.0"
  gem "rspec-rails", "~> 6.1"
  gem "shoulda-matchers", "~> 6.0"
  gem "simplecov", require: false
  gem "webmock", "~> 3.19"
end

group :development do
  gem "flatpack-checker", "~> 0.1.1", github: "bowerbird-app/flatpack-checker"
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end

gem "pg", "~> 1.6"
