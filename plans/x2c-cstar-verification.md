> Status: active
> Reviewed and corrected against source and upstream on 2026-09-09.
> Milestone 1 (feasibility) executed the same day; results are recorded
> under "Milestone 1 results". Gary accepted proceeding without a known
> license for the closed C* core. Milestones 2-5 remain unstarted.

# C* verification for x2c

## Intended result and difficulty

Let an x2c programmer annotate selected functions with contracts, loop
invariants, and calls to proof helpers. A separate command checks those
functions and reports remaining obligations at source locations. Proof
helpers are ordinary x2c programs using C*'s proof API. Deployment contains
the implementation without proof execution.

Recommend an experimental package for a small C-like subset, not a new x2c
type system or a verifier for the entire runtime. Budget roughly
**8-14 engineer-weeks** for a useful pilot, including proof examples and
integration. This is engineering judgment, not a measured schedule; assume
an engineer comfortable with x2c/compiler work and access to someone
experienced with HOL and separation logic. Neither estimate includes broad
language coverage, an editor extension, or production assurance.

The macros are a relatively small part. The difficult work is faithful
translation of program effects, useful reusable proofs, native/backend
integration, and making a successful report mean exactly what it claims.

## Evidence and backend choice

The [paper](https://arxiv.org/abs/2504.02246) ("C*: Unifying Programming
and Verification in C") motivates interleaving symbolic execution with
executable proof procedures. Its manual prototype is not the current
implementation baseline.

The [C* runtime documentation][runtime] exposes symbolic-state get/set
operations, the `make_*` AST-builder API that `cstarc` emits, and a final
report rendered by `cst_print_vc` with `verification_conditions`, `axioms`,
and `strategies` arrays. SMT results and loaded strategies are recorded as
explicit trust obligations ([SMT tutorial][smt]). The
[header provenance][provenance] records `cstarc 0.5.7`, synced 2026-09-08,
and seven headers; it records no hashes. The pinned artifact is the
`v0.5.7` `darwin-aarch64` release tarball (sha256 in "Milestone 1 results").
Do not track a floating latest release.

Reuse its engine, HOL Light server, C API, and applicable proof library. Do
not implement a symbolic executor, theorem kernel, SMT integration, or HOL
parser in x2c. `cst_feed_program_segment_with_loc` (`symexec.h`) is the
intended integration point; generated x2c calls that surface directly rather
than translating x2c into C* source and adding another parser to the path.

Source availability: only `cstar_docs`, `cstar_examples`, `cstar_stdlib`,
and `cmc` are public (MIT). The core toolchain (`cstarc`, the engine,
`hol_light_server`) is closed, and the release ships no LICENSE file.
`packages/LICENSE-POLICY.md` rejects unclear terms by default; Gary made the
explicit project decision on 2026-09-09 to proceed anyway. Record that
decision in the package notices when the package exists.

Relevant current x2c facts, verified by probe on 2026-09-09:

- [Function decorators](../docs/src/guide/macros.md#decorators-transform-one-target)
  capture the typed function and preserve its signature. Statement
  decorators exist, and a decorator returning `{ $target }` works as an
  unbraced loop body. An empty production is rejected as a loop body, so an
  erased marker becomes `;`.
- [Macro-visible syntax](../docs/src/reference/language.md#macro-visible-syntax)
  is the canonical typed List AST. x2c does not reject an undeclared
  identifier in an expression hole; it reaches C. Proof helper names are
  checked when the generated proof program is compiled.
- `Compiler.macro_lisp`, `Lisp.try_get`, and `ParsedUnit` expose the
  session until `ParsedUnit.close`. A Statement macro can accumulate a Lisp
  global across expansions in source order, and a host tool built against
  `libx2c-dev.a` reads it and exports it through `unit.context.export`
  before closing. `x2c.invocation.file/.line/.column` supply locations.
- `ParsedUnit.ast` is post-macro and pre-transform. `Compiler.transform`
  and `generate.x` later lower `defer`, lambdas, and printf/Var forms;
  `foreach` is already a `while` over `Iter_try_next` at parse time. The
  compiler never renames user locals; the only expected differences between
  a captured body and the final one are `(at ID NODE)` wrappers, erased
  markers, and the invariant decorator's brace wrapper.
- A non-`static` prototype after `#pragma private` keeps C linkage, stays
  out of the header, and an undefined call fails at link.
- x2c parses included C headers itself, and `hol_prover_client.h` contains
  a C++ `constexpr` region x2c cannot parse. The package therefore declares
  its pinned C surface in a shim header (the pcre2 pattern), never including
  the upstream headers into x2c units. `range` collides with an x2c name and
  must be renamed in the shim.

## First supported contract

The pilot establishes partial correctness and the backend's safety
obligations for each explicitly selected function, under its precondition,
the admitted target model, and the recorded trusted components. It does not
prove termination or the correctness of arbitrary callers or an entire
executable.

| Area | Pilot scope |
| --- | --- |
| Target | macOS arm64 (tested); 8-bit bytes, 32-bit int, 64-bit pointers, little endian |
| Values | `void`, signed/unsigned int, unsigned char, pointers to admitted scalar types |
| Expressions | Constants, locals/parameters, explicit scalar arithmetic and comparisons, scalar conversions, address/dereference and bounded array indexing |
| Statements | Declarations, assignment, blocks, `if/else`, `while`, early return |
| Calls | Direct calls within the selected, acyclic set of functions, each with a checked contract and body |
| Proofs | Preconditions/postconditions, loop invariants, intermediate assertions, named x2c proof helpers with logical arguments |

Reject an unsupported operation at the verification translation boundary.
There is no rule that treats an unknown call or AST form as having no effect.
Initially exclude structs/unions, floating point, function pointers,
recursion, variadics, volatile/atomics, concurrency, allocation, pointer-int
casts, inline assembly, `goto`, `break/continue`, and runtime-managed values.
Also exclude `defer`, Scope/Context operations, Error/exception transfers,
lambdas, protocols, container literals, and operators requiring those
facilities inside verified implementations. Proof helpers may use ordinary
x2c facilities where their native lifetime obligations are satisfied.

Model integer promotions, narrowing, overflow obligations, alignment, and
pointer scaling explicitly using the already resolved x2c types. Reject
unsequenced side effects instead of inventing an evaluation order. Keep
pointer arithmetic within the specified live object. The upstream theory
uses integer addresses, and its [typed storage model][memory] has fixed
widths and little-endian byte order. Matching those facts to the host is
necessary; it is not a proof of all ISO C pointer semantics.

## Surface and staging

Proposed names describe new macros, not currently working APIs:

- `$cstar.verify(pre, post)` decorates a function. `pre` and `post` are
  String literals in the pinned backend's logical syntax; the shipped 0.5.7
  return-value name is `__return`.
- `$cstar.invariant(assertion)` decorates a `while` statement.
- `$cstar.assert(assertion);` records an intermediate logical assertion.
- `$cstar.proof(helper, logical_arguments...);` records a named proof helper
  with the helper as a `Name` hole and arguments as String literals. These
  are logical terms, never reads of live implementation variables.

Use the backend's quotation/term constructors behind a small `Cstar` package
surface; do not invent another assertion language. Resolve implementation
names to lexical bindings; parameter names in entry contracts denote entry
values, while program-point assertions use the current symbolic state. Keep
proof and implementation bindings separate.

Proof helpers live in companion `.x` files with a declared ordinary
interface receiving logical term arguments. They get the symbolic state,
produce a theorem, and submit the justified state change through the
backend API. A helper name is resolved when building the separate proof
program; a missing helper is an ordinary compile or link error there.

Inline arbitrary proof blocks are a later ergonomic extension.

## Architecture and ownership

1. **Collect through macros.** Inner annotations record their kind, logical
   text or helper name, and invocation location in the translation-unit
   Lisp session, and expand to calls of a declared marker carrying record
   IDs. The marker has package-private source visibility, external C
   linkage, and no definition. An invariant decorator returns one compound
   statement containing the marker and its loop. The function decorator
   records the annotated function in `cstar.records`, erases marker calls
   to `;`, and returns the remaining body.
2. **Read after successful parsing.** An optional `cstar-extract`
   executable follows x2c-graph's compiler-library pattern: `Frontend`,
   `Lisp.try_get` on `cstar.records`, export through the unit Context,
   close. The macros perform no file I/O or process launch. Ordinary
   compilation discards the in-memory records.
3. **Establish correspondence.** Require the verifying decorator to be
   outermost. Associate records with final parsed functions and compare the
   erased captured body with the final body modulo `(at ID NODE)` wrappers.
   Any other difference invalidates the record.
4. **Translate once into backend operations.** A package-owned traversal
   maps the admitted typed AST to the backend's `make_*` builders and
   `cst_feed_program_segment_with_loc`, dispatching on head symbols. Use
   existing Match and List operations; no new AST grammar.
5. **Generate and run proof code.** Emit a separate `.proof.x` unit that
   alternates segment submissions with helper calls, compile it through the
   ordinary x2c driver against the shim header, link `libcstar.a`,
   `libsac.dylib`, `libstdc++`, and the `cstarc --cl` library objects of the
   proof libraries it uses, and run it against an isolated prover session.
   The driver owns `hol_light_server` startup, its port, `CSTAR_HOME`,
   process status, a timeout, diagnostics, and report collection.
6. **Keep compilation ordinary.** Build implementation C with the existing
   x2c path. The implementation contains no marker calls, proof helpers, or
   linked verification runtime.

No new public compiler SDK or plugin ABI is required. The extractor uses
internal compiler APIs and is rebuilt with the exact x2c revision, as
x2c-graph is today. Keep it in the optional package build. `package.mk`
knows `src/`, `examples/`, and `tests/`; the extractor's home (extend
`package.mk` or `tools/`) is decided in milestone 2.

Records contain canonical Lists, Strings, and scalar values. Emit only
records reachable from successful final functions. Normalize occurrence IDs
into lexical order.

Do not cache verification initially. Each explicit verification runs in a
fresh directory and prover session. Record content hashes of inputs,
compiler/adapter/backend/proof-library identities, target options, proof
source, and resulting implementation C. A receipt describes that run, not a
permanent verified property of a filename.

## Verification result and trusted boundary

A successful process exit is insufficient. The driver requires all requested
functions to be processed, a complete final report, and empty
`verification_conditions`, `axioms`, and `strategies`. These arrays are not
a processed-function inventory: generated driver code records each expected
function's completion, and the outer driver matches that inventory against
the extraction request.

Report `verified`, `obligations remain`, `unsupported`, or `tool error` with
the affected function/location and backend detail. Timeout, crash, missing
report, or zero processed functions cannot count as verified. The runtime
blocks about 105 s before reporting a missing server; the driver needs its
own connect timeout.

Reuse backend theorem handles and state-setting checks. Handles are
`struct { void *inner; }` values owned by the server session; returned
strings are managed by the runtime's bundled Boehm GC. Values cannot
outlive the session. Do not assume x2c Context storage is a backend GC root.

Trusted components include HOL Light and its baseline theory, the symbolic
executor (`libsac`), the AST adapter, native proof runtime/reporting, x2c,
and the C toolchain. Process separation from the prover is not a defense
against arbitrary native proof code corrupting its in-process executor or
report.

## Implementation milestones

| Milestone | Deliverable and acceptance evidence | Effort |
| --- | --- | --- |
| 1. Feasibility | Pin usable C* libraries/headers; run one x2c theorem helper and scalar function through the engine; complete reports; extract/erase macro records with binding correspondence | done |
| 2. Annotation/extraction | Function contracts, assertion/invariant/proof markers, native extractor, locations, companion proof helper interface, deterministic output, unchanged ordinary function behavior | 5-10 days |
| 3. Scalar and pointer adapter | Declarations, arithmetic/conversions, branches, return, loads/stores and checked direct calls; bounded absolute value and pointer swap verify end to end | 10-15 days |
| 4. Loops and useful proofs | Array clearing with a loop invariant and x2c ownership-splitting helper; reused proofs for a second bounded buffer routine | 15-25 days |
| 5. Package delivery | Explicit verification command, isolated sessions, complete result handling, reproducible inputs, examples, dependency profile, notices, and book documentation | 5-10 days |

Suggested ownership:

- `packages/cstar/src/cstar.x` and `cstar-0.5.7.h`: small public
  proof/context operations and the pinned shim C surface.
- `packages/cstar/src/cstar.xmacro` and companion `.xlisp`: annotation
  templates, capture records, and erasure, with a declaration-only
  `cstar-annotations.x` supplying the marker.
- The extractor, one backend adapter, and the verification driver.
- `packages/cstar/examples/`, `tests/`, `README.md`, dependency profile
  and notices.

Keep backend tests explicit and optional. Do not enroll this package in
aggregate checks or change `precommit`, `sanity-check`, or `agent-pr-check`.

## Milestone 1 results (2026-09-09, macOS 15 arm64, Apple clang)

Artifact: `https://gitee.com/cstarlang/cstar_docs/releases/download/v0.5.7/cstar_darwin-aarch64.tar.xz`,
sha256 `f8fb646d20e9f59aa36f7cd39359acbeacb0f5fdbd4a4ce465112e432bcafd7f`,
71 MB. Contents used: `include/` (444 KB), `lib/libcstar.a` (9.9 MB,
bundles Boehm GC and the capnp client), `lib/libsac.dylib` (2.3 MB
universal), `bin/hol_light_server` (31 MB). `cstarc` (8.3 MB) is needed
only to build the proof libraries (`cstarc --cl`), which use `#require`
and backtick terms plain clang cannot compile. `cst_clang`/`cst_clangd`
(306 MB) are not needed.

Link line that works from `x2c build`:
`-L$R/lib -Wl,-force_load,$R/lib/libcstar.a -lsac -Wl,-rpath,$R/lib -lm
-lstdc++` plus the proof-library objects. `-pthread` is rejected by the
macOS linker through `-Xlinker`; it is unnecessary. The runtime reads
`CSTAR_HOME/include/common.strategies` at startup and `LCF_SERVER_PORT`
(default 7000). macOS Control Center also listens on `*:7000`; the server
binds `127.0.0.1:7000`, so readiness must be read from its log line, not a
port probe.

The x2c proof program (`abs.proof.x`, plain x2c against the shim header)
feeds `absolute` and `twice` through the builders, runs an x2c helper that
proves `n + n == n + n` with `int_arith_rule`, records completion per
function, and inspects the report:

| Measurement | Result |
| --- | --- |
| Cold `hol_light_server` start to listening | 13.9 s, 88 MB RSS |
| Warm theorem call from x2c (`int_arith_rule`) | 0.1-0.2 ms |
| Proof-program build (translate, compile, link) | 83 ms |
| Verify two scalar functions, warm server | 0.19 s total process |
| Upstream `cstarc verify` on the same tutorial | 0.4 s |

Acceptance behaviors observed:

- Both functions: report `{"verification_conditions":[],"axioms":[],"strategies":[]}`,
  `processed 2 of 2`, `RESULT: verified`, exit 0.
- `--stop-early` (second function abandoned after its first statement): the
  report is still empty, so the arrays alone would have passed; the
  inventory check prints `processed 1 of 2` and `RESULT: incomplete`, exit 2.
- `--unbounded` (precondition without the `INT_MIN` exclusion): one
  verification condition at the `-x` return, `fact (~(x__pre == --
  2147483648i))`, `RESULT: obligations remain`, exit 1.
- Server absent: `cannot connect to hol light server` after 105 s, exit 1.
- `CSTAR_HOME` unset: `fatal error: folder path ~/.cstar/include does not
  exist`, immediate.

Extraction (`packages/cstar/spike/extract/`): `$cstar.verify`,
`$cstar.invariant`, `$cstar.assert`, and `$cstar.proof` record into
`cstar.records` in source order; the function decorator erases every marker
call in Lisp, so the generated C never mentions the marker and differs from
the unannotated baseline only by `;` null statements. The extractor,
linked against the x2c-graph development archive, reads the records,
prints them with locations, and compares each recorded body with the body
in `unit.ast` modulo `(at ID NODE)`: both functions MATCH, and a variant
with an outer decorator that appends a statement is refused with exit 1
while still compiling and running correctly. Translation of the 42-line
file costs 45 ms annotated against 34 ms plain, a fixed Lisp session cost;
extraction takes 44 ms.

Facts learned for milestone 2: a Function decorator sees `(at ID NODE)`
wrappers, contrary to the language reference; `x2c.source.text` rejects
elements of a sequence hole, so literal arguments are read from the AST;
there is no `Literal` hole kind; the marker is matched by spelling, not
binding identity; marker positions inside a body are recoverable only if
the record also keeps the pre-erasure body.

Upstream facts corrected during the spike: there is no documented
default/alternative engine (a header comment names a `minise` variant built
with `ENABLE_QCP=OFF`); the paper's `__result` is `__return` in 0.5.7; the
examples' `cstar.toml` links `-lz3`, which only the SMT tutorial needs.

## Validation and expansion decisions

The acceptance corpus is small and behavioral:

- Absolute value: a bounded input contract passes; removing the `INT_MIN`
  exclusion leaves an overflow obligation (demonstrated in milestone 1).
- Pointer swap: correct disjoint ownership passes; missing ownership fails.
- Array clearing: empty and nonempty ranges satisfy the same contract;
  an off-by-one store or false invariant prevents success. Execute ordinary
  C output on representative buffers as an independent integration check.
- A changed outer decorator cannot reuse a proof of the old body. Nested
  bindings and repeated names map to the correct logical variables.
- Unknown effects, a remaining axiom, truncated report, failed server, and a
  stale input cannot produce a successful result.

Later additions are separate scoped work: structs and allocation first;
inline proof blocks after their binding rules are settled; editor
integration after trustworthy source-mapped batch results.

## Plan review

The parser/binder establishes legal AST positions, types, bindings, and
function declarations. The adapter trusts those facts and adds no x2c
validator or origin authentication. Its supported-operation dispatch is
necessary to prevent unknown effects from disappearing. The capture/final
body comparison establishes correspondence that parsing alone does not.
Backend state/theorem checks stay in their existing owner.

Reuse function and statement decorators, canonical Lists, Match, per-unit
Lisp state, Frontend/ParsedUnit, Context export, the x2c-graph development
archive, native compilation, dependency tooling, the pcre2 shim-header
pattern, and C*'s engine, kernel, and proof library. There is no existing
verifier to delete. The new lasting mechanisms are annotation records with
temporary marker calls, one adapter traversal, a small proof API, and a
driver/report. No macro sidecar I/O, new AST tags, alternate parser, plugin
framework, or proof cache is justified.

New rejection/report checks are limited to unsupported operations or target
models, capture mismatch or missing requested functions, native errors and
result completeness, input changes, and outstanding proof/trust obligations.
The negative examples exercise those boundaries. Additional gates or broader
validation requirements are not proposed.

[runtime]: https://cstarlang.org/en/reference/header-symexec.html
[smt]: https://cstarlang.org/en/tutorial/smt.html
[provenance]: https://gitee.com/cstarlang/cstar_docs/raw/main/vendor/include/PROVENANCE.md
[memory]: https://cstarlang.org/en/reference/memory-predicates.html
