# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## [Unreleased]

### Added

- AGENTS.md
- **Dependency Tags Support**: Added `spec/support/dependency_tags.rb` to load shared
  dependency tags from tree_haver and ast-merge. This enables automatic exclusion of
  tests when required backends or dependencies are not available.
  - Tests tagged with `:ffi_backend`, `:java_backend`, `:rust_backend` are now properly
    excluded when those backends aren't available
  - Tests tagged with `:rbs_grammar` are excluded when tree-sitter-rbs isn't available
  - Tests tagged with `:rbs_parsing` work with any available RBS parsing backend
- FFI backend isolation for test suite
  - Added `bin/rspec-ffi` script to run FFI specs in isolation (before MRI backend loads)
  - Added `spec/spec_ffi_helper.rb` for FFI-specific test configuration
  - Updated Rakefile with `ffi_specs` and `remaining_specs` tasks
  - The `:test` task now runs FFI specs first, then remaining specs
- **BackendRegistry Integration**: RbsBackend now registers its availability checker with `TreeHaver::BackendRegistry`
  - Enables `TreeHaver::RSpec::DependencyTags` to detect RBS backend availability without hardcoded checks
  - Called automatically when backend is loaded: `TreeHaver::BackendRegistry.register_availability_checker(:rbs)`
- **TreeHaver backend integration** - rbs-merge now uses TreeHaver for all parsing,
  enabling cross-platform RBS parsing:
  - **`Rbs::Merge::Backends::RbsBackend`** - New TreeHaver-compatible backend module
    that wraps the RBS gem. Registered with TreeHaver via `register_language(:rbs, ...)`.
  - On MRI: Uses RBS gem backend (richer AST, comment association)
  - On JRuby: Uses tree-sitter-rbs via TreeHaver's Java backend
  - Backend selection respects `TreeHaver.with_backend()` and `TREE_HAVER_BACKEND` env var
- **`NodeWrapper#comment`** - Delegates to underlying RBS gem node's comment for
  leading comment association (RBS gem backend only)
- **`FileAnalysis#compute_tree_sitter_signature`** - Generates signatures for raw
  TreeHaver::Node objects from tree-sitter backend
- **`FileAnalysis#extract_tree_sitter_node_name`** - Extracts declaration names from
  tree-sitter nodes by traversing child nodes
- `node_typing` parameter for per-node-type merge preferences
  - Enables `preference: { default: :destination, special_type: :template }` pattern
  - Works with custom merge_types assigned via node_typing lambdas
- `match_refiner` parameter for fuzzy matching support
- `regions` and `region_placeholder` parameters for nested content merging

### Changed

