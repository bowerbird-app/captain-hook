# Security Policy

## Supported Versions

We release patches for security vulnerabilities. Which versions are eligible for receiving such patches depends on the CVSS v3.0 Rating:

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability in Captain Hook, please report it privately by sending an email to:

**security@bowerbird.app**

Please include the following information in your report:

- Type of issue (e.g., signature bypass, timing attack, SQL injection, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit it

### What to Expect

After you submit a report, you can expect:

1. **Acknowledgment**: We'll acknowledge receipt of your report within 48 hours
2. **Investigation**: We'll investigate and determine the severity and impact
3. **Updates**: We'll keep you informed about the progress of the fix
4. **Fix & Disclosure**: Once a fix is ready, we'll:
   - Release a patched version
   - Credit you in the security advisory (if desired)
   - Publish a security advisory with details

## Security Features in Captain Hook

Captain Hook is designed with security as a top priority. Key security features include:

### 1. Signature Verification
- Constant-time HMAC-SHA256 signature comparison to prevent timing attacks
- Support for multiple signature formats (hex, base64)
- Provider-specific verification logic

### 2. Replay Attack Prevention
- Timestamp validation with configurable tolerance
- Idempotency via unique external IDs
- Database-level unique constraints

### 3. Rate Limiting
- Per-provider rate limiting
- Configurable limits and periods
- Thread-safe implementation

### 4. Payload Security
- Payload size limits to prevent DoS attacks
- Safe JSON parsing (no eval or unsafe deserialization)
- Input validation before processing

### 5. Token-Based Authentication
- Cryptographically secure token generation
- Unique URLs per provider
- Constant-time token comparison

### 6. Secure Secret Management
- Environment variable-based secret storage
- ActiveRecord Encryption for database secrets
- No secrets in logs or error messages

### 7. Security Defaults
- All security features enabled by default
- Conservative limits and timeouts
- Fail-secure error handling

## Security Best Practices for Users

When integrating Captain Hook into your application:

1. **Always use HTTPS** for webhook endpoints in production
2. **Rotate secrets regularly** - set up a rotation schedule for signing secrets
3. **Monitor security logs** - watch for signature failures and rate limit violations
4. **Keep dependencies updated** - regularly update Captain Hook and its dependencies
5. **Use environment variables** - never commit secrets to version control
6. **Enable all security features** - don't disable timestamp validation or signature verification
7. **Set appropriate rate limits** - configure based on expected traffic patterns
8. **Review webhook payloads** - understand what data providers send

## Security Audits

Captain Hook undergoes regular security reviews:

- **Automated scanning**: Brakeman runs on every PR
- **Dependency auditing**: Bundler Audit checks for vulnerable gems
- **Code review**: All changes reviewed with security focus
- **Manual testing**: Security-focused test suite

## Known Security Considerations

### Environment-Specific Concerns

1. **Development/Test Environments**: 
   - Never use production secrets in development
   - Use separate webhook endpoints for testing
   - Be cautious with webhook forwarding tools (ngrok, etc.)

2. **Production Deployment**:
   - Use Redis for distributed rate limiting (in-memory only works for single server)
   - Enable database-level encryption at rest
   - Configure appropriate log retention policies
   - Implement IP whitelisting where possible (in addition to signature verification)

### PII and GDPR

Captain Hook may process webhook payloads containing Personal Identifiable Information (PII):

- Payloads are stored in the database by default
- Implement data retention policies appropriate for your use case
- Consider encrypting payload columns if they contain sensitive data
- Provide mechanisms for data deletion requests
- Review provider-specific data handling requirements

## Security Contacts

- **Security Issues**: security@bowerbird.app
- **General Support**: support@bowerbird.app
- **GitHub Security Advisories**: [GitHub Security](https://github.com/bowerbird-app/captain-hook/security)

## Disclosure Policy

When we receive a security bug report, we will:

1. Confirm the problem and determine affected versions
2. Audit code to find similar problems
3. Prepare fixes for all supported versions
4. Release new versions with the fix
5. Publish a security advisory on GitHub

We aim to complete this process within 30 days of the initial report.

## Hall of Fame

We appreciate security researchers who help make Captain Hook more secure:

<!-- Security researchers who report valid vulnerabilities will be listed here with their permission -->

*No vulnerabilities reported yet. Be the first!*

---

Last updated: January 30, 2026
