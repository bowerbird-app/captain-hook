# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in captain_hook.gemspec
gemspec

gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "debug"
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end

gem "pg", "~> 1.6"