- appraisal2 v3.0.6
- kettle-test v1.0.10
- stone_checksums v1.0.3
- [ast-merge v4.0.6](https://github.com/kettle-rb/ast-merge/releases/tag/v4.0.6)
- [tree_haver v5.0.5](https://github.com/kettle-rb/tree_haver/releases/tag/v5.0.5)
- tree_stump v0.2.0
  - fork no longer required, updates all applied upstream
- Updated documentation on hostile takeover of RubyGems
  - https://dev.to/galtzo/hostile-takeover-of-rubygems-my-thoughts-5hlo
- **RbsBackend refactored to use TreeHaver::Base classes**
  - `RbsBackend::Language` now inherits from `TreeHaver::Base::Language`
  - `RbsBackend::Parser` now inherits from `TreeHaver::Base::Parser`
  - `RbsBackend::Tree` now inherits from `TreeHaver::Base::Tree`
  - `RbsBackend::Node` now inherits from `TreeHaver::Base::Node`
  - Consistent API across all merge gem backends
- **Tree-sitter grammar registration** - `register_backend!` now registers both:
  - The RBS gem backend (Ruby-based parser, MRI only)
  - The tree-sitter-rbs grammar path (for native tree-sitter backends)
  - This enables `TreeHaver.parser_for(:rbs)` to use tree-sitter when available
- **FileAnalysis now uses TreeHaver exclusively** - Removed separate backend selection
  logic. `parse_rbs` now calls `TreeHaver.parser_for(:rbs)` which handles all backend
  selection automatically.
- **`node_start_line`/`node_end_line` helpers** - Now check for `start_line`/`end_line`
  methods first (TreeHaver::Node has these), falling back to `location` or `start_point`.
- **`ConflictResolver#declarations_identical?`** - Now compares text content instead of
  relying on object equality, enabling cross-backend comparison.
- **`ConflictResolver#canonical_type`** - Now handles TreeHaver::Node objects in addition
  to NodeWrapper and RBS gem nodes.
- **`ConflictResolver#has_members?`** - Now checks for `members` child nodes in
  TreeHaver::Node objects for tree-sitter backend support.
- **`ConflictResolver#resolve`** - Now checks for template freeze blocks first, ensuring
  frozen content from templates is preserved during merge.
- **`FileAligner#build_signature_map`** - FreezeNodes are now indexed by both their own
  signature AND the signatures of their contained nodes. This allows freeze blocks to
  match against the non-frozen version of the same declaration in the other file.
- **`MergeResult#add_freeze_block`** - Now uses the freeze_node's own analysis for line
  extraction, ensuring template freeze blocks use template lines (not destination lines).
- **`SmartMerger#process_match`** - Now handles template FreezeNodes correctly, adding
  them via `add_freeze_block` when the template side wins.
- **`SmartMerger#process_template_only`** - FreezeNodes from template are now always
  added (they represent protected content that must be preserved).
- **SmartMerger**: Added `**options` for forward compatibility
  - Accepts additional options that may be added to base class in future
  - Passes all options through to `SmartMergerBase`
- **ConflictResolver**: Added `**options` for forward compatibility
- **MergeResult**: Added `**options` for forward compatibility
- **BREAKING**: `SmartMerger` now inherits from `Ast::Merge::SmartMergerBase`
  - Provides standardized options API consistent with all other `*-merge` gems
  - Gains automatic support for new SmartMergerBase features
  - `max_recursion_depth` parameter is still supported
  - `preference` now accepts Hash for per-type preferences

### Deprecated

### Removed

- **`FileAnalysis#rbs_gem_available?`** - Removed; TreeHaver handles backend availability
- **`FileAnalysis#parse_with_rbs_gem`** - Removed; replaced by `process_rbs_gem_result`
- **`FileAnalysis#parse_with_tree_sitter`** - Removed; replaced by `process_tree_sitter_result`
- **`backend:` parameter from `FileAnalysis#initialize`** - Removed; use
  `TreeHaver.with_backend()` to control backend selection

### Fixed

- ConflictResolver now applies Hash-based per-node-type preferences via `node_typing`.
- **Freeze blocks from template now preserved correctly** - Previously, freeze blocks
  from the template would not match destination declarations because their signatures
  differed. Now FreezeNodes are indexed by contained node signatures.
- **FreezeNode name extraction** - `extract_node_name` now handles TreeHaver::Node
  objects and extracts meaningful names for error messages.
- **`FreezeNode#get_start_line`/`get_end_line`** - Now properly handle nodes with
  direct `start_line`/`end_line` methods (TreeHaver::Node).
- **`SmartMerger#get_start_line`/`get_end_line`** - Added helper methods to support
  both NodeWrapper and RBS gem nodes in `reconstruct_declaration_with_merged_members`.

### Security

## [1.0.0] - 2025-12-12

- TAG: [v1.0.0][1.0.0t]
- COVERAGE: 98.56% -- 343/348 lines in 9 files
- BRANCH COVERAGE: 87.50% -- 98/112 branches in 9 files
- 96.61% documented

### Added

- Initial release

[Unreleased]: https://github.com/kettle-rb/rbs-merge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kettle-rb/rbs-merge/compare/7ae936a6ae844aee513264eecc39215eed53c313...v1.0.0
[1.0.0t]: https://github.com/kettle-rb/rbs-merge/tags/v1.0.0
