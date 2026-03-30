# AGENTS.md - rbs-merge Development Guide

# AGENTS.md - Development Guide

## 🎯 Project Overview

Full suite spec runs:

```bash
mise exec -C /path/to/project -- bundle exec rspec
```

For single file, targeted, or partial spec runs the coverage threshold **must** be disabled.
Use the `K_SOUP_COV_MIN_HARD=false` environment variable to disable hard failure:

This project is a **RubyGem** managed with the [kettle-rb](https://github.com/kettle-rb) toolchain.

**Repository**: https://github.com/kettle-rb/rbs-merge
**Current Version**: 2.0.0
**Required Ruby**: >= 3.2.0 (currently developed against Ruby 4.0.1)

## ⚠️ AI Agent Terminal Limitations

### Terminal Output Is Available, but Each Command Is Isolated

**Minimum Supported Ruby**: See the gemspec `required_ruby_version` constraint.
**Local Development Ruby**: See `.tool-versions` for the version used in local development (typically the latest stable Ruby).

### Use `mise` for Project Environment

**CRITICAL**: The canonical project environment lives in `mise.toml`, with local overrides in `.env.local` loaded via `dotenvy`.

⚠️ **Watch for trust prompts**: After editing `mise.toml` or `.env.local`, `mise` may require trust to be refreshed before commands can load the project environment. Until that trust step is handled, commands can appear hung or produce no output, which can look like terminal access is broken.

**Recovery rule**: If a `mise exec` command goes silent or appears hung, assume `mise trust` is the first thing to check. Recover by running:

```bash
mise trust -C /home/pboling/src/kettle-rb/rbs-merge
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bundle exec rspec
```

```bash
mise trust -C /path/to/project
mise exec -C /path/to/project -- bundle exec rspec
```

Do this before spending time on unrelated debugging; in this workspace pattern, silent `mise` commands are usually a trust problem first.

```bash
mise trust -C /home/pboling/src/kettle-rb/rbs-merge
```

### Local sibling-development mode is the ONLY supported mode

## 🏗️ Architecture

### Toolchain Dependencies

This gem is part of the **kettle-rb** ecosystem. Key development tools:

❌ **AVOID** when possible:
- `run_in_terminal` for information gathering

Only use terminal for:
- Running tests (`bundle exec rspec`)
- Installing dependencies (`bundle install`)
- Git operations that require interaction
- Commands that actually need to execute (not just gather info)

✅ **CORRECT** — Run self-contained commands with `mise exec`:

```bash
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bundle exec rspec
```

✅ **CORRECT**:
```bash
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bundle exec rake magic
```

❌ **WRONG**:
```bash
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- env KETTLE_RB_DEV=false bundle exec rspec
```

❌ **WRONG**:
```bash
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bundle exec rspec  # after adding fallback code for old dependencies
```

```bash
mise exec -C /path/to/project -- bundle exec rspec
```

✅ **CORRECT** — If you need shell syntax first, load the environment in the same command:
```bash
eval "$(mise env -C /path/to/project -s bash)" && bundle exec rspec
```

❌ **WRONG** — Do not rely on a previous command changing directories:
```bash
cd /path/to/project
bundle exec rspec
```

❌ **WRONG** — A chained `cd` does not give directory-change hooks time to update the environment:
```bash
cd /path/to/project && bundle exec rspec
```

### Prefer Internal Tools Over Terminal

### Environment Variable Helpers

```ruby
before do
  stub_env("MY_ENV_VAR" => "value")
end

before do
  hide_env("HOME", "USER")
end
```

### Dependency Tags

Use dependency tags to conditionally skip tests when optional dependencies are not available:

### Workspace layout

### Running Commands

Always make commands self-contained. Use `mise exec -C /home/pboling/src/kettle-rb/prism-merge -- ...` so the command gets the project environment in the same invocation.

### Local `examples/` scripts should use `nomono`

```bash
mise exec -C /path/to/project -- bin/rake coverage
mise exec -C /path/to/project -- bin/kettle-soup-cover -d
```

**Key ENV variables** (set in `mise.toml`, with local overrides in `.env.local`):

✅ **PREFERRED** — Use internal tools:
- `grep_search` instead of `grep` command
- `file_search` instead of `find` command
- `read_file` instead of `cat` command
- `list_dir` instead of `ls` command
- `replace_string_in_file` or `create_file` instead of `sed` / manual editing

Recommended pattern:

```ruby
WORKSPACE_ROOT = File.expand_path("../..", __dir__)
ENV["KETTLE_RB_DEV"] = WORKSPACE_ROOT unless ENV.key?("KETTLE_RB_DEV")

require "bundler/inline"

gemfile do
  source "https://gem.coop"
  require File.expand_path("nomono/lib/nomono/bundler", WORKSPACE_ROOT)

  gem "benchmark"
  gem "rbs"

  eval_nomono_gems(
    gems: %w[ast-merge tree_haver rbs-merge],
    prefix: "KETTLE_RB",
    path_env: "KETTLE_RB_DEV",
    vendored_gems_env: "VENDORED_GEMS",
    vendor_gem_dir_env: "VENDOR_GEM_DIR",
    debug_env: "KETTLE_DEV_DEBUG"
  )
end
```

### NEVER Pipe Test Commands Through head/tail

When you do run tests, keep the full output visible so you can inspect failures completely.

## 🏗️ Architecture: Format-Specific Implementation

### What rbs-merge Provides

- **`Rbs::Merge::SmartMerger`** – RBS-specific SmartMerger implementation
- **`Rbs::Merge::FileAnalysis`** – RBS file analysis with class/module/method extraction
- **`Rbs::Merge::NodeWrapper`** – Wrapper for RBS AST nodes
- **`Rbs::Merge::MergeResult`** – RBS-specific merge result
- **`Rbs::Merge::ConflictResolver`** – RBS conflict resolution
- **`Rbs::Merge::FreezeNode`** – RBS freeze block support
- **`Rbs::Merge::DebugLogger`** – RBS-specific debug logging

### Key Dependencies

| Gem | Role |
|-----|------|
| `ast-merge` (~> 4.0) | Base classes and shared infrastructure |
| `tree_haver` (~> 5.0) | Unified parser adapter (wraps RBS) |
| `rbs` (>= 3.10) | Ruby type signature parser |
| `version_gem` (~> 1.1) | Version management |

### Parser Backend

rbs-merge uses the RBS parser exclusively via TreeHaver's `:rbs_backend`:

| Backend | Parser | Platform | Notes |
|---------|--------|----------|-------|
| `:rbs_backend` | RBS gem | MRI only | Official Ruby type signature parser |

| Tool | Purpose |
|------|---------|
| `kettle-dev` | Development dependency: Rake tasks, release tooling, CI helpers |
| `kettle-test` | Test infrastructure: RSpec helpers, stubbed_env, timecop |
| `kettle-jem` | Template management and gem scaffolding |

### Executables (from kettle-dev)

| Executable | Purpose |
|-----------|---------|
| `kettle-release` | Full gem release workflow |
| `kettle-pre-release` | Pre-release validation |
| `kettle-changelog` | Changelog generation |
| `kettle-dvcs` | DVCS (git) workflow automation |
| `kettle-commit-msg` | Commit message validation |
| `kettle-check-eof` | EOF newline validation |

## 📁 Project Structure

```
lib/rbs/merge/
├── smart_merger.rb          # Main SmartMerger implementation
├── file_analysis.rb         # RBS file analysis
├── node_wrapper.rb          # AST node wrapper
├── merge_result.rb          # Merge result object
├── conflict_resolver.rb     # Conflict resolution
├── freeze_node.rb           # Freeze block support
├── debug_logger.rb          # Debug logging
└── version.rb

spec/rbs/merge/
├── smart_merger_spec.rb
├── file_analysis_spec.rb
├── node_wrapper_spec.rb
└── integration/
```

```
lib/
├── <gem_namespace>/           # Main library code
│   └── version.rb             # Version constant (managed by kettle-release)
spec/
├── fixtures/                  # Test fixture files (NOT auto-loaded)
├── support/
│   ├── classes/               # Helper classes for specs
│   └── shared_contexts/       # Shared RSpec contexts
├── spec_helper.rb             # RSpec configuration (loaded by .rspec)
gemfiles/
├── modular/                   # Modular Gemfile components
│   ├── coverage.gemfile       # SimpleCov dependencies
│   ├── debug.gemfile          # Debugging tools
│   ├── documentation.gemfile  # YARD/documentation
│   ├── optional.gemfile       # Optional dependencies
│   ├── rspec.gemfile          # RSpec testing
│   ├── style.gemfile          # RuboCop/linting
│   └── x_std_libs.gemfile     # Extracted stdlib gems
├── ruby_*.gemfile             # Per-Ruby-version Appraisal Gemfiles
└── Appraisal.root.gemfile     # Root Gemfile for Appraisal builds
.git-hooks/
├── commit-msg                 # Commit message validation hook
├── prepare-commit-msg         # Commit message preparation
├── commit-subjects-goalie.txt # Commit subject prefix filters
└── footer-template.erb.txt    # Commit footer ERB template
```

## 🔧 Development Workflows

### Running Tests

```bash
# Full suite
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bundle exec rspec

# Single file (disable coverage threshold check)
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/rbs/merge/smart_merger_spec.rb

# Split-suite validation in local sibling mode
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bin/rspec-ffi
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bundle exec rake remaining_specs
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bundle exec rake magic
```

```bash
mise exec -C /path/to/project -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/path/to/spec.rb
```

### Coverage Reports

```bash
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bin/rake coverage
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bin/kettle-soup-cover -d
```

## 🚫 No backward compatibility policy

1. Do **not** add `defined?` guards, fallback `Struct`s, or dual old/new API branches for sibling libraries.
2. Do **not** keep release-mode or vendored-mode Gemfile branches.
3. Do **not** preserve dead compatibility comments or instructions that reference old layouts.
4. When behavior differs between current sibling code and an older release, follow the current sibling code and update tests accordingly.
5. If a helper from `ast-merge`, `tree_haver`, `kettle-dev`, `kettle-test`, or `kettle-soup-cover` is required, depend on the current sibling implementation directly.

- `K_SOUP_COV_DO=true` – Enable coverage
- `K_SOUP_COV_MIN_LINE` – Line coverage threshold
- `K_SOUP_COV_MIN_BRANCH` – Branch coverage threshold
- `K_SOUP_COV_MIN_HARD=true` – Fail if thresholds not met

### Code Quality

```bash
mise exec -C /path/to/project -- bundle exec rake reek
mise exec -C /path/to/project -- bundle exec rubocop-gradual
```

### Releasing

```bash
bin/kettle-pre-release    # Validate everything before release
bin/kettle-release        # Full release workflow
```

## 📝 Project Conventions

### API Conventions

#### SmartMerger API

### Test Infrastructure

- Uses `kettle-test` for RSpec helpers (stubbed_env, block_is_expected, silent_stream, timecop)
- Uses `Dir.mktmpdir` for isolated filesystem tests
- Spec helper is loaded by `.rspec` — never add `require "spec_helper"` to spec files

#### RBS-Specific Features

**Class/Module Merging**:
```rbs
# Template
class MyClass
  def foo: () -> String
end

# Destination
class MyClass
  def bar: () -> Integer
  def foo: () -> String  # Custom implementation
end
```

### Freeze Block Preservation

Template updates preserve custom code wrapped in freeze blocks:

```rbs
# rbs-merge:freeze
class CustomType
  attr_reader custom: String
end
# rbs-merge:unfreeze

class StandardType
  attr_reader name: String
end
```

```ruby
# kettle-jem:freeze
# ... custom code preserved across template runs ...
# kettle-jem:unfreeze
```

### Modular Gemfile Architecture

Gemfiles are split into modular components under `gemfiles/modular/`. Each component handles a specific concern (coverage, style, debug, etc.). The main `Gemfile` loads these modular components via `eval_gemfile`.

### Forward Compatibility with `**options`

**CRITICAL**: All constructors and public API methods that accept keyword arguments MUST include `**options` as the final parameter for forward compatibility.

## 🧪 Testing Patterns

### TreeHaver Dependency Tags

**Available tags**:
- `:rbs_grammar` – Requires RBS grammar
- `:rbs_backend` – Requires RBS backend
- `:rbs_parsing` – Requires RBS parser

✅ **CORRECT**:
```ruby
RSpec.describe Rbs::Merge::SmartMerger, :rbs_backend do
  # Skipped if RBS parser not available
end
```

❌ **WRONG**:
```ruby
before do
  skip "Requires RBS" unless defined?(RBS)  # DO NOT DO THIS
end
```

## 💡 Key Insights

1. **Type signature merging**: RBS definitions matched by name (class/module/method)
2. **Method overloads**: Multiple method signatures can coexist
3. **Generic types**: Type parameters preserved during merge
4. **Interface definitions**: Interfaces matched by name
5. **Freeze blocks use `# rbs-merge:freeze`**: Standard comment syntax
6. **MRI only**: RBS parser only works on MRI Ruby

```ruby
RSpec.describe SomeClass, :prism_merge do
  # Skipped if prism-merge is not available
end
```

## 🚫 Common Pitfalls

1. **RBS requires MRI**: Does not work on JRuby or TruffleRuby
2. **NEVER use manual skip checks** – Use dependency tags (`:rbs_backend`, `:rbs_grammar`)
3. **Do NOT add vendor/release fallback paths** – local sibling repositories are the only supported dependency source
4. **Use `tmp/` for temporary files** – Never use `/tmp` or other system directories
5. **Do NOT expect `cd` to persist** – Every terminal command is isolated; use a self-contained `mise exec -C ... -- ...` invocation.
6. **Do NOT rely on prior shell state** – Previous `cd`, `export`, aliases, and functions are not available to the next command.

## 🔧 RBS-Specific Notes

### Declaration Types

```rbs
class MyClass                   # Class declaration
  attr_reader name: String     # Attribute
  def foo: () -> String        # Method signature
end

module MyModule                 # Module declaration
  def self.bar: () -> Integer  # Module method
end

interface _Enumerable[T]        # Interface with type parameter
  def each: () { (T) -> void } -> void
end

type status = :pending | :done  # Type alias
```

### Merge Behavior

- **Classes**: Matched by class name; methods merged within
- **Methods**: Matched by method name; signatures can be overloaded
- **Interfaces**: Matched by interface name
- **Type aliases**: Matched by type name
- **Comments**: Preserved when attached to declarations
- **Freeze blocks**: Protect customizations from template updates
- **Generic types**: Type parameters preserved and matched

1. **NEVER add backward compatibility** — No shims, aliases, or deprecation layers. Bump major version instead.
2. **NEVER expect `cd` to persist** — Every terminal command is isolated; use a self-contained `mise exec -C ... -- ...` invocation.
3. **NEVER pipe test output through `head`/`tail`** — Run tests without truncation so you can inspect the full output.
4. **Terminal commands do not share shell state** — Previous `cd`, `export`, aliases, and functions are not available to the next command.
