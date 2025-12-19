# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/rename_verification_test.rb")
  t.verbose = false
end

# Load RSpec rake tasks
begin
  require "rspec/core/rake_task"
  
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.rspec_opts = "--color --format documentation"
  end
  
  desc "Run RSpec tests"
  task rspec: :spec
rescue LoadError
  # RSpec not available, skip
end

namespace :test do
  desc "Run rename verification tests to validate gem naming consistency"
  task :rename_verification do
    ruby "test/rename_verification_test.rb", verbose: true
  end

  desc "Run rename verification tests in verbose mode"
  task :rename_verification_verbose do
    ruby "test/rename_verification_test.rb", "--verbose", verbose: true
  end
end

namespace :app do
  desc "Run all tests for the gem"
  task test: :test
end

task default: :test
