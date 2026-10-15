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
- Runtime worker: return void for null boxed Array push, unshift, and insert
  receivers before reading fields. Preserve typed Array error contracts.
- Orchestrator: reject explicit empty output and out-dir values through the
  existing missing-value diagnostic, and preserve compiler warnings with path
  spaces and unfamiliar diagnostic text in the fixture harness.

Gary's latest decision preserves void for boxed Array absence, including null
push, unshift, and insert receivers. This supersedes the earlier bad-arg
decision. Correct family-specific documentation and focused tests; preserve
typed Array exceptions and unrelated void-element, allocation, and size errors.

Additional retained findings use the same selected baseline:

- Runtime worker, after Array work: preserve function-local record, typedef,
  and enum identity through lambda capture cells and lifted functions.
- Cache worker, after cache work: repair REPL truth conversion for empty
  Strings and zero Symbols, and pointer increments/compound updates through
  the existing pointer-step operation. Add native/REPL parity coverage.
- Native macro references to file-private statics reproduce the reported
  mismatch. Gary closed this finding as outside supported behavior:
  intermixing #define with x2c is best effort, and CPP beyond #include is
  discouraged. The book states this boundary; no macro-binding repair is
  commissioned.
- Orchestrator: normalize local install directories before deriving names,
  and correct and execute the guide's acquired-value $auto example.

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

Focused evidence before final publication validation:

- Compiler worker: 38 fixtures passed; PCRE2 20 tests/118 assertions;
  SQLite 15 tests/133 assertions; libcurl consumer compiled and linked.
  Orchestrator probes confirm static redeclaration and same-scope external
  declarations link, and separate static storage now prints 0 instead of 9.
- Array worker: 52 Array/typed Array tests, 563 assertions, pass under the
  latest boxed-null sentinel decision.
- Cache worker: complete meta-cache harness passes, including archive
  replacement, explicit/environment meta compiler identity, executable hits,
  and retained translation/object reuse.
- Nine alternating paired warm library-script runs, after three warmups,
  have medians 0.015352 seconds before repair and 0.080126 seconds after
  repair. This is elapsed time for one unchanged script using -L/-lvalue,
  including conservative relinking; it is not a full-build measurement.
- REPL worker: full command tests and 14 native/REPL parity cases pass.
- Lambda worker: 63 lambda, enum, and function-rewrite fixtures pass. The
  local-type fixture covers nested definitions, anonymous members, escaped
  cells, public-inline headers, and original source-rule input. Independent
  final review confirms traversal order and existing writer/cell ownership.
- Orchestrator: complete CLI boundary and scratch-home package-install
  harnesses pass; the original guide example exits 139 and its corrected
  replacement exits 0.

Do not reopen extreme-integer slices, the synthetic failed-compiler/object-cache
experiment, or expand into vulnerability auditing or a hardening campaign.
No recurring gate, framework, or validation requirement is added.

## Plan review

Resolved bindings, established linkage, and selected dependency files remain
producer-owned facts. Consumers preserve those facts rather than adding a
parallel registry or linker search implementation. Existing typed Array errors,
boxed absence sentinels, and option diagnostics own the public boundaries.
File prefixes encode the
file/local-name boundary without restricting legal source identifiers.
Per-declarator projections retain source order and shared definitions.
Focused negative cases protect typed null-argument errors and CLI behavior,
existing invalid linkage order, and warnings that the harness must not erase.
The implementation review will remove duplicated checks and unnecessary helpers
before the existing publication proof.

The completed authored diff has been reviewed. Local type lifting reuses
binding facts, native aliases, declaration order, and the existing builtin
writer context. It adds no public meta SDK operation, persistent registry,
validation framework, or new gate. The final combined publication proof and
performance checkpoint remain pending.
