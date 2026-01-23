# frozen_string_literal: true

namespace :captain_hook do
  desc "Complete CaptainHook setup (install, migrations, encryption)"
  task setup: :environment do
    puts "\n" + ("=" * 80)
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

    # Step 4: Check encryption keys
    puts "\n📋 Step 4: Checking encryption keys..."
    if encryption_keys_configured?
      puts "✓ Encryption keys already configured"
    else
      puts "\n⚠️  ActiveRecord Encryption keys not found!"
      puts "CaptainHook needs these to encrypt webhook signing secrets."

      if auto_mode
        puts "Generating encryption keys..."
        generate_encryption_keys
      else
        print "\nGenerate encryption keys now? (Y/n): "
        response = $stdin.gets.chomp.downcase
        if response.empty? || response == "y" || response == "yes"
          generate_encryption_keys
        else
          puts "⚠️  Skipping encryption setup. Run 'rails db:encryption:init' manually."
        end
      end
    end

    # Step 5: Create example provider structure (development only)
    if Rails.env.development?
      puts "\n📋 Step 5: Setting up example provider..."
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

    # Step 6: Validate setup
    puts "\n📋 Step 6: Validating setup..."
    validation_errors = validate_setup

    if validation_errors.empty?
      puts "✓ All validations passed!"
    else
      puts "\n⚠️  Setup validation warnings:"
      validation_errors.each { |error| puts "  - #{error}" }
    end

    # Final summary
    print_setup_summary

    puts "\n" + ("=" * 80)
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

    # Check encryption
    if encryption_keys_configured?
      puts "✓ Encryption keys configured"
    else
      errors << "Encryption keys not configured. Run: rails db:encryption:init"
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

    puts "\n" + ("=" * 80)

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

  def encryption_keys_configured?
    ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present? ||
      (defined?(Rails.application.credentials.active_record_encryption) &&
       Rails.application.credentials.active_record_encryption.present?)
  end

  def generate_encryption_keys
    puts "\nGenerating encryption keys..."

    # Generate keys using Rails built-in
    output = `rails db:encryption:init 2>&1`

    if output.include?("primary_key:")
      primary_key = output[/primary_key:\s+(\S+)/, 1]
      deterministic_key = output[/deterministic_key:\s+(\S+)/, 1]
      key_derivation_salt = output[/key_derivation_salt:\s+(\S+)/, 1]

      puts "\n✓ Keys generated successfully!"
      puts "\n" + ("=" * 80)
      puts "📋 Add these to your environment:"
      puts "=" * 80
      puts "\nFor development (.env file):"
      puts "-" * 80
      puts "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=#{primary_key}"
      puts "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=#{deterministic_key}"
      puts "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=#{key_derivation_salt}"

      puts "\n" + ("=" * 80)
      puts "For production (set as environment variables):"
      puts "=" * 80
      puts "Heroku:  heroku config:set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=#{primary_key}"
      puts "Render:  Add to Environment Variables in dashboard"
      puts "Fly.io:  fly secrets set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=#{primary_key}"
      puts "=" * 80

      # Try to add to .env file if it exists
      env_file = Rails.root.join(".env")
      if File.exist?(env_file)
        print "\nAdd keys to .env file automatically? (Y/n): "
        response = $stdin.gets.chomp.downcase
        if response.empty? || response == "y" || response == "yes"
          File.open(env_file, "a") do |f|
            f.puts "\n# ActiveRecord Encryption Keys (generated #{Time.now})"
            f.puts "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=#{primary_key}"
            f.puts "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=#{deterministic_key}"
            f.puts "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=#{key_derivation_salt}"
          end
          puts "✓ Keys added to .env file"
          puts "⚠️  Restart your Rails server to load the new keys"
        end
      end
    else
      puts "❌ Failed to generate keys. Output:"
      puts output
      puts "\nTry running manually: rails db:encryption:init"
    end
  end

  def create_example_provider
    puts "Creating example WebhookSite provider..."

    example_dir = Rails.root.join("captain_hook/webhook_site")
    FileUtils.mkdir_p(example_dir)
    FileUtils.mkdir_p(File.join(example_dir, "actions"))

    # Create YAML config
    yaml_content = <<~YAML
      # Example provider configuration for testing webhooks
      # Visit https://webhook.site to get a unique URL for testing

      name: webhook_site
      display_name: Webhook.site (Testing)
      description: Test webhook provider for development
      verifier_file: webhook_site.rb
      active: true

      # No signing secret needed for webhook.site
      signing_secret: ""

      # Optional: Rate limiting
      rate_limit_requests: 100
      rate_limit_period: 60
    YAML

    File.write(File.join(example_dir, "webhook_site.yml"), yaml_content)

    # Create verifier
    verifier_content = <<~RUBY
      # frozen_string_literal: true

      # Simple verifier for testing - accepts all webhooks
      class WebhookSiteVerifier
        include CaptainHook::VerifierHelpers

        def verify_signature(payload:, headers:, provider_config:)
          # Accept all requests for testing
          true
        end

        def extract_timestamp(headers)
          Time.now.to_i
        end

        def extract_event_id(payload)
          payload["id"] || SecureRandom.uuid
        end

        def extract_event_type(payload)
          payload["event_type"] || "test.event"
        end
      end
    RUBY

    File.write(File.join(example_dir, "webhook_site.rb"), verifier_content)

    # Create example action
    action_content = <<~RUBY
      # frozen_string_literal: true

      module WebhookSite
        class TestAction
          def self.details
            {
              description: "Handles test webhook events",
              event_type: "*",  # Matches all events
              priority: 100,
              async: true,
              max_attempts: 3
            }
          end

          def webhook_action(event:, payload:, metadata:)
            Rails.logger.info "🎣 WebhookSite test webhook received!"
            Rails.logger.info "Event ID: \#{event.external_id}"
            Rails.logger.info "Event Type: \#{event.event_type}"
            Rails.logger.info "Payload: \#{payload.inspect}"
          end
        end
      end
    RUBY

    File.write(File.join(example_dir, "actions", "test_action.rb"), action_content)

    puts "✓ Example provider created at captain_hook/webhook_site/"
    puts "  - Configuration: webhook_site.yml"
    puts "  - Verifier: webhook_site.rb"
    puts "  - Action: actions/test_action.rb"
  end

  def validate_setup
    errors = []

    # Check initializer
    errors << "Initializer missing" unless File.exist?(Rails.root.join("config/initializers/captain_hook.rb"))

    # Check routes
    unless File.read(Rails.root.join("config/routes.rb")).include?("CaptainHook::Engine")
      errors << "Engine not mounted in routes"
    end

    # Check encryption
    errors << "Encryption keys not configured (restart server after adding to .env)" unless encryption_keys_configured?

    # Check for pending migrations
    errors << "Pending migrations exist" if pending_migrations?

    errors
  end

  def print_setup_summary
    puts "\n" + ("=" * 80)
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
    puts "   - See example: captain_hook/webhook_site/actions/test_action.rb"

    puts "\n5. Get webhook URL from admin UI and configure in your provider"

    puts "\n📖 Documentation:"
    puts "   - Full guide: https://github.com/bowerbird-app/captain-hook#readme"
    puts "   - Provider setup: docs/PROVIDER_DISCOVERY.md"
    puts "   - Action discovery: docs/ACTION_DISCOVERY.md"

    puts "\n🔧 Troubleshooting:"
    puts "   rails captain_hook:doctor    # Validate configuration"
  end
end
