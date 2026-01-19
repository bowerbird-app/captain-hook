# Signing Secret Storage

CaptainHook needs to store webhook signing secrets to verify incoming webhook signatures. This document explains the storage options and security considerations.

## Current Implementation: Rails Encrypted Attributes

**Enabled by default** in `app/models/captain_hook/provider.rb`:

```ruby
encrypts :signing_secret, deterministic: false
```

### How It Works

1. **Storage**: Secrets are encrypted in the database using AES-256-GCM
2. **Keys**: Encryption keys stored in Rails credentials or ENV variables
3. **Transparent**: Automatically decrypts when accessing `provider.signing_secret`
4. **Non-deterministic**: Same value encrypted differently each time (more secure)

### Setting Up Encryption Keys

#### Option A: Rails Credentials (Default)

```bash
# Generate keys and add to credentials
rails db:encryption:init

# This generates keys like:
# active_record_encryption:
#   primary_key: <long key>
#   deterministic_key: <long key>
#   key_derivation_salt: <long key>
```

Add these to your credentials:

```bash
EDITOR="code --wait" rails credentials:edit
```

#### Option B: Environment Variables (Recommended for Production)

```bash
# .env or production environment
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=your_primary_key
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=your_deterministic_key
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=your_salt
```

### Security Benefits

✅ **Encryption at rest** - Secrets encrypted in database  
✅ **Application-level encryption** - DB admins can't read secrets  
✅ **Automatic rotation** - Can re-encrypt with new keys  
✅ **No code changes** - Transparent to application  

---

## Alternative: Environment Variables

Some teams prefer storing secrets in ENV instead of the database.

### Implementation Pattern

**Store reference in database:**

```ruby
# In provider record
signing_secret_key: "STRIPE_PRODUCTION_SECRET"

# In environment
STRIPE_PRODUCTION_SECRET=whsec_abc123...
```

**Update verifier to read from ENV:**

```ruby
def signing_secret
  key = read_attribute(:signing_secret_key)
  ENV[key] || read_attribute(:signing_secret)
end
```

### Tradeoffs

**Pros:**
- Secrets never in database
- Easy to rotate via deployment
- Works well with K8s secrets, Vault, etc.
- Familiar pattern for DevOps teams

**Cons:**
- Requires deployment to change secrets
- ENV pollution with many providers
- Admin UI can't manage secrets easily
- Need separate secrets management

---

## Recommendation for Your Boss

### Use Rails Encryption When:
- ✅ Multiple providers per environment
- ✅ Self-service provider management needed
- ✅ Secrets change frequently
- ✅ Want admin UI to manage everything
- ✅ Don't have external secrets manager

### Use ENV Variables When:
- ✅ Few static providers
- ✅ Using external secrets manager (Vault, AWS Secrets Manager)
- ✅ Strict separation of config and code
- ✅ Deployment-based secret rotation
- ✅ DevOps team manages all secrets

### Hybrid Approach (Best of Both):

```ruby
# Support both!
def signing_secret
  # First check ENV for override
  env_key = "#{name.upcase}_WEBHOOK_SECRET"
  ENV[env_key].presence || super
end
```

This lets you:
- Store in DB for most providers (encrypted)
- Override via ENV for sensitive providers
- Migrate between approaches without code changes

---

## Migration Path

If you need to switch from encrypted DB to ENV:

```ruby
# 1. Export secrets
CaptainHook::Provider.find_each do |provider|
  puts "export #{provider.name.upcase}_WEBHOOK_SECRET=#{provider.signing_secret}"
end

# 2. Add ENV variables to your deployment

# 3. Update model to prefer ENV (hybrid approach above)

# 4. Optionally clear DB secrets
CaptainHook::Provider.update_all(signing_secret: nil)
```

---

## Security Checklist

Regardless of approach, ensure:

- [ ] HTTPS/TLS for all webhook endpoints
- [ ] Secrets never in version control
- [ ] Secrets never in logs
- [ ] Database backups encrypted
- [ ] ENV variables encrypted in CI/CD
- [ ] Regular secret rotation policy
- [ ] Audit trail for secret access
- [ ] Multi-factor auth for admins

---

## Additional Reading

- [Rails Encryption Guide](https://guides.rubyonrails.org/active_record_encryption.html)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [The Twelve-Factor App: Config](https://12factor.net/config)
