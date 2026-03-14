# PLAN.md

## Goal
Integrate the shared Comment AST & Merge capability into `rbs-merge` so declaration-level comments and file structure survive type-signature merges with stable, valid RBS output.

`psych-merge` is the reference for shared comment behavior, but `rbs-merge` may need a hybrid approach because backend-specific comment/location support can vary.

## Current Status
- `rbs-merge` is a good medium-complexity target because declaration docs and comments matter in real RBS files.
- The gem has the standard merge-gem layout and is expected to merge declarations and members structurally.
- Comment support likely needs a backend-aware normalization layer rather than one parser-specific assumption.
- The main priority is keeping merged output valid RBS with stable declaration ownership.

## Integration Strategy
- Expose shared comment capability from file analysis and wrapped nodes.
- Use native backend comment ownership when available.
- Add source-augmented fallback only where backend parity is missing.
- Preserve document prelude/postlude comments, declaration-leading comments, and removed-node comment promotion.
- Keep the first implementation focused on declaration-level comments before finer-grained member comments.

## First Slices
1. Add shared comment capability plumbing to file analysis and node wrappers.
2. Preserve top-of-file comments and comment-only files.
3. Preserve declaration-leading comments when matched template declarations win.
4. Preserve comments for removed destination-only declarations when removal is enabled.
5. Expand to nested members, overloads, and backend parity once the basics are stable.

## First Files To Inspect
- `lib/rbs/merge/file_analysis.rb`
- `lib/rbs/merge/node_wrapper.rb`
- `lib/rbs/merge/smart_merger.rb`
- `lib/rbs/merge/conflict_resolver.rb`
- any backend-specific files under `lib/rbs/merge/`

## Tests To Add First
- file analysis specs for comment capability exposure
- smart merger specs for declaration-leading comments
- conflict resolver specs for removed declaration comment preservation
- backend parity specs for comment ownership where multiple backends exist
- reproducible fixtures for comment-heavy RBS files

## Risks
- Different backends may disagree about comment locations or ownership.
- Nested declarations and overloaded members can complicate association.
- Output must remain valid RBS even when comments are promoted or moved.
- A backend-specific implementation that is too clever may be hard to keep consistent.

## Success Criteria
- Shared comment capability is available through the analysis layer.
- Document and declaration-level comments survive common merges.
- Removed destination-only declarations can preserve comments safely.
- Backend differences are normalized well enough for stable test coverage.
- Reproducible fixtures cover representative typed-API comment layouts.

## Rollout Phase
- Phase 2 target.
- Recommended after the first-wave gems because backend normalization may be needed before comment ownership becomes stable.

## At-a-Glance Summary

### Foundation complete
- Shared comment capability plumbing is in place in the analysis layer: `comment_capability`, `comment_augmenter`, normalized regions/attachments, and declaration-level ownership fallback.
- Document prelude/postlude handling and comment-only boundary behavior are covered.

### Merge behavior complete
- Template-preferred matched declarations can keep destination-owned docs when the template lacks them.
- Removed destination-only declarations can promote their docs instead of silently dropping them.

### Backend/member parity mostly complete
- The native RBS path and the main tree-sitter-backed paths now agree on the key merge inputs that comment ownership depends on: top-level declaration extraction, nested member extraction, stable signatures, exact wrapper spans/text, and recursive member merge shape.
- Reproducible fixtures now cover adjacent declaration docs, removed-declaration promotion, reordered overloads, documented nested members, and alias-declaration docs.

### Remaining work
- No immediate comment-rollout slice remains beyond keeping the explicit backend runners green and adding new regression coverage only if a backend-specific ownership escape is reproduced.

