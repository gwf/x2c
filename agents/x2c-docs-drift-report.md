# X2C Documentation Drift Report

> Status: active (2026-07-19) - canonical entry points, examples, contracts,
> diagnostics, architecture, debugging, and organization are reconciled.

## Mechanically checked surface

`make doc-check` currently verifies:

- the generated module catalog matches live `src/*.x` and `lib/*.x` modules;
- the generated library reference matches the runtime sources and every row of
  `docs/library-manifest.txt`;
- every page under `docs/src/` is reachable from `docs/src/SUMMARY.md`, and
  every SUMMARY entry names a file that exists;
- no document spells the project name as the drug it is pronounced like;
- local Markdown links resolve across README and active top-level docs;
- repository paths in the canonical entry-point set resolve;
- compiler flags named by active docs exist in `src/cli.x`;
- canonical workflow docs do not reintroduce unsupported `V=1`, missing
  `OVERVIEW.md`, or bootstrap redirection before creating `debug/`;
- example compile commands use quote-only runtime-header lookup so generated
  headers do not shadow system headers;
- every example cited by the language/library guides is either executable in
  the manifest harness or labeled with its non-checked manifest category;
- every stated compiler or runtime module count matches `src/*.x` or
  `lib/*.x`, and the `src/` module lists in `AGENTS.md` and
  `docs/src/internals/architecture.md` name exactly those modules;
- every section under "Partial contracts and open decisions" in
  `agents/x2c-philosophy.md` names a ledger row that is not yet verified.

The path-audited entry-point set is declared in `tools/check-docs.py`. Its 17
entries are README, the root and `agents/` agent guidance, the philosophy,
quick start, development guide, code-organization guide, debugging guide,
module catalog, this report, the canonical diagnostics guide, and six book
chapters: architecture, the CLI reference, the language reference, idioms, the
implementation map, and the library overview.

The Array/Map empty-value correction is now consistent across the philosophy,
quick start, development guide, language reference, and library guide. Each
describes empty mutable containers as allocated objects and reserves raw null
container pointers for internal absence or pending initialization, not empty
values. The mutable-empty compiler fixture owns the executable boundary.

The exception guides now agree that generated `try` owns optimized
`sigsetjmp(env, 0)`/`siglongjmp` state preservation. The compiler fixture
harness applies
the active build flags to native artifacts, keeping that documentation tied to
optimized executable evidence.

Initialization is now described through one type-owned lifecycle method per
translation unit. Exact fixtures own the generated guard, cache ordering,
signature rejection, duplicate-owner rejection, and legacy `@init` error; the
examples surface contains a checked runnable showcase. Non-static functions
own lazy entry; static helpers trust that boundary instead of repeating its
guard. Plain-C Scope probes separately prove pre-aggregator entry,
uninitialized shutdown, and the terminal state after a repeated initializer
call.

The architecture and code-organization guides now name the
consolidated compiler, current runtime owners, real build stages, and current
benchmark/test surfaces. The debugging guide already matched the verified
diagnostic and failure-capture workflow. Obsolete split-module maps and the
unsupported `V=1` workflow have been removed.

The preprocessor contract now agrees across architecture, language,
debugging, philosophy, and fixture-status surfaces. Host preprocessing is an
argv-safe, status-bearing discovery pass; the original positioned token stream
owns full parsing, diagnostics, and emission. Checked process probes cover
hostile paths and exact failure status, while compiler fixtures cover missing
includes and directive retention inside compound statements.

The scalar contract now agrees across philosophy, language routing, the
reference, the generated module catalog, and continuation status. One Type
owner supplies declaration normalization, literal source families, arithmetic
properties, and Var tags. Exact fixtures prove valid alternate spellings,
invalid combinations, overflow diagnostics, generated boxing, scalar typedef
crossings, and native behavior. VarOps now separately owns complete cross-tag
numeric conversion without broadening nonnumeric conversion.

The AST-construction guide now distinguishes parsed and transformed shapes.
Array and Map literal documentation follows the implemented owner boundary:
parsing preserves raw source-ordered children, transformation owns `Var`
crossings, and downstream cache/emission code consumes the normalized order.
The literal/cache fixture proves both phase representations and runtime order.

Index/slice guidance is tied to an exact five-artifact fixture. It
distinguishes native indexing from collection helpers, proves raw Map keys at
parse time and transform-owned boxing, and checks single evaluation through
runtime counters. The former redundant collection-assignment expression
wrapper is gone without changing generated C or runtime behavior.

