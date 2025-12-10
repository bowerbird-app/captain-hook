# GemTemplate

A template for building **Rails mountable engine gems** with PostgreSQL UUID primary keys, TailwindCSS, and GitHub Codespaces integration.

---

## ✅ What's Working

- ✓ Rails Engine mounted and operational
- ✓ PostgreSQL with UUID primary keys
- ✓ TailwindCSS styling (auto-rebuilds in development)
- ✓ Codespaces environment automatically sets up on build
- ✓ Install generator for host applications
- ✓ Migrations generator for database setup
- ✓ Service object pattern with Result monad

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

## 📚 Documentation

| Guide | Description |
|-------|-------------|
| [Renaming](docs/RENAMING.md) | Instructions for renaming this template gem to your own name. |
| [Installation](docs/INSTALLING.md) | Step-by-step guide for installing this engine in a host Rails application. |
| [Configuration](docs/CONFIGURATION.md) | Details on configuring the gem via initializers and environment variables. |
| [Database Migrations](docs/MIGRATIONS.md) | How to generate and manage database migrations for the engine. |
| [Service Objects](docs/SERVICES.md) | Explanation of the Service Object pattern and Result monad used for business logic. |
| [Engine Hooks](docs/HOOKS.md) | Guide to customizing engine behavior using lifecycle and service hooks. |
| [Asset Architecture](docs/CSS_JS_ASSETS_ARCHITECTURE.md) | Details on TailwindCSS setup and asset pipeline integration. |
| [Security](SECURITY.md) | Security considerations. |
| [Changelog](CHANGELOG.md) | Version history. |

---

## 📁 Project Structure

```
gem_template/
├── app/
│   ├── controllers/gem_template/
│   └── views/gem_template/
├── config/routes.rb
├── db/migrate/              # Engine migrations
├── lib/
│   ├── gem_template.rb
│   ├── gem_template/
│   │   ├── configuration.rb
│   │   ├── engine.rb
│   │   ├── version.rb
│   │   └── services/        # Service objects
│   │       ├── base_service.rb
│   │       └── example_service.rb
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

## 📄 License

MIT – see [MIT-LICENSE](MIT-LICENSE)

---

**Happy coding! 🎉**

