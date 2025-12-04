# GemTemplate

A template for building Rails mountable engine gems with PostgreSQL UUID primary keys, TailwindCSS, and GitHub Codespaces integration.

## 🚀 Features

- **Rails Mountable Engine**: Full-featured Rails engine that can be mounted in any Rails application
- **PostgreSQL with UUIDs**: Configured to use UUID primary keys by default
- **TailwindCSS**: Modern styling with TailwindCSS v4
- **GitHub Codespaces Ready**: Complete devcontainer setup with Docker Compose
- **Frictionless Development**: Everything configured to work out of the box

## 📋 Tech Stack

- Ruby 3.3
- Rails 8.1
- PostgreSQL 16
- Redis 7
- TailwindCSS 4
- Docker & Docker Compose

## 🏁 Getting Started with Codespaces

### Using GitHub Codespaces

1. **Create a Codespace** on this repository
2. **Wait** for the devcontainer to build and the `postCreateCommand` to complete
3. **Start the development server**:
   ```bash
   cd test/dummy
   bin/dev
   ```
4. **Open the app** by clicking on the forwarded port 3000 in the Codespaces UI
5. **Visit the engine** at `/gem_template`

The `bin/dev` command uses [foreman](https://github.com/ddollar/foreman) to run multiple processes defined in `Procfile.dev`:
- **Rails server** - bound to `0.0.0.0` for Codespaces port forwarding
- **TailwindCSS watcher** - automatically rebuilds CSS when views change

The devcontainer automatically:
- Installs all dependencies
- Sets up the PostgreSQL database
- Builds TailwindCSS assets
- Configures the environment

### CSRF Protection in Codespaces

The dummy app is configured to relax CSRF origin checks when running in Codespaces (when `ENV["CODESPACES"] == "true"`). CSRF authenticity tokens remain enabled. For best results, access your app consistently via either:
- The GitHub Codespaces forwarded URL (*.app.github.dev)
- localhost:3000 (if port forwarding is set to local)

## 🔧 Local Development Setup

### Prerequisites

- Ruby 3.3
- PostgreSQL 16
- Redis 7
- Node.js (for TailwindCSS)

### Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/bowerbird-app/gem_template.git
   cd gem_template
   ```

2. **Install dependencies**:
   ```bash
   bundle install
   cd test/dummy
   bundle install
   ```

3. **Setup database**:
   ```bash
   cd test/dummy
   bin/rails db:prepare
   ```

4. **Build TailwindCSS**:
   ```bash
   cd test/dummy
   bin/rails tailwindcss:build
   ```

5. **Start the development server**:
   ```bash
   cd test/dummy
   bin/dev
   ```

   This runs both the Rails server and TailwindCSS watcher. Alternatively, run just the server:
   ```bash
   bundle exec rails server
   ```

6. **Visit** http://localhost:3000/gem_template

## 🎯 Using This Template

### Creating Your Own Engine

1. **Fork this repository** or use it as a template
2. **Rename the gem**:
   - Update `gem_template.gemspec`
   - Rename `lib/gem_template*` files
   - Update module names from `GemTemplate` to your engine name
   - Update `config/routes.rb` mount path
3. **Customize** the engine by adding your controllers, models, and views

### Mounting in a Host Application

1. **Add to your Gemfile**:
   ```ruby
   gem "gem_template", github: "bowerbird-app/gem_template"
   # or
   gem "gem_template", path: "../gem_template"
   ```

2. **Run the installer**:
   ```bash
   rails generate gem_template:install
   ```

3. **Or manually mount** in your `config/routes.rb`:
   ```ruby
   mount GemTemplate::Engine, at: "/gem_template"
   ```

## 🐳 Docker Compose Services

The devcontainer includes three services:

### Database (PostgreSQL)
- Image: `postgres:16`
- Port: `5432`
- Default database: `app_development`
- UUID support enabled via `pgcrypto` extension

### Redis
- Image: `redis:7-alpine`
- Port: `6379`
- Data persisted in volume

### App
- Built from `.devcontainer/Dockerfile`
- Ruby 3.3 slim base
- All Rails dependencies pre-installed
- Bundle path: `/usr/local/bundle`

## 🧪 Testing

Run the test suite:

```bash
bundle exec rake test
```

## 📁 Project Structure

```
gem_template/
├── app/
│   ├── controllers/gem_template/    # Engine controllers
│   └── views/gem_template/          # Engine views
├── config/
│   └── routes.rb                    # Engine routes
├── lib/
│   ├── gem_template/
│   │   ├── engine.rb                # Engine definition
│   │   └── version.rb               # Version
│   ├── gem_template.rb              # Main gem file
│   └── generators/                  # Rails generators
├── test/
│   └── dummy/                       # Test Rails app
├── .devcontainer/
│   ├── devcontainer.json           # Codespaces config
│   ├── docker-compose.yml          # Docker services
│   └── Dockerfile                  # App container
├── Gemfile
├── Rakefile
└── gem_template.gemspec
```

## 🔒 Security

- RuboCop configured for code quality
- CSRF protection enabled
- Environment-based configuration
- No secrets committed to repository

## 📝 Development Workflow

1. Make changes to engine code in `app/`, `config/`, or `lib/`
2. Test changes in the dummy app (`test/dummy`)
3. Run tests: `bundle exec rake test`
4. Commit and push changes

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## 📄 License

This project is available under the MIT License. See the [MIT-LICENSE](MIT-LICENSE) file for details.

## 🙏 Acknowledgments

- Built with Rails mountable engine architecture
- Inspired by modern Ruby gem development practices
- Tailored for GitHub Codespaces development

---

**Happy coding! 🎉**