Var comparison guidance now distinguishes value equality, representation
identity, and total ordering at both source and runtime boundaries. One exact
fixture proves all eight operators, native controls, both mixed operand
directions, wide-box equality versus identity, object identity/order, and
single evaluation. A second exact fixture proves that direct and chained
file-scope aliases of `Var` use the same boxing, extraction, call, return, and
comparison crossings while preserving their source declarations. The language
reference and implementation map also state the corresponding scope rule:
typedef declarations inside compound statements are rejected.

Var numeric guidance now agrees across the philosophy, quick start, language
reference, idioms, library guide, generated catalog, test status, and
continuation record. `lib/var.x` owns structural validation and exact integer
comparison mechanics; `lib/varconvert.x` owns all 15 numeric conversion
families and failure policy; `lib/common.x` declares the shared Symbol outcome
ABI; `lib/varops.x` owns binary arithmetic, truthiness, and typed compound
updates; dispatch retains comparison policy. Integer lanes never use a
floating intermediary. Exact runtime and compiler fixtures prove promotion,
narrowing, every native conversion target, wide precision, short-circuit
behavior, typed adapter selection, single lvalue evaluation, failure
atomicity, and fail-fast `void` truthiness. Five exact diagnostics reject a
statically nonnumeric operand, dynamic unary arithmetic, and helper-backed,
enum, and bit-field compound targets. The `numeric-string-interpolation`
showcase checks numeric-to-String interpolation against exact expected
output.

## Executable examples surface

`examples/manifest.txt` classifies all 39 example sources: 27 showcase, 7
probe, 3 external-input, and 2 legacy. `make examples` currently runs the 30
sources marked `check=run` (25 of them against exact expected output; the
other 5 declare `-` and must exit zero printing nothing) and build-checks the
three external-input programs. Probes and legacy sources remain visible in the
manifest but do not claim supported behavior.

The first audit of the former 11-file documentation-example directory was
wrong. It treated the absence of `main` as proof that a teaching module was
unusable and reported that none of the sources was usable. In fact, the Symbol
module translated and compiled correctly, while the interpolation and
conversion modules also compiled and exposed current defects when called.
Deleting the directory without first preserving that evidence was a mistake.

The directory remains retired because it mixed valid modules with stale APIs,
placeholders, incorrect syntax, and broad unsupported claims. Its useful
evidence is now preserved in the manifest surface:

| Former source | Disposition |
| --- | --- |
| `symbol-literals.x` | Incorporated into the checked Symbol showcase. |
| `string-interpolation.x` | Replaced by the checked interpolation showcase. |
| `type-conversions.x` | Replaced by the checked conversion-matrix showcase. |
| `init-decorator.x` | Replaced by the checked type-initializer showcase. |
| `foreach.x` | Retired; checked foreach example and fixture own the feature. |
| `percent-literals.x` | Retired; used unsupported insertion positions. |
| `lambda-map.x` | Retired; existing lambda evidence owns it. |
| `defer-cleanup.x` | Retired; defer tests own the feature; APIs were stale. |
| `pattern-matching.x` | Retired; its binder API was invented. |
| `base-types-interop.x` | Retired; universal nonnumeric claims were false. |
| `idioms-showcase.x` | Retired; splice failure was extracted. |

## Current authoritative entry points

- `README.md` routes readers without duplicating a language manual.
- `agents/x2c-philosophy.md` owns principles and contract status.
- `agents/quick-start.md` owns the shortest verified build/test path.
- `agents/x2c-development-guide.md` owns less common compiler and build facts;
  the root `AGENTS.md` owns workflow, validation, and publication.
- `agents/x2c-module-catalog.md` is generated from the live module tree.
- `docs/src/reference/language.md` owns implemented syntax and explicit
  limitations.
- `docs/src/guide/idioms.md` owns verified recommended patterns.
- `docs/src/internals/implementation-map.md` owns feature routing across the
  compiler/runtime boundary.
- `docs/src/library/overview.md` owns runtime relationships and contracts.
- `agents/logger-and-diagnostics-guide.md` owns Logger and compiler diagnostic
  contracts.
- `AGENTS.md` and `agents/AGENTS.md` own agent safety and evidence rules;
  `docs/AGENTS.md` owns the book's authoring rules.

The `docs/` entries above are chapters of the mdBook whose spine is
`docs/src/SUMMARY.md`.

## Remaining staged audit

- Fragmentary code blocks in the coding-style guide need explicit
  illustrative/pseudo labels before a
  future audit can require all claimed standalone examples to compile.

## Repair order

1. Keep the checked entry points, language guides, examples, and generated
   catalog green.
2. Reconcile the remaining coding-style examples with live idioms.

Do not call the entire documentation set verified merely because
`make doc-check` passes. The command states its exact coverage, and this
report keeps the remaining families explicit.
