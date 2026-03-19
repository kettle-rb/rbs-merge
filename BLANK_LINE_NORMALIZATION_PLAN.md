# Blank Line Normalization Plan for `rbs-merge`

_Date: 2026-03-19_

## Role in the family refactor

`rbs-merge` is the declaration/doc-comment adopter for the shared blank-line normalization effort.

Its main responsibility is to align declaration-adjacent spacing, promoted comment/doc behavior, and removal-mode separator handling with the shared family contract while keeping format-specific inline-comment limitations explicit.

## Current evidence files

Implementation files:

- `lib/rbs/merge/smart_merger.rb`
- `lib/rbs/merge/file_aligner.rb`
- related files under `lib/rbs/merge/`

Relevant specs:

- `spec/rbs/merge/file_aligner_spec.rb`
- `spec/rbs/merge/smart_merger_spec.rb`
- `spec/rbs/merge/removal_mode_compliance_spec.rb`
- `spec/integration/reproducible_merge_spec.rb`

## Current pressure points

Spacing matters around:

- declaration-leading docs/comments
- promoted removed-declaration docs
- separator blank lines between declarations after removal or reordering
- destination-relative ordering stability

## Migration targets

- adopt shared blank-line/layout handling for declaration boundaries
- keep format-specific inline-comment N/A cases explicit
- preserve current ordering and freeze/protection behavior while removing repo-local spacing folklore where possible

## Workstreams

- map current declaration-boundary blank-line rules
- migrate promoted-comment separator behavior first
- align repeated-merge idempotence expectations with the shared layout contract
- document any RBS-specific non-applicable cases explicitly rather than encoding them as ad hoc exceptions

## Exit criteria

- declaration/doc-comment spacing follows shared layout behavior where applicable
- destination-ordering regressions stay covered
- non-applicable inline-comment semantics remain explicit and documented
