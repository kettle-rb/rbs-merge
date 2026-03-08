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

✅ **CORRECT**:
```bash
mise exec -C /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge -- bundle exec rspec
```

✅ **CORRECT**:
```bash
eval "$(mise env -C /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge -s bash)" && bundle exec rspec
```

❌ **WRONG**:
```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge
bundle exec rspec
```

❌ **WRONG**:
```bash
cd /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge && bundle exec rspec
```

### Prefer Internal Tools Over Terminal

Use `read_file`, `list_dir`, `grep_search`, `file_search` instead of terminal commands for gathering information. Only use terminal for running tests, installing dependencies, and git operations.

### grep_search Cannot Search Nested Git Projects

This project is a nested git project inside the `ast-merge` workspace. The `grep_search` tool **cannot** search inside it. Use `read_file` and `list_dir` instead.

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
mise exec -C /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge -- bundle exec rspec

# Single file (disable coverage threshold check)
mise exec -C /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge -- env K_SOUP_COV_MIN_HARD=false bundle exec rspec spec/rbs/merge/smart_merger_spec.rb

# RBS backend tests
mise exec -C /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge -- bundle exec rspec --tag rbs_backend
mise exec -C /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge -- bundle exec rspec --tag rbs_grammar
```

### Coverage Reports

```bash
mise exec -C /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge -- bin/rake coverage
mise exec -C /home/pboling/src/kettle-rb/ast-merge/vendor/rbs-merge -- bin/kettle-soup-cover -d
```

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
3. **Do NOT load vendor gems** – They are not part of this project; they do not exist in CI
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
