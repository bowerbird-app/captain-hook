# Quick Start Guide

This is a quick reference for getting started with the gem_template engine.

## For GitHub Codespaces Users

1. Click "Create Codespace" on this repository
2. Wait for the container to build (3-5 minutes)
3. Wait for postCreateCommand to complete (shown in terminal)
4. Run:
   ```bash
   cd test/dummy
   bundle exec rails server -p 3000 -b 0.0.0.0
   ```
5. Click on the "Ports" tab, find port 3000, and click the globe icon to open in browser
6. Visit `/gem_template` to see the engine

## For Local Development

### Prerequisites
- Ruby 3.3+
- PostgreSQL 16
- Node.js (for TailwindCSS)
- Redis 7

### Setup
```bash
# Clone the repository
git clone https://github.com/bowerbird-app/gem_template.git
cd gem_template

# Install dependencies
bundle install

# Setup the dummy app
cd test/dummy
bundle install

# Configure database (update config/database.yml if needed)
bin/rails db:prepare

# Build Tailwind
bin/rails tailwindcss:build

# Start the server
bundle exec rails server
```

Visit http://localhost:3000/gem_template

## Using as a Template

### To Create Your Own Engine

1. Fork or use as template
2. Rename throughout:
   - `gem_template` → `your_engine_name`
   - `GemTemplate` → `YourEngineName`
3. Update gemspec:
   - name, authors, email, homepage
   - summary and description
4. Update README and documentation
5. Start building your engine features

### Files to Update When Renaming
- `gem_template.gemspec`
- `lib/gem_template.rb`
- `lib/gem_template/engine.rb`
- `lib/gem_template/version.rb`
- `config/routes.rb`
- All files in `app/controllers/gem_template/`
- All files in `app/views/gem_template/`
- All files in `lib/generators/gem_template/`
- `test/dummy/config/routes.rb` (mount path)
- `test/dummy/Gemfile` (gem reference)

## Key Features

### UUID Primary Keys
All database tables automatically use UUIDs. This is configured in:
- `test/dummy/config/application.rb`
- `test/dummy/db/migrate/20250101000000_enable_pgcrypto_extension.rb`

### TailwindCSS
Tailwind v4 is configured and ready to use. Build with:
```bash
cd test/dummy
bin/rails tailwindcss:build
```

Or run in watch mode:
```bash
cd test/dummy
bin/dev  # Starts Rails and Tailwind watch
```

### Codespaces CSRF Handling
When running in Codespaces (`ENV["CODESPACES"] == "true"`):
- CSRF origin check is relaxed for ease of use
- CSRF tokens remain enabled for security
- Access via consistent hostname for best results

## Testing

Run the test suite:
```bash
bundle exec rake test
```

Run RuboCop:
```bash
bundle exec rubocop
```

## Common Tasks

### Add a New Controller
```bash
# In the engine root
touch app/controllers/gem_template/posts_controller.rb
```

### Add a New Migration
```bash
cd test/dummy
bin/rails generate migration CreatePosts title:string content:text
bin/rails db:migrate
```

### Update Routes
Edit `config/routes.rb` in the engine root.

### Install in a Host App
```bash
# In your Rails app
bundle add gem_template --git "https://github.com/bowerbird-app/gem_template"

# Or in Gemfile:
gem "gem_template", github: "bowerbird-app/gem_template"

# Then run:
bundle install
rails generate gem_template:install
```

## Troubleshooting

### Database Connection Issues
Ensure PostgreSQL is running and environment variables are set:
- `DB_HOST` (default: localhost)
- `DB_USER` (default: postgres)
- `DB_PASSWORD` (default: postgres)
- `DB_PORT` (default: 5432)

### Tailwind Not Loading
Run `bin/rails tailwindcss:build` in the dummy app directory.

### Port Already in Use
Use a different port:
```bash
bundle exec rails server -p 3001 -b 0.0.0.0
```

## Resources

- [Rails Engines Guide](https://guides.rubyonrails.org/engines.html)
- [TailwindCSS Documentation](https://tailwindcss.com/docs)
- [PostgreSQL UUID Documentation](https://www.postgresql.org/docs/current/datatype-uuid.html)
- [GitHub Codespaces Documentation](https://docs.github.com/en/codespaces)
