> Status: active
> Implementation starts from origin/dev 53061627eaf5ecc4b45525a536b8c02b0d10ae67.
> The prior review baseline was 8bfeb6a79e94f9ac12c7dbec4a88bd01dbd79098.

# Engineering review repairs

Implement the retained engineering findings with focused regression coverage.
Delivery is one orchestrator-owned, validated batch to dev. Do not advance main.

## Ownership and decisions

- Compiler worker: retained package method bindings, unambiguous file-private
  prefixes, per-binding linkage and header visibility, and macro external
  declaration identity. Shared compiler owners are repaired in sequence.
- Cache worker: reuse ordinary translation fingerprints for scripts; decline
  executable reuse when selected user or package libraries are unrecorded.
  Preserve translation and object reuse and measure warm relinking cost.
- Runtime worker: reject null boxed Array push, unshift, and insert receivers
  through the existing bad-arg owner before reading fields.
- Orchestrator: reject explicit empty output and out-dir values through the
  existing missing-value diagnostic, and preserve compiler warnings with path
  spaces and unfamiliar diagnostic text in the fixture harness.

Gary confirmed that boxed take_last, shift, remove, and invalid-index insert
preserve void sentinels. Correct family-specific documentation to distinguish
that behavior from typed Array exceptions.

## Verification and delivery

Reproduce each retained defect at the selected baseline before repair. Use
isolated worker worktrees with worker/private context and private commits.
Workers run focused checks; the orchestrator reviews their evidence and the
complete authored diff, integrates current dev, regenerates final artifacts,
and runs the existing performance checkpoint and agent-pr-check gate.

Compiler acceptance includes dependency-free generated Cleanup through $auto,
PCRE2 and SQLite tests, a libcurl consumer, separate tentative static storage,
ordinary generated-looking source names, C-compatible linkage redeclarations,
mixed public/private headers, and same-scope macro external declarations.
Cache acceptance includes archive replacement, explicit/environment meta-cc
changes, unchanged script executable reuse, and warm library-run measurements.
Runtime and CLI acceptance cover the named public operations and exact option
forms through their existing suites and harnesses.

Do not reopen extreme-integer slices, the synthetic failed-compiler/object-cache
experiment, or expand into vulnerability auditing or a hardening campaign.
No recurring gate, framework, or validation requirement is added.

## Plan review

Resolved bindings, established linkage, and selected dependency files remain
producer-owned facts. Consumers preserve those facts rather than adding a
parallel registry or linker search implementation. Existing error and option
diagnostics own the deliberate public boundaries. File prefixes encode the
file/local-name boundary without restricting legal source identifiers.
Per-declarator projections retain source order and shared definitions.
Focused negative cases protect documented null-argument and CLI behavior,
existing invalid linkage order, and warnings that the harness must not erase.
The implementation review will remove duplicated checks and unnecessary helpers
before the existing publication proof.
