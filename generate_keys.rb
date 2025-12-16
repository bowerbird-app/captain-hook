#!/usr/bin/env ruby
require "securerandom"

puts ""
puts "🔐 CaptainHook Encryption Key Generator"
puts "=" * 70
puts ""
puts "# Copy these to your .env file:"
puts ""
puts "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=#{SecureRandom.alphanumeric(32)}"
puts "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=#{SecureRandom.alphanumeric(32)}"
puts "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=#{SecureRandom.alphanumeric(32)}"
puts ""
puts "# Also add this:"
puts "SECRET_KEY_BASE=#{SecureRandom.hex(64)}"
puts ""
puts "=" * 70
puts "✅ Keys generated! Add them to /workspace/test/dummy/.env"
puts ""