## Latest `ast-merge` Comment Logic Checklist (2026-03-13)
- [x] Shared capability plumbing: `comment_capability`, `comment_augmenter`, normalized region/attachment access
- [x] Document boundary ownership: prelude/postlude analysis ownership, merge-path postlude/comment-only parity, and adjacent declaration fixture coverage are in place
- [x] Matched-node fallback: preserve destination declaration-leading comments under template preference
- [x] Removed-node preservation: keep/promote comments for removed destination-only declarations
- [x] Backend/fixture parity: backend parity means the native RBS path and the tree-sitter-backed paths must hand `Ast::Merge::Comment` the same merge-relevant facts: declaration/member extraction, stable signatures, exact wrapper ranges/text, recursive member shape, and comment-ownership inputs. Fixture parity means real reproducible RBS merge scenarios must stay stable end-to-end, not just isolated wrapper specs. Shared capability plumbing, declaration-leading fallback, removed-node comment promotion, root boundary handling, nested member extraction and recursive merge parity, exact declaration/wrapper parity for the major top-level RBS shapes, and reproducible reordered-overload / documented-member / alias-declaration comment fixtures are now revalidated across the native path, the primary tree-sitter-backed paths, the explicit Rust split, and the isolated FFI runner.

Current parity status: complete for the current Phase 2 rollout scope. `rbs-merge` now exposes shared comment capability, preserves declaration-level comments in the main merge paths, and keeps the native RBS plus explicit tree-sitter-backed backends aligned on the key structural inputs and reproducible merge outputs that comment ownership depends on.

Next execution target: regression-only unless a newly reproduced backend-specific ownership or member-shape escape reopens the parity sweep.

## Execution Backlog

## Detailed Progress Log

### 2026-03-13 — Explicit Rust/FFI backend sweep completed
- Revalidated the explicit Rust tree-sitter-backed shared-comment-capability slice (`spec/rbs/merge/file_analysis_spec.rb:1332`) and the explicit Rust reproducible merge slice (`spec/integration/reproducible_merge_spec.rb:185`) under `KETTLE_RB_DEV=/home/pboling/src/kettle-rb`; both are green.
- Revalidated the aggregate split-suite flow with `bundle exec rake magic`, confirming both the FFI-tagged partition and the remaining-spec partition are green under sibling workspace mode.
- Rechecked the explicit FFI mirrors (`spec/rbs/merge/file_analysis_spec.rb:1378`, `spec/integration/reproducible_merge_spec.rb:195`) through the isolated `bin/rspec-ffi` runner; both are green once MRI is kept unloaded, so the earlier pending results were a runner-isolation issue rather than a comment-parity gap.

### 2026-03-12 — Backend and wrapper parity
- 2026-03-12: Slice 3 explicit-backend and alias parity coverage advanced.
- Probed exact top-level `class_alias` / `module_alias` wrapper line/text extraction directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and available tree-sitter-backed backends already agreed on exact wrapper lines and exact source slices without trailing same-line comments.
- Added focused `file_analysis_spec` coverage for exact top-level alias wrapper location/text parity and extended explicit tree-sitter-backed contexts with shared comment capability coverage, then promoted matched alias-declaration doc preservation into both `smart_merger_spec` and a reproducible integration fixture.
- Revalidation target: focused file-analysis, smart-merger, and reproducible integration runs across the supported sibling-only backend split suite.

