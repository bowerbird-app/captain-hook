# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Breaking Changes
- **Removed outgoing webhooks functionality**: CaptainHook now focuses exclusively on receiving and processing incoming webhooks
- Removed `OutgoingEvent` model and all associated functionality
- Removed `OutgoingJob` and circuit breaker service
- Removed `OutgoingEndpoint` configuration
- Removed outgoing webhooks admin interface
- Removed inter-gem communication documentation

### Added
- **Provider Management**: New `Provider` model for database-backed webhook provider configuration
- Provider admin interface at `/captain_hook/admin/providers`
  - Create, read, update, and delete webhook providers
  - View webhook URLs for sharing with providers
  - Copy-to-clipboard functionality for webhook URLs
  - Manage security settings per provider (rate limiting, payload limits, timestamp validation)
- Handlers admin interface at `/captain_hook/admin/providers/:id/handlers`
  - View registered handlers per provider
  - See handler configuration (priority, async, retry settings)
- Active/inactive status for providers to enable/disable webhook reception
- Enhanced security documentation and explanations in admin UI

### Changed
- Admin interface now defaults to providers list instead of incoming events
- Webhook tester page reworded to focus on provider connectivity testing
- Configuration now supports both in-memory and database-backed providers
- `IncomingController` updated to check provider active status
- README.md completely rewritten to reflect incoming-only functionality

### Removed
- All outgoing webhook functionality
- Circuit breaker service (was outgoing-specific)
- Outgoing events admin interface
- Inter-gem communication guides

## [0.1.0] - 2025-12-04

### Added
- Initial release
- Rails mountable engine structure
- PostgreSQL with UUID primary keys support
- TailwindCSS v4 integration
- GitHub Codespaces devcontainer configuration
- Docker Compose setup with PostgreSQL and Redis
- Install generator for host applications
- Comprehensive README and documentation
- Basic test suite with Minitest

[Unreleased]: https://github.com/bowerbird-app/captain_hook/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bowerbird-app/captain_hook/releases/tag/v0.1.0
