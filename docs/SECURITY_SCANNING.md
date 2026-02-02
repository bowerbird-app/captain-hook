# Security Scanning

This document describes the security scanning tools and processes for Captain Hook.

## Automated Security Scans

Every pull request automatically runs three security scans:

1. **Brakeman** - Rails security vulnerability scanner
2. **Bundler Audit** - Dependency vulnerability checker
3. **RuboCop Security** - Security-focused code analysis

These scans run via GitHub Actions and results are visible in the PR checks.

## Running Security Scans Locally

### Quick Scan (All Tools)

Run all security checks before committing:

```bash
./bin/security-scan
```

This will:
- Install required gems if needed
- Run Brakeman to check for security vulnerabilities
- Run Bundler Audit to check for vulnerable dependencies
- Run RuboCop Security checks (if available)
- Report all findings with colored output

### Individual Scans

#### Brakeman (Rails Security)

```bash
# Install
gem install brakeman

# Run with default output
brakeman

# Run with markdown output
brakeman --format markdown

# Run with JSON output for CI
brakeman --format json --output brakeman-report.json

# Configuration file: config/brakeman.json
```

**What it checks:**
- SQL injection vulnerabilities
- Cross-site scripting (XSS)
- Command injection
- Mass assignment
- Unsafe redirects
- Dangerous evaluation
- And 100+ other security issues

#### Bundler Audit (Dependency Vulnerabilities)

```bash
# Install
gem install bundler-audit

# Update vulnerability database
bundler-audit update

# Check for vulnerabilities
bundler-audit check

# Verbose output
bundler-audit check --verbose
```

**What it checks:**
- Known CVEs in gem dependencies
- Insecure gem sources (non-HTTPS)
- Out-of-date vulnerability database

#### RuboCop Security

```bash
# Install
gem install rubocop rubocop-rails

# Run only security checks
rubocop --only Security

# Auto-correct safe issues
rubocop --only Security --auto-correct
```

**What it checks:**
- Eval and system call usage
- YAML.load vulnerabilities
- Marshal.load dangers
- JSON parsing issues
- And other security patterns

## GitHub Actions Workflow

The security workflow (`.github/workflows/security.yml`) runs on:
- Every pull request to main/develop
- Every push to main
- Manual trigger via workflow_dispatch

### Workflow Jobs

1. **brakeman** - Scans Rails code for security vulnerabilities
   - Fails on high-confidence issues
   - Warns on excessive medium-confidence issues
   - Uploads reports as artifacts

2. **bundler-audit** - Checks dependencies for known CVEs
   - Fails on any known vulnerabilities
   - Updates vulnerability database first

3. **rubocop-security** - Analyzes code patterns
   - Checks security-focused cops
   - Uploads reports as artifacts

4. **security-summary** - Aggregates results
   - Runs after all checks complete
   - Provides summary in GitHub Actions

## Security Scan Results

### Understanding Brakeman Output

Brakeman categorizes issues by confidence level:
- **High**: Very likely to be a real security issue - must fix
- **Medium**: Could be a security issue - should review
- **Weak**: Possibly a security issue - may be false positive

Our CI fails on:
- Any high-confidence issues
- More than 3 medium-confidence issues

### Understanding Bundler Audit Output

Bundler Audit reports:
- CVE number (e.g., CVE-2023-12345)
- GHSA identifier (GitHub Security Advisory)
- Severity (Low, Medium, High, Critical)
- Affected versions
- Solution (which version to upgrade to)

Our CI fails on any known vulnerability.

### Understanding RuboCop Security Output

RuboCop reports security cops like:
- `Security/Eval` - Use of eval()
- `Security/YAMLLoad` - Use of YAML.load
- `Security/MarshalLoad` - Use of Marshal.load
- `Security/JSONLoad` - Use of JSON.load

These are usually legitimate issues that should be addressed.

## Fixing Security Issues

### High Priority (Critical)

1. **Signature bypass vulnerabilities**
   - Use constant-time comparison for all crypto operations
   - Example: Always use `secure_compare`, never `==` for signatures

2. **SQL injection**
   - Use parameterized queries
   - Never interpolate user input into SQL

3. **Command injection**
   - Avoid system calls with user input
   - Use safe libraries like `Open3`

4. **Eval/deserialization**
   - Never use `eval`, `YAML.load`, `Marshal.load` with untrusted data
   - Use safe alternatives like `JSON.parse`

### Medium Priority (Important)

1. **Dependency vulnerabilities**
   - Update vulnerable gems immediately
   - Check for security advisories

2. **Missing input validation**
   - Validate all external input
   - Check payload sizes, types, formats

3. **Timing attacks**
   - Use constant-time comparison
   - Don't leak information via timing

### Low Priority (Nice to Have)

1. **Code quality issues**
   - Refactor complex security-critical code
   - Add security-focused tests

2. **Documentation**
   - Document security assumptions
   - Add warnings about insecure usage

## Security Configuration

### Brakeman Configuration

Located at `config/brakeman.json`:

```json
{
  "application_path": ".",
  "skip_checks": [],
  "min_confidence": 2,
  "github_repo": "bowerbird-app/captain-hook"
}
```

### RuboCop Configuration

Add to `.rubocop.yml`:

```yaml
Security:
  Enabled: true

Security/Eval:
  Severity: error

Security/YAMLLoad:
  Severity: error
```

## Pre-commit Hooks

You can set up a pre-commit hook to run security scans automatically:

```bash
# Create .git/hooks/pre-commit
#!/bin/bash
./bin/security-scan || exit 1
```

Make it executable:
```bash
chmod +x .git/hooks/pre-commit
```

## Continuous Security

### Regular Practices

1. **Weekly**: Run `bundler-audit update && bundler-audit check`
2. **Before each release**: Run full security scan
3. **Monthly**: Review security logs and alerts
4. **Quarterly**: Security audit of critical paths

### Monitoring

Watch for:
- Failed signature verifications
- Rate limit violations
- Unusual traffic patterns
- Repeated timestamp failures

These may indicate attacks or misconfigurations.

## Security Reporting

If you discover a security vulnerability:

1. **DO NOT** open a public GitHub issue
2. Email security@bowerbird.app with details
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

See [SECURITY.md](../SECURITY.md) for full reporting guidelines.

## Resources

- [Brakeman Documentation](https://brakemanscanner.org/)
- [Bundler Audit](https://github.com/rubysec/bundler-audit)
- [RuboCop Security](https://docs.rubocop.org/rubocop/cops_security.html)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Rails Security Guide](https://guides.rubyonrails.org/security.html)

## Troubleshooting

### False Positives

If Brakeman reports a false positive:

1. Add it to the ignore file: `brakeman -I`
2. Document why it's a false positive
3. Consider refactoring to avoid the pattern

### Scan Failures in CI

If security scans fail in CI:

1. Run locally: `./bin/security-scan`
2. Review the specific failure
3. Fix the issue or update dependencies
4. Test locally before pushing

### Performance

If scans are slow:

1. Brakeman: Use `--faster` flag for quicker (less thorough) scans
2. Skip test files: Configure in `brakeman.json`
3. Parallel execution: Scans run in parallel in CI

---

Last updated: January 30, 2026
