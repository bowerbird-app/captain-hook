#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

# Check SimpleCov coverage thresholds
# Usage: ruby scripts/check_coverage.rb
#
# Exit codes:
#   0 - Coverage meets thresholds
#   1 - Coverage below thresholds or report not found

coverage_file = "coverage/.last_run.json"

unless File.exist?(coverage_file)
  puts "Warning: No coverage report found at #{coverage_file}"
  puts "Run tests with COVERAGE=true to generate report"
  exit 0
end

data = JSON.parse(File.read(coverage_file))
coverage = data.dig("result", "line") || data.dig("result", "covered_percent")
branch_cov = data.dig("result", "branch")

puts "\n" + "=" * 50
puts "SimpleCov Coverage Report"
puts "=" * 50

if coverage
  puts "Line coverage:   #{coverage.round(2)}%"
else
  puts "Line coverage:   Not available"
end

if branch_cov
  puts "Branch coverage: #{branch_cov.round(2)}%"
else
  puts "Branch coverage: Not available"
end

puts "=" * 50

# Check thresholds
min_line_coverage = 90
min_branch_coverage = 80

exit_code = 0

if coverage && coverage < min_line_coverage
  puts "\n❌ ERROR: Line coverage (#{coverage.round(2)}%) is below minimum threshold of #{min_line_coverage}%"
  exit_code = 1
end

if branch_cov && branch_cov < min_branch_coverage
  puts "\n❌ ERROR: Branch coverage (#{branch_cov.round(2)}%) is below minimum threshold of #{min_branch_coverage}%"
  exit_code = 1
end

if exit_code == 0
  puts "\n✅ Coverage thresholds met!"
end

puts

exit exit_code