### 2026-03-12 — Recursive merge and nested comment parity
- 2026-03-12: Slice 3 recursive member merge parity advanced.
- Taught `Rbs::Merge::SmartMerger` to recursively merge matched container members by nested signature/order instead of selecting a whole declaration, preserving destination-only members while applying template-preferred shared and template-only members.
- Added focused `smart_merger_spec` coverage for recursive matched-container member merging and revalidated focused, broader, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 overload-aware recursive member parity advanced.
- Taught `Rbs::Merge::SmartMerger` to align method overloads inside matched containers by callable shape instead of only method name/order, while preserving destination-relative member ordering for matched and destination-only members.
- Added focused `smart_merger_spec` coverage for reordered overloads plus a reproducible integration fixture, then revalidated focused integration, broader subset, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 nested member comment preservation advanced.
- Taught `Rbs::Merge::SmartMerger` to preserve leading comment lines when recursively emitting matched, destination-only, and template-only nested members, reusing the existing preferred leading-region logic inside the recursive member path.
- Added focused `smart_merger_spec` coverage for template-preferred documented matched members plus a reproducible integration fixture, then revalidated focused smart-merger, focused integration, broader subset, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 empty preferred-container recursive parity advanced.
- Taught `Rbs::Merge::ConflictResolver` and `Rbs::Merge::SmartMerger` to recursively preserve one-sided nested members inside a matched container even when the preferred declaration shell is empty.
- Added focused `smart_merger_spec` coverage for template-preferred empty-container preservation, then revalidated focused smart-merger, broader subset, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 recursive template-only member parity coverage advanced.
- Probed the remaining one-sided recursive template-only member cases directly against the local sibling `ast-merge` / `tree_haver` code path, confirming correct behavior for empty matched destination shells, non-empty destination-owned member lists, `add_template_only_nodes` gating, and nested template-owned member docs.
- Added focused `smart_merger_spec` regressions to lock in those behaviors across the auto, explicit RBS, and explicit MRI tree-sitter contexts, then revalidated focused smart-merger, broader subset, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 tree-sitter attribute member extraction parity advanced.
- Taught `Rbs::Merge::NodeTypeNormalizer` and `Rbs::Merge::NodeWrapper` to refine tree-sitter `attribute_member` nodes by their nested `attribyte_type`, restoring concrete `attr_reader` / `attr_writer` / `attr_accessor` member extraction instead of dropping those members entirely.
- Added focused `file_analysis_spec` coverage for nested attribute member extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 tree-sitter alias member extraction parity advanced.
- Taught `Rbs::Merge::NodeTypeNormalizer` to recognize tree-sitter `alias_member` nodes and extended `Rbs::Merge::NodeWrapper` to read alias names from the node's ordered `method_name` children, restoring alias member visibility and stable alias signatures across backends.
- Added focused `file_analysis_spec` coverage for nested alias member extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 tree-sitter variable member extraction parity advanced.
- Taught `Rbs::Merge::NodeTypeNormalizer` to refine tree-sitter `ivar_member` nodes into `:ivar`, `:civar`, or `:cvar` based on child shape and extended `Rbs::Merge::NodeWrapper` name extraction to recognize `ivar_name` / `cvar_name`, restoring stable variable-member names and signatures across backends.
- Added focused `file_analysis_spec` coverage for nested `@ivar`, `self.@civar`, and `@@cvar` extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 tree-sitter singleton method kind parity advanced.
- Taught `Rbs::Merge::NodeWrapper#method_kind` to detect tree-sitter singleton methods from a nested `self` child instead of relying on the raw node type string, restoring stable singleton-vs-instance method signatures across backends.
- Added focused `file_analysis_spec` coverage for nested singleton method kind extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 visibility member extraction parity advanced.
- Taught `Rbs::Merge::NodeWrapper` to expose stable `public` / `private` visibility names, `visibility_kind`, and `[:visibility, kind]` signatures across the native RBS and tree-sitter-backed backends instead of falling back to unknown line-based signatures.
- Added focused `file_analysis_spec` coverage for nested visibility member extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 mixin member extraction parity coverage advanced.
- Probed tree-sitter `include` / `extend` / `prepend` member extraction directly against the local sibling `ast-merge` / `tree_haver` code path, confirming generic include targets and mixin signatures were already parity-correct across the native RBS and tree-sitter-backed backends.
- Added focused `file_analysis_spec` coverage for nested mixin member extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 declaration-alias extraction parity advanced.
- Taught `Rbs::Merge::NodeTypeNormalizer`, `Rbs::Merge::NodeWrapper`, and `Rbs::Merge::FileAnalysis` to recognize tree-sitter `class_alias_decl` / `module_alias_decl` nodes and to expose stable `[:class_alias, name]` / `[:module_alias, name]` signatures across both the native RBS and tree-sitter-backed backends instead of dropping those declarations or falling back to unknown signatures.
- Added focused `file_analysis_spec` coverage for alias declaration extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact type_alias declaration parity coverage advanced.
- Probed exact top-level `type_alias` extraction and signature generation directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on type-alias names and `[:type_alias, name]` signatures.
- Added focused `file_analysis_spec` coverage for exact top-level type-alias declaration extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact constant declaration parity coverage advanced.
- Probed exact top-level `constant` extraction and signature generation directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on constant names and `[:constant, name]` signatures.
- Added focused `file_analysis_spec` coverage for exact top-level constant declaration extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact global declaration parity coverage advanced.
- Probed exact top-level `global` extraction and signature generation directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on global names and `[:global, name]` signatures.
- Added focused `file_analysis_spec` coverage for exact top-level global declaration extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact interface declaration parity coverage advanced.
- Probed exact top-level `interface` extraction and signature generation directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on interface names and `[:interface, name]` signatures.
- Added focused `file_analysis_spec` coverage for exact top-level interface declaration extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact module declaration parity coverage advanced.
- Probed exact top-level `module` extraction and signature generation directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on module names and `[:module, name]` signatures.
- Added focused `file_analysis_spec` coverage for exact top-level module declaration extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact class declaration parity coverage advanced.
- Probed exact top-level `class` extraction and signature generation directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on class names and `[:class, name]` signatures.
- Added focused `file_analysis_spec` coverage for exact top-level class declaration extraction across the RBS backend and tree-sitter-backed contexts, then revalidated focused file-analysis, broader subset, and full `rbs-merge` suite coverage against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact class/module wrapper location-text parity coverage advanced.
- Fixed `bin/rspec-ffi` to load `spec_thin_helper` before `spec_ffi_helper`, restoring the isolated FFI suite's ability to boot and execute against the local sibling `ast-merge` / `tree_haver` code instead of crashing before examples ran.
- Taught `Rbs::Merge::NodeWrapper#text` to prefer exact parser source spans over line-based reconstruction, eliminating same-line trailing-comment overreach for declaration wrappers across the native RBS and tree-sitter-backed backends.
- Probed exact top-level `class` and `module` wrapper line/text extraction directly against the local sibling `ast-merge` / `tree_haver` code path, confirming both backends now agree on exact wrapper lines and exact source slices without trailing same-line comments.
- Added focused `file_analysis_spec` coverage for exact top-level class and module wrapper location/text parity across the RBS backend and tree-sitter-backed contexts, then revalidated the isolated FFI suite, the remaining non-FFI suite, and the aggregate split-suite `rake magic` flow against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact interface wrapper location-text parity coverage advanced.
- Probed exact top-level `interface` wrapper line/text extraction directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on exact wrapper lines and exact source slices without trailing same-line comments.
- Added focused `file_analysis_spec` coverage for exact top-level interface wrapper location/text parity across the RBS backend and tree-sitter-backed contexts, then revalidated the split file-analysis runs plus the isolated FFI suite, the remaining non-FFI suite, and the aggregate split-suite `rake magic` flow against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact type_alias wrapper location-text parity coverage advanced.
- Probed exact top-level `type_alias` wrapper line/text extraction directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on exact wrapper lines and exact source slices without trailing same-line comments.
- Added focused `file_analysis_spec` coverage for exact top-level type-alias wrapper location/text parity across the RBS backend and tree-sitter-backed contexts, then revalidated the split file-analysis runs plus the isolated FFI suite, the remaining non-FFI suite, and the aggregate split-suite `rake magic` flow against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact constant wrapper location-text parity coverage advanced.
- Probed exact top-level `constant` wrapper line/text extraction directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on exact wrapper lines and exact source slices without trailing same-line comments.
- Added focused `file_analysis_spec` coverage for exact top-level constant wrapper location/text parity across the RBS backend and tree-sitter-backed contexts, then revalidated the split file-analysis runs plus the isolated FFI suite, the remaining non-FFI suite, and the aggregate split-suite `rake magic` flow against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 exact global wrapper location-text parity coverage advanced.
- Probed exact top-level `global` wrapper line/text extraction directly against the local sibling `ast-merge` / `tree_haver` code path, confirming the native RBS and tree-sitter-backed backends already agreed on exact wrapper lines and exact source slices without trailing same-line comments.
- Added focused `file_analysis_spec` coverage for exact top-level global wrapper location/text parity across the RBS backend and tree-sitter-backed contexts, then revalidated the split file-analysis runs plus the isolated FFI suite, the remaining non-FFI suite, and the aggregate split-suite `rake magic` flow against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 3 nested member extraction parity advanced.
- Fixed `Rbs::Merge::NodeWrapper` tree-sitter member extraction to unwrap `members` / `interface_members` containers and `member` / `interface_member` wrappers, restoring nested overloaded member visibility for class/module/interface declarations.
- Added focused `file_analysis_spec` coverage proving overloaded nested member extraction parity across the RBS backend and tree-sitter backend contexts, then revalidated focused, broader, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.

