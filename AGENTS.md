# AGENTS.md - rbs-merge Development Guide

## 🎯 Project Overview

`rbs-merge` is a **format-specific implementation of the `*-merge` gem family** for RBS (Ruby Signature) files. It provides intelligent RBS file merging using AST analysis with the RBS parser.

**Core Philosophy**: Intelligent RBS type signature merging that preserves structure, comments, and formatting while applying updates from templates.

**Repository**: https://github.com/kettle-rb/rbs-merge
**Current Version**: 2.0.0
**Required Ruby**: >= 3.2.0 (currently developed against Ruby 4.0.1)

## ⚠️ AI Agent Terminal Limitations

### Terminal Output Is Available, but Each Command Is Isolated

**CRITICAL**: AI agents can reliably read terminal output when commands run in the background and the output is polled afterward. However, each terminal command should be treated as a fresh shell with no shared state.

### Use `mise` for Project Environment

**CRITICAL**: The canonical project environment now lives in `mise.toml`, with local overrides in `.env.local` loaded via `dotenvy`.

⚠️ **Watch for trust prompts**: After editing `mise.toml` or `.env.local`, `mise` may require trust to be refreshed before commands can load the project environment. That interactive trust screen can masquerade as missing terminal output, so commands may appear hung or silent until you handle it.

**Recovery rule**: If a `mise exec` command in this repo goes silent, appears hung, or terminal polling stops returning useful output, assume `mise trust` is needed first and recover with:

```bash
mise trust -C /home/pboling/src/kettle-rb/rbs-merge
mise exec -C /home/pboling/src/kettle-rb/rbs-merge -- bundle exec rspec
```

Do this before spending time on unrelated debugging; in this workspace, silent `mise` commands are usually a trust problem.

```bash
mise trust -C /home/pboling/src/kettle-rb/rbs-merge
```

### Local sibling-development mode is the ONLY supported mode

**CRITICAL**: `rbs-merge` evolves in lockstep with its sibling repositories under `/home/pboling/src/kettle-rb`.

- Support **only** local sibling-development mode.
- Do **not** add or preserve code paths for released gems, vendored gems, older sibling APIs, or compatibility shims.
- Do **not** test or validate in any non-sibling mode.
- If a sibling API changes, update `rbs-merge` to match the current sibling code instead of adding fallback logic.

✅ **CORRECT**:
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

### Prefer Internal Tools Over Terminal

Use `read_file`, `list_dir`, `grep_search`, `file_search` instead of terminal commands for gathering information. Only use terminal for running tests, installing dependencies, and git operations.

### Workspace layout

This repo is a sibling project inside the `/home/pboling/src/kettle-rb` workspace. Resolve dependencies from sibling repositories, not from `vendor/` and not from released gems.

### Local `examples/` scripts should use `nomono`

For `bundler/inline` scripts under `examples/`, follow the same local sibling wiring pattern as `gemfiles/modular/*_local.gemfile`:

- set `KETTLE_RB_DEV` to the sibling workspace root unless the caller already set it
- `require` `nomono/lib/nomono/bundler` from the local workspace
- use `eval_nomono_gems(...)` for sibling gems such as `ast-merge`, `tree_haver`, and `rbs-merge`
- keep parser/runtime gems like `rbs`, `ffi`, or `ruby_tree_sitter` explicit in the inline Gemfile
- do **not** hardcode `vendor/*` paths or brittle relative guesses like `../../..`

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

Run the plain command and inspect the full output afterward. Do not truncate test output.

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

## 📝 Project Conventions

### API Conventions

#### SmartMerger API
- `merge` – Returns a **String** (the merged RBS content)
- `merge_result` – Returns a **MergeResult** object
- `to_s` on MergeResult returns the merged content as a string

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

**Freeze Blocks**:
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
