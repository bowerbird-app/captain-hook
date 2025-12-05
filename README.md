# GemTemplate

A template for building **Rails mountable engine gems** with PostgreSQL UUID primary keys, TailwindCSS, and GitHub Codespaces integration.

---

## ✅ What's Working

- ✓ Rails Engine mounted and operational
- ✓ PostgreSQL with UUID primary keys
- ✓ TailwindCSS styling (auto-rebuilds in development)
- ✓ Codespaces environment automatically sets up on build
- ✓ Install generator for host applications

---

## 🚀 Quick Start

### GitHub Codespaces (Recommended)

1. Click **Code** → **Codespaces** → **Create codespace**
2. Wait for setup to complete (~3-5 minutes)
3. Run:
   ```bash
   cd test/dummy
   bin/dev
   ```
4. Open port 3000 and visit `/gem_template`

→ [Codespaces Setup Guide](docs/CODESPACES.md)

### Local Development

1. Clone and install dependencies
2. Setup database and build Tailwind
3. Run `bin/dev`

→ [Local Development Guide](docs/LOCAL_DEVELOPMENT.md)

---

## ✏️ Rename This Gem

This gem is currently named `gem_template`. Rename it to your own:

```bash
bin/rename_gem your_gem_name
```

Preview changes first with `--dry-run`:

```bash
bin/rename_gem your_gem_name --dry-run
```

→ [Renaming Guide](docs/RENAMING.md)

---

## 🎨 Tailwind CSS

- CSS is prebuilt when Codespaces starts
- Auto-rebuilds when using `bin/dev`
- Host apps include engine views via the install generator

→ [Tailwind Setup](docs/TAILWIND.md)

---

## ⚙️ Configuration

Configure the gem in your host app:

```ruby
# config/initializers/gem_template.rb
GemTemplate.configure do |config|
  config.api_key = ENV["GEM_TEMPLATE_API_KEY"]
  config.enable_feature_x = true
  config.timeout = 10
end
```

→ [Configuration Guide](docs/CONFIGURATION.md)

---

## 📦 Installing in a Host App

1. Add to your `Gemfile`:
   ```ruby
   gem "gem_template", github: "bowerbird-app/gem_template"
   ```

2. Run the install generator:
   ```bash
   bundle install
   rails generate gem_template:install
   ```

The generator mounts the engine, creates a config initializer, and configures Tailwind.

→ [Installation Guide](docs/INSTALLING.md)

---

## 🧪 Testing

```bash
bundle exec rake test
```

---

## 📁 Project Structure

```
gem_template/
├── app/
│   ├── controllers/gem_template/
│   └── views/gem_template/
├── config/routes.rb
├── lib/
│   ├── gem_template.rb
│   ├── gem_template/
│   │   ├── configuration.rb
│   │   ├── engine.rb
│   │   └── version.rb
│   └── generators/
├── test/dummy/              # Test Rails app
├── docs/                    # Documentation
└── gem_template.gemspec
```

---

## 📋 Tech Stack

| Component | Version |
|-----------|---------|
| Ruby | 3.3 |
| Rails | 8.1 |
| PostgreSQL | 16 |
| Redis | 7 |
| TailwindCSS | 4 |

---

## 📚 Documentation

| Guide | Description |
|-------|-------------|
| [Codespaces](docs/CODESPACES.md) | Devcontainer setup and Codespaces usage |
| [Local Development](docs/LOCAL_DEVELOPMENT.md) | Setup without Codespaces |
| [Configuration](docs/CONFIGURATION.md) | Configuration API and options |
| [Tailwind](docs/TAILWIND.md) | CSS setup and auto-rebuild |
| [Renaming](docs/RENAMING.md) | Rename script usage |
| [Installing](docs/INSTALLING.md) | Install in a host Rails app |
| [Security](SECURITY.md) | Security considerations |
| [Changelog](CHANGELOG.md) | Version history |

---

## 📄 License

MIT – see [MIT-LICENSE](MIT-LICENSE)

---

**Happy coding! 🎉**