### 2026-03-12 — Boundary and adjacent-declaration fixture parity
- 2026-03-12: Slice 3 boundary + adjacent declaration fixture parity advanced.
- Taught `Rbs::Merge::SmartMerger` to emit root preamble/postlude comment regions so comment-only destinations and removed-declaration comment promotion remain stable and idempotent across repeated merges.
- Added focused `smart_merger_spec` coverage for destination postlude and comment-only files, plus adjacent non-first declaration regressions for template-preferred fallback and removed-declaration promotion.
- Added reproducible fixtures for adjacent declaration doc preservation and adjacent removed-declaration comment promotion, then revalidated focused, broader, and full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.

### 2026-03-12 — Declaration-level comment behavior
- 2026-03-12: Slice 2 removed-declaration preservation completed.
- Added `remove_template_missing_nodes` plumbing to `Rbs::Merge::SmartMerger` and promoted leading comments for removed destination-only declarations instead of keeping the removed declaration bodies, while preserving surrounding blank-line separation.
- Added focused `smart_merger_spec` regressions for removed documented declarations across backends and revalidated focused/backend/full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.
- 2026-03-12: Slice 1 declaration-leading merge-path fallback completed.
- Taught `Rbs::Merge::MergeResult`, `SmartMerger`, and `ConflictResolver` to treat declaration-leading shared comment attachments as part of matched template-preferred output and declaration identity, so destination docs are preserved only when the template lacks them while template-owned docs still win when present.
- Added focused `smart_merger_spec` coverage for template-preferred declaration-leading comment fallback across backends, aligned the shared `file_analysis_spec` expectation with declaration ownership instead of duplicated preamble ownership, and revalidated focused/backend/full `rbs-merge` suites against the local sibling `ast-merge` / `tree_haver` code.

