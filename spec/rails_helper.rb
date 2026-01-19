# frozen_string_literal: true

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

# Set up encryption keys for test environment
ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] = "m9zZmUjUUXMdeQnp5HeIAFQ3DdPImKAd"
ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] = "zMGZzfBbHG8t38g1M2RKD5AsnSzva90q"
ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] = "yBlRa4HF0NLzhKDXSpk1ruiDhccvRkM2"

require_relative "../test/dummy/config/environment"
require "rspec/rails"
require "factory_bot_rails"
require "faker"
require "shoulda-matchers"
require "webmock/rspec"

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

# Load support files
Dir[CaptainHook::Engine.root.join("spec/support/**/*.rb")].each { |f| require f }

# Load factories
Dir[CaptainHook::Engine.root.join("spec/factories/**/*.rb")].each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join("spec/fixtures")
  ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/6-0/rspec-rails
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # Include Factory Bot syntax methods
  config.include FactoryBot::Syntax::Methods

  # Clean up action registry between tests
  config.before(:each) do
    CaptainHook.action_registry.clear!
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# WebMock configuration
WebMock.disable_net_connect!(allow_localhost: true)
