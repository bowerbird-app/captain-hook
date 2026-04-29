# frozen_string_literal: true

namespace :captain_hook do
  desc "Complete CaptainHook setup (install, migrations, encryption)"
  task setup: :environment do
    puts "\n#{'=' * 80}"
    puts "⚓ CaptainHook Setup Wizard"
    puts "=" * 80

    # Check if we're in a Rails app
    unless defined?(Rails)
      puts "❌ Error: Must be run in a Rails application"
      exit 1
    end

    auto_mode = ENV["AUTO"] == "true" || ARGV.include?("--auto")

    # Step 1: Check if already installed
    puts "\n📋 Step 1: Checking existing installation..."
    initializer_exists = File.exist?(Rails.root.join("config/initializers/captain_hook.rb"))
    routes_mounted = File.read(Rails.root.join("config/routes.rb")).include?("CaptainHook::Engine")

    if initializer_exists && routes_mounted
      puts "✓ CaptainHook already installed (initializer and routes found)"

      unless auto_mode
        print "\nReinstall? This will overwrite existing files. (y/N): "
        response = $stdin.gets.chomp.downcase
        if response != "y" && response != "yes"
          puts "Skipping installation step..."
        else
          run_install_generator
        end
      end
    else
      puts "Installing CaptainHook..."
      run_install_generator
    end

    # Step 2: Check and copy migrations
    puts "\n📋 Step 2: Checking migrations..."
    if pending_captain_hook_migrations?
      puts "Copying CaptainHook migrations..."
      Rake::Task["captain_hook:install:migrations"].invoke
      puts "✓ Migrations copied"
    else
      puts "✓ All CaptainHook migrations already present"
    end

    # Step 3: Run pending migrations
    puts "\n📋 Step 3: Checking database migrations..."
    if pending_migrations?
      if auto_mode
        puts "Running migrations automatically..."
        run_migrations
      else
        print "\nRun pending migrations now? (Y/n): "
        response = $stdin.gets.chomp.downcase
        if response.empty? || response == "y" || response == "yes"
          run_migrations
        else
          puts "⚠️  Skipping migrations. Run 'rails db:migrate' manually later."
        end
      end
    else
      puts "✓ No pending migrations"
    end

    # Step 4: Create example provider structure (development only)
    if Rails.env.development?
      puts "\n📋 Step 4: Setting up example provider..."
      example_dir = Rails.root.join("captain_hook/webhook_site")

      if File.directory?(example_dir)
        puts "✓ Example provider directory already exists"
      elsif auto_mode
        create_example_provider
      else
        print "\nCreate example WebhookSite provider for testing? (Y/n): "
        response = $stdin.gets.chomp.downcase
        if response.empty? || response == "y" || response == "yes"
          create_example_provider
        else
          puts "Skipping example provider creation"
        end
      end
    end

    # Step 5: Validate setup
    puts "\n📋 Step 5: Validating setup..."
    validation_errors = validate_setup

    if validation_errors.empty?
      puts "✓ All validations passed!"
    else
      puts "\n⚠️  Setup validation warnings:"
      validation_errors.each { |error| puts "  - #{error}" }
    end

    # Final summary
    print_setup_summary

    puts "\n#{'=' * 80}"
    puts "✅ CaptainHook setup complete!"
    puts "=" * 80
  end

  desc "Validate CaptainHook configuration"
  task doctor: :environment do
    puts "\n⚓ CaptainHook Configuration Doctor"
    puts "=" * 80

    errors = []
    warnings = []

    # Check initializer
    if File.exist?(Rails.root.join("config/initializers/captain_hook.rb"))
      puts "✓ Initializer exists"
    else
      errors << "Initializer missing: config/initializers/captain_hook.rb"
    end

    # Check routes
    routes_content = File.read(Rails.root.join("config/routes.rb"))
    if routes_content.include?("CaptainHook::Engine")
      puts "✓ Engine mounted in routes"
    else
      errors << "Engine not mounted in config/routes.rb"
    end

    # Check migrations
    if pending_captain_hook_migrations?
      warnings << "CaptainHook migrations not copied. Run: rails captain_hook:install:migrations"
    elsif pending_migrations?
      warnings << "Pending migrations exist. Run: rails db:migrate"
    else
      puts "✓ All migrations applied"
    end

    # Check database tables
    begin
      if ActiveRecord::Base.connection.table_exists?("captain_hook_providers")
        puts "✓ Database tables exist"
      else
        errors << "CaptainHook tables missing. Run: rails db:migrate"
      end
    rescue StandardError => e
      errors << "Cannot connect to database: #{e.message}"
    end

    # Check autoload paths
    captain_hook_paths = Rails.configuration.autoload_paths.select do |path|
      path.to_s.include?("captain_hook")
    end

    if captain_hook_paths.any?
      puts "✓ Autoload paths configured"
    else
      warnings << "Consider adding captain_hook directories to autoload_paths in config/application.rb"
    end

    puts "\n#{'=' * 80}"

    if errors.empty? && warnings.empty?
      puts "✅ All checks passed! CaptainHook is properly configured."
    else
      if errors.any?
        puts "\n❌ ERRORS (must fix):"
        errors.each { |e| puts "  - #{e}" }
      end

      if warnings.any?
        puts "\n⚠️  WARNINGS (recommended):"
        warnings.each { |w| puts "  - #{w}" }
      end

      puts "\nRun 'rails captain_hook:setup' to fix these issues."
    end

    puts "=" * 80
  end

  # Helper methods
  private

  def run_install_generator
    require "rails/generators"
    Rails::Generators.invoke("captain_hook:install", [], behavior: :invoke, destination_root: Rails.root)
  rescue StandardError => e
    puts "❌ Error running generator: #{e.message}"
    puts "Try running manually: rails generate captain_hook:install"
  end

  def pending_captain_hook_migrations?
    # Check if CaptainHook migrations exist in the gem but not in the app
    engine_migrations_dir = CaptainHook::Engine.root.join("db/migrate")
    app_migrations_dir = Rails.root.join("db/migrate")

    return false unless File.directory?(engine_migrations_dir)

    engine_migration_names = Dir.glob(File.join(engine_migrations_dir, "*.rb")).map do |path|
      File.basename(path).sub(/^\d+_/, "")
    end

    app_migration_names = Dir.glob(File.join(app_migrations_dir, "*captain_hook*.rb")).map do |path|
      File.basename(path).sub(/^\d+_/, "")
    end

    missing = engine_migration_names - app_migration_names
    missing.any?
  end

  def pending_migrations?
    ActiveRecord::Migration.check_pending!
    false
  rescue ActiveRecord::PendingMigrationError
    true
  rescue StandardError => e
    # If we can't check, assume no pending migrations
    Rails.logger.warn "Could not check for pending migrations: #{e.message}"
    false
  end

  def run_migrations
    Rake::Task["db:migrate"].invoke
    puts "✓ Migrations completed"
  rescue StandardError => e
    puts "❌ Error running migrations: #{e.message}"
    puts "Try running manually: rails db:migrate"
  end

  # No longer creates example provider
  # Users should refer to the README for Stripe setup instructions
  def create_example_provider
    # Deprecated - no longer creates example providers
    puts "Example provider creation is deprecated. Please see README.md for Stripe setup."
  end

  def validate_setup
    errors = []

    # Check initializer
    errors << "Initializer missing" unless File.exist?(Rails.root.join("config/initializers/captain_hook.rb"))

    # Check routes
    unless File.read(Rails.root.join("config/routes.rb")).include?("CaptainHook::Engine")
      errors << "Engine not mounted in routes"
    end

    # Check for pending migrations
    errors << "Pending migrations exist" if pending_migrations?

    errors
  end

  def print_setup_summary
    puts "\n#{'=' * 80}"
    puts "📚 Next Steps:"
    puts "=" * 80
    puts "\n1. Restart your Rails server (if running)"
    puts "   rails server"

    puts "\n2. Visit the admin interface:"
    puts "   http://localhost:3000/captain_hook"

    puts "\n3. Create providers via admin UI or YAML files:"
    puts "   - Admin UI: http://localhost:3000/captain_hook/admin/providers"
    puts "   - YAML: Create captain_hook/<provider>/<provider>.yml"

    puts "\n4. Register actions:"
    puts "   - Create action classes in captain_hook/<provider>/actions/"
    puts "   - See README.md for action examples"

    puts "\n5. Get webhook URL from admin UI and configure in your provider"

    puts "\n📖 Documentation:"
    puts "   - Full guide: https://github.com/bowerbird-app/captain-hook#readme"
    puts "   - Provider setup: docs/PROVIDER_DISCOVERY.md"
    puts "   - Action discovery: docs/ACTION_DISCOVERY.md"

    puts "\n🔧 Troubleshooting:"
    puts "   rails captain_hook:doctor    # Validate configuration"
  end
end
