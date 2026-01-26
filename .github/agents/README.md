# Captain Hook Custom Agents

This directory contains custom GitHub Copilot agents specialized for working with the Captain Hook webhook processing gem.

## Available Agents

### 1. Captain Hook Security Agent
**File**: `captain_hook_security.agent.md`
**Description**: Expert security agent for Captain Hook webhook processing gem

**Specializes in**:
- Signature verification (HMAC, constant-time comparison)
- Replay attack prevention (timestamp validation, idempotency)
- Rate limiting (per-provider, thread-safe)
- Secure webhook handling (payload size limits, safe parsing)
- Security testing and vulnerability detection
- Security code reviews

**Use when**:
- Implementing security features
- Reviewing webhook security
- Debugging signature verification issues
- Setting up rate limiting
- Investigating security vulnerabilities
- Performing security audits

### 2. Captain Hook Test QA Agent
**File**: `captain_hook_test_qa.agent.md`
**Description**: Expert test quality assurance agent for Captain Hook

**Specializes in**:
- Minitest best practices
- SimpleCov configuration and branch coverage
- Comprehensive test scenarios (happy and unhappy paths)
- Security testing
- Test isolation and organization
- Coverage analysis

**Use when**:
- Writing new tests
- Improving test coverage
- Setting up branch coverage
- Testing security features
- Debugging test failures
- Reviewing test quality

### 3. Captain Hook Refactor Agent
**File**: `captain_hook_refactor_dev.agent.md`
**Description**: Expert refactoring agent for Captain Hook

**Specializes in**:
- Keeping code DRY (Don't Repeat Yourself)
- Making code efficient yet readable
- Refactoring without sacrificing quality or security
- Performance optimization (profile-driven)
- Rails engine/gem refactoring patterns
- Code quality improvements

**Use when**:
- Refactoring duplicated code
- Improving code readability
- Optimizing performance bottlenecks
- Extracting service objects or modules
- Simplifying complex methods
- Reducing technical debt

### 4. Rails Gem Architect Agent
**File**: `rails_architect.agent.md`
**Description**: Senior Ruby on Rails Gem Engineer for engine/gem development

**Specializes in**:
- Rails engine architecture
- Gem development best practices
- Database migrations and indexing
- Engine isolation and namespacing
- Minitest testing strategies
- Git workflow and merge management

**Use when**:
- Building new engine features
- Setting up database migrations
- Configuring engine routing
- Implementing generators
- Following Rails conventions
- Managing gem dependencies

## How to Use Custom Agents

### Via GitHub Copilot Chat
1. Start a conversation with the specific agent by mentioning its name
2. Example: "@captain_hook_security Can you review the signature verification in stripe_verifier.rb?"

### Via Copilot CLI (Local Testing)
```bash
# Install the Copilot CLI
gh extension install github/gh-copilot

# Test an agent locally
gh copilot test-agent .github/agents/captain_hook_security.agent.md
```

### Agent Selection Guide

Choose the right agent for your task:

| Task | Recommended Agent |
|------|-------------------|
| Add signature verification | Security Agent |
| Fix timing attack vulnerability | Security Agent |
| Add rate limiting | Security Agent |
| Write tests for new feature | Test QA Agent |
| Improve test coverage | Test QA Agent |
| Setup branch coverage | Test QA Agent |
| Refactor duplicated code | Refactor Agent |
| Optimize slow query | Refactor Agent |
| Extract service object | Refactor Agent |
| Add new engine feature | Rails Architect Agent |
| Create migration | Rails Architect Agent |
| Setup new provider | Rails Architect Agent |

## Agent Characteristics

### Security Agent
- ✅ **Conservative**: Prioritizes security over convenience
- ✅ **Thorough**: Checks all security layers
- ✅ **Educational**: Explains security implications
- ⚠️ **Strict**: Will reject insecure patterns

### Test QA Agent
- ✅ **Comprehensive**: Tests both happy and unhappy paths
- ✅ **Coverage-Focused**: Enforces branch coverage
- ✅ **Practical**: Uses realistic test scenarios
- ⚠️ **Detail-Oriented**: May suggest extensive test cases

### Refactor Agent
- ✅ **Pragmatic**: Balances perfect code with shipping features
- ✅ **Incremental**: Suggests small, focused changes
- ✅ **Security-Conscious**: Never weakens security
- ⚠️ **Context-Aware**: Requires understanding before refactoring

### Rails Architect Agent
- ✅ **Conventional**: Follows "The Rails Way"
- ✅ **Modern**: Uses latest Rails features
- ✅ **Engine-Focused**: Understands isolation and namespacing
- ⚠️ **Opinionated**: Strong preferences for patterns

## Agent Synergies

Agents work well together in sequence:

1. **Build Feature** → Rails Architect Agent
   - Creates the feature following Rails conventions

2. **Add Security** → Security Agent
   - Reviews and secures the feature

3. **Write Tests** → Test QA Agent
   - Adds comprehensive test coverage

4. **Refactor** → Refactor Agent
   - Improves code quality and removes duplication

## Contributing

When adding new agents:
1. Follow the agent configuration format
2. Include clear description and specialization
3. Provide examples and patterns
4. Document when to use the agent
5. Update this README

## Resources

- [GitHub Copilot Custom Agents Documentation](https://gh.io/customagents/config)
- [Copilot CLI](https://gh.io/customagents/cli)
- [Captain Hook Documentation](../../README.md)

## Agent Files

All agent files use the `.agent.md` extension and follow the GitHub custom agent configuration format with YAML frontmatter.

```yaml
---
name: Agent Name
description: Brief description
---

# Agent content follows...
```

## Support

For issues with agents or suggestions for new agents, please open an issue in the repository.
