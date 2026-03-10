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

## Execution Backlog

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