### 2026-03-11 — Slice 1 kickoff
- 2026-03-11: Phase 2 / Slice 1 started.
- Added `Rbs::Merge::CommentTracker` and wired shared comment capability plumbing in `Rbs::Merge::FileAnalysis` (`comment_capability`, `comment_nodes`, `comment_node_at`, `comment_region_for_range`, `comment_attachment_for`, `comment_augmenter`).
- Implemented conservative declaration-level leading-comment ownership with document prelude/postlude regions using the current sibling `ast-merge` comment classes.
- Added focused `file_analysis_spec` coverage for shared comment node exposure, declaration-leading attachment fallback, and prelude/postlude region behavior.
- Validated focused spec locations for auto and explicit backend contexts.
- Existing merge-path behavior only partially benefits from backend-native declaration comments; shared matched-node fallback, postlude/comment-only parity, and explicit regression coverage are still pending.

### Slice 1 — Shared capability + declaration-leading comments
- Add `comment_capability`, `comment_augmenter`, and normalized attachments to file analysis and node wrappers.
- Preserve document prelude/postlude comments and declaration-leading comments for the primary backend.
- Add focused specs for class/module/interface declarations first.

### Slice 2 — Matched and removed declaration behavior
- Preserve destination comments when matched template-preferred declarations win.
- Preserve comments for removed destination-only declarations when removal is enabled.
- Add conflict-resolver and smart-merger regressions for declaration-level ownership.

### Slice 3 — Backend parity + deeper member coverage
- Expand to nested members, overloads, and backend parity once declaration-level ownership is stable.
- Add reproducible fixtures for representative typed API files.
- Keep fallback behavior explicit where one backend lacks native comment support.

## Dependencies / Resume Notes
- Start in `lib/rbs/merge/file_analysis.rb` and `lib/rbs/merge/node_wrapper.rb`.
- Treat declaration-level comments as the first win; do not start with member-level edge cases.
- Reuse `psych-merge` for shared behavior concepts only.

## Exit Gate For This Plan
- Declaration-level comments survive common merges across the supported backend path.
- Backend differences are normalized enough that focused and reproducible tests stay stable.
