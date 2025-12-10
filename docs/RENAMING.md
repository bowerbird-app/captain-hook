# Gem Rename Script

A utility script to rename the gem throughout the codebase.

## Usage

```bash
bin/rename_gem <new_name> [options]
```

### Basic Examples

```bash
# Rename using auto-detected current name
bin/rename_gem my_awesome_gem

# Names with spaces are automatically converted to snake_case
bin/rename_gem "my awesome gem"  # becomes my_awesome_gem

# Preview changes without applying them
bin/rename_gem my_awesome_gem --dry-run

# Override the detected current name
bin/rename_gem my_awesome_gem --from old_gem_name
```

### Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview all changes without modifying any files |
| `--from NAME` | Specify the current gem name (overrides auto-detection) |

## What Gets Renamed

The script updates all gem-related files and references:

### Files Renamed
- `<gem_name>.gemspec` → `<new_name>.gemspec`
- `lib/<gem_name>.rb` → `lib/<new_name>.rb`
- `test/<gem_name>_test.rb` → `test/<new_name>_test.rb`

### Directories Renamed
- `lib/<gem_name>/` → `lib/<new_name>/`
- `app/controllers/<gem_name>/` → `app/controllers/<new_name>/`
- `app/views/<gem_name>/` → `app/views/<new_name>/`
- `lib/generators/<gem_name>/` → `lib/generators/<new_name>/`

### Content Updated
The script performs two types of replacements in all relevant files:
- **snake_case**: `gem_template` → `new_gem_name`
- **PascalCase**: `GemTemplate` → `NewGemName`

Files updated include:
- `.gemspec`, `.rb`, `.erb`, `.md` files
- `Gemfile`, `Rakefile`, `routes.rb`
- Documentation files (`README.md`, `CHANGELOG.md`, etc.)
- Test files and test helper
- Dummy app configuration (`test/dummy/Gemfile`, `test/dummy/config/routes.rb`)

## Verification

After renaming, the script automatically runs verification tests to ensure:
- All files were renamed correctly
- No orphaned references to the old name remain
- Module names and class definitions are consistent

## Workflow

1. **Preview the changes** (recommended):
   ```bash
   bin/rename_gem my_new_name --dry-run
   ```

2. **Run the rename**:
   ```bash
   bin/rename_gem my_new_name
   ```

3. **Review changes**:
   ```bash
   git diff
   ```

4. **Run tests**:
   ```bash
   bundle exec rake test
   ```

5. **Commit**:
   ```bash
   git add -A && git commit -m "Rename gem to my_new_name"
   ```

## Notes

- The script will warn you if there are uncommitted git changes
- Auto-detection reads the gem name from the `.gemspec` file
- The verification tests are excluded from content replacement to preserve their reference strings
- Before publishing, verify your new gem name is available on [RubyGems.org](https://rubygems.org)
