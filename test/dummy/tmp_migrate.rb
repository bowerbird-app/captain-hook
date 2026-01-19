ENV['RAILS_ENV'] ||= 'development'
require_relative 'config/environment'
ActiveRecord::Tasks::DatabaseTasks.migrate
puts "✅ Migrations completed successfully!"
