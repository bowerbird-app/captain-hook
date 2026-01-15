# frozen_string_literal: true

source "https://rubygems.org"

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
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end

gem "pg", "~> 1.6"
