# Meta continuation: x2c as its own metalanguage

> Status: active, refreshed 2026-10-04 against origin/dev
> 12a095f9728796f5138278a3082f4e3e7b5e085e. The original review used
> fe19c15f13c22dfcad8930a7d9bf97e0d6de428a.
> Item 1 has a local compiler prototype and a separate deep plan in worktree
> `4c75`; neither is shipped on dev. Match preparation and prepared formatting
> are deferred. The operator ledger from item 4 is implemented locally.
> The other opportunities and the numeric policy experiment remain proposed.
> This document is a campaign roadmap, not an implementation specification.
> Updating this record does not authorize implementation or publication.
> Follow-up: Gary approved the operator ledger implementation. It is integrated
> on origin/dev b5c2dde7. Implementation and verification are complete, and
> the advisory performance checkpoint is neutral. The destination is dev.

## Intended result

Make the project's source more direct by using x2c to describe, analyze,
recognize, and construct x2c. Fixed descriptions should produce reusable
plans and code before execution needs them. Each analysis should have one
owner, usable at the appropriate stages.

The governing source rule is:

- Recognize source forms as source through shared grammar macros.
- Compute semantic decisions in ordinary named x2c functions.
- Express generated output with quotations.
- Keep raw AST operations for internal forms without a source spelling and
  for algorithms whose actual operation is List construction or traversal.

Success means fewer independently maintained relationships, less repeated
analysis, and clearer authored source. Source reduction and execution speed
are separate results. Neither is assumed from the use of a macro.

## Baseline and evidence

The original review used fe19c15f. This refresh starts from fetched
origin/dev at 12a095f9 on branch `codex/update-meta-continuation`. It compares
all intervening commits and checks the affected authoritative source and
fixtures. The requested file was not tracked in dev or any fetched branch;
the starting copy was the untracked plan in
`/Users/gary/.codex/worktrees/4c75/x2c/plans/meta-continuation.md`.
The source copy remains unchanged.

Current-source statements below refer to 12a095f9. Local prototype results
refer to their original baseline and are not verification of current dev.
This refresh does not rerun builds, fixtures, or performance measurements.

The review inspected compiler construction and recognition, Match preparation
and emission, runtime ledgers and formatting, meta examples, package wrapper
generation, compiler-backed documentation, and shared site highlighting.
It did not build dev, execute fixtures, measure performance, or audit release
readiness. Proposed changes have source evidence, not implementation proof.

The latest language work already supplies these foundations:

- Source-form macros recognize and construct canonical syntax. Nested macro
  patterns and typed shells compose.
- Quotations write expression, statement, and unit output as x2c source.
- Expression holes evaluate once, in written order, before construction.
  Type, scalar, syntax, and sequence values retain their respective roles.
- Eligible quotations construct syntax where written. Landing still binds
  and types that syntax in the destination unit.

Relevant evidence at the baseline:

| Subject | Source or executable example |
| --- | --- |
| Shared source recognition | `src/grammar.x` |
| Quotation construction and landing | `src/macros.x`, `Definition.construction`, `Compiler.land_quotation` |
| Expression-hole semantics | `docs/src/reference/language.md`, quotations section |
| Hole composition and evaluation order | `unittest/compiler-fixtures/macro-quotation-expression-holes.x` |
| Reflection-driven generation | `examples/magic/meta-functions.x` |
| Existing meta ledger projections | `lib/var-tags.x` |
| Literal computation with runtime fallback | `lib/system-macros.x`, `$dedent` |

The dev records `plans/x2c-metalanguage.md`,
`plans/quotation-adoption-audit-2026-10-03.md`, and
`plans/meta-followups.md` retain previous decisions and results. This plan
continues that work. It does not reopen completed migrations by treating
their original proposals as current gaps.

## Changes since the original review

- `a7edf144` changes `Walk._lower_defer` to insert the results of ordinary
  `builtin_defer_record` and `builtin_try_cleanup_placement` calls through
  expression holes. It removes the former's linked slot target. Lowered
  code values bypass helper-result traversal and the leftover-binder scan;
  binding replacement runs only when effects supply replacements. This is
  already-shipped adoption of the governing source rule, not future work.
  [Macro application cost](archive/macro-application-cost.md) records the
  capture representation and translation-memory questions.
- `88df676e` makes `Definition.body` read complete templates during collection,
  including declaration initializers. The earlier shallow collection path
  could retain an initializer-free declaration. The
  `declaration-macro-initializers` fixture covers named and anonymous forms,
  direct and stored Macro application, and source recognition.
- `1556a6c3` installs imported protocols before member discovery through
  `Compiler._ordered_occurrences`, not just `protocol_members_for`. The
  `macro-import-string-add` fixture covers imported String addition. Further
  grammar preparation must preserve these collection-time resolutions.
- `5666ad76` reports an expression hole without an x2c type at its written
  expression through the existing unresolved-type report. The
  `macro-quotation-expression-hole-unknown` fixture covers unresolved calls
  and an unknown identifier. This is current diagnostic behavior to preserve;
  the roadmap proposes no additional validator or diagnostic.
- `585da2a6` documents compile-time effects per translated unit in the CLI
  reference and runs the declaration-bundle probe serially. Imported meta
  code must not assume one execution across parallel translation workers.
- `7c6140dc`, `73a2e061`, and `d4c834ff` change build scheduling: each unittest
  unit translates once, independent publication checks run concurrently,
  and command builds and smoke tests run concurrently. They do not move
  Match preparation or change quotation semantics. Future measurements must
  use the same current scheduling and equivalent converged toolchains.

All five roadmap items were rechecked. Static Match preparation has not landed:
`MachineProgram` still has its packed four-count header, the emitter declares
an empty static MatchCaptureSite, and its first-use path calls
`MatchPlan.prepare`. The native scalar ledger still has its Lisp projections
and `_Alignof` constructor. Formatting, grammar derivation, operator tables,
Torch generation, and numeric policy owners are unchanged in this interval.
Their proposed scopes remain applicable; no performance gain is established.

## Staging boundaries

| When the complete inputs are known | Where the analysis belongs |
| --- | --- |
| Fixed grammar and literal patterns in compiler source | Compiler build |
| User declarations, types, and literal patterns | User-program translation |
| Dynamic patterns, runtime values, locale, and external state | Program execution |

A shipped meta function executes inside the running compiler when called.
Adding `meta` alone does not move that analysis into the compiler build.
Project meta functions use a cached host helper and receive facts through
arguments such as TypeInfo and Source. They cannot query arbitrary compiler
state. Preserve this boundary when choosing a shared analysis surface. Imported
compile-time forms may execute separately in each translated unit's worker;
serial translation may reuse one import across units. A helper cache does not
establish process-wide or build-wide execution of an imported effect.

Binding, typing, protocol resolution, cleanup placement, and region summaries
depend on the program being translated. Fixed rules can be prepared earlier;
their application still belongs to that translation. Region summaries reach
a fixpoint over the actual functions and calls. No proposal here replaces
that analysis with a precomputed answer.

Compile-time output must not contain helper-process addresses or borrowed
objects that expire before use. Target ABI facts must come from the target,
not from an assumption about the machine running meta code.

## Ordered work

### 1. Precompute general static Match plans

Defer this candidate after the underwhelming first investigation. Deep planning
and a local prototype exist, but adoption needs stronger evidence of practical
value and lower costs. Reassess that prototype against current dev only if
further evidence justifies reopening it.

The local deep plan is
`/Users/gary/.codex/worktrees/4c75/x2c/plans/static-match-preparation.md`.
It recommends borrowed plans with explicit MachineProgram section pointers
and one shared executor. It reports stage-1/2 convergence and a passing unit
executable at fe19c15f, not at the refreshed baseline. Nonflat raw arms were
prototyped; direct List APIs, catches, and macro recognition remain outside
that prototype. Generated storage grows, and comparable Match-rich
translation measurements show additional cost. Header placement and a
context-dependent String-lowering failure also remain recorded concerns.

Current dev repairs imported String operator resolution. That repair does
not establish that the prototype's String failure has the same cause.
Reproduce the original failing workload after integration before closing it.
The new lowered-code handling also requires reassessing the prototype's
cleanup-normalization repair against the actual current code path.

On current dev, `Compiler.match_pattern_binders` in `src/compiler.x`
analyzes capture layout during translation. `Emitter._match_capture_arm`
in `src/emit.x` emits a MatchCaptureSite for a general static pattern.
`MatchCaptureSite._prepare` in `lib/match.x` prepares it on first execution
under the site lock. `MatchPlan.prepare` in `lib/match-plan.x` computes
normalization, capture layout, wordcode, and dispatch keys.

Desired result: an eligible fixed pattern has its analysis performed during
translation. Generated code contains an immutable execution description.
The subject and captured values remain runtime inputs. Dynamic patterns keep
their ordinary runtime preparation. Existing flat-pattern direct emission
remains the comparison baseline.

For the compiler's own fixed patterns, this moves preparation into the
compiler build. For user-program patterns, it moves preparation from first
execution into user-program translation.

Reuse the same preparation algorithm and machine executor. Do not implement
another matcher or normalize patterns with a second semantic owner. A
portable emitted representation may be necessary because MachineProgram
currently holds shallow Var constants and binder identities. Its exact form
is an open design decision.

The deep planning session must settle:

1. Which currently emitted patterns qualify, including raw static cases,
   macro-valued cases, and static catch patterns. Account for retained paths.
2. Which results already exist during translation and can be retained rather
   than recomputed. Separate pattern preparation from execution specialization.
3. How instructions, constants, binders, normalized values, and keys are
   emitted without process-local pointer bits or invalid pool lifetimes.
4. Whether constants need runtime materialization, and its exact ownership,
   initialization, concurrency, and shutdown behavior.
5. How the shared analysis runs at both stages without depending on compiler
   queries unavailable to project meta code.
6. How malformed and ineligible statuses, errors, capture ordering, atomic
   capture publication, arm priority, and canonical equality remain compatible.
   Static knowledge alone does not authorize earlier rejection.
7. Which current cache, site, allocation, or registry operations disappear
   from eligible paths, and which remain necessary for dynamic patterns.
8. Bootstrap sequencing, emitted representation compatibility, and the
   smallest coherent implementation boundary.

Use a nonflat literal pattern for the decisive experiment. Flat cases already
receive direct conditions, so measuring them would miss the proposed change.
Use existing Match differential tests, plan tests, fixtures, and catch checks
as evidence. Select concrete cases after tracing the affected paths.

Measure first-use preparation, repeated matching, a compiler translation
workload, build cost, and emitted code/data size separately. Precomputation
does not establish faster steady-state execution. Compare equivalent trees
and toolchains, and record absolute workloads and results.

The session should produce a decision-complete item-1 plan and a focused
feasibility result. It must not silently narrow the result to a cosmetic
table rewrite or broaden it into a general matcher redesign.

### 2. Finish native scalar projections in x2c

`lib/native-scalar-types.x` already has an x2c meta ledger. Naming,
access entries, and alignment construction still use Lisp projections.

Move naming and table projection into ordinary meta functions and quotations.
Keep one scalar ledger and the current native load/store behavior. Evaluate
alignment separately: current dev lacks `_Alignof(type-name)` with a Type
quotation hole. Retaining a narrow primitive constructor is an acceptable
outcome; a language extension needs a demonstrated use and separate design.

Compare generated access tables and native layout behavior. Preserve target
size and alignment, scalar conversions, and wide-value ownership. This is a
bounded source improvement, not a promised performance change.

### 3. Precompute fixed format specifications

Further investigation produced a [prepared-format feasibility result](prepared-format.md).
A native x2c analyzer now emits fixed descriptions through quotations.
The refactored prototype shares conversion code, matches 43 static cases,
and passes 4,000 calls sharing one plan across four Thread workers. Static
plans save about 11-26% against the final shared ordinary path on three
varying-value conversion workloads.
Complete constructed exports put those isolated gains in context. Formatting
20,000 native records into 448,890 bytes took 18.470 ms with String.format
and 14.738 ms with the prepared plan. Existing Buffer.printf took 2.594 ms
for the same output with known native types. A 20,000-record Lisp export
including evaluation, argument Lists, and joining took 68.707 ms with the
ordinary formatter and 64.706 ms with a prebound fixed-format helper.
These are warm in-memory exports, not existing applications or compiler builds.

No production invocation of String.format was found in src, lib, etc,
commands, tools, or examples. Compiler reporting uses existing printf paths.
There is no demonstrated internal migration or typical-workload speedup.
The useful niche is repeated checked formatting of runtime Lists of Vars;
the Lisp export improved about 4-6% across two runs with its favorable binding.

Defer the optional public macro until an actual caller justifies its adoption
and storage costs. Feasibility is proved, usefulness for current workloads is
not. The linked-analyzer candidate, costs, fallback, and placement limits
remain recorded. This does not reject other implementations or automatic
specialization, which were not measured. No production implementation or
publication is authorized by this record.

Runtime spike, 2026-10-04 at 12a095f9: reusing parsed fixed specifications
saved 6-8% on three repeated conversion workloads. Retaining native C
spelling as well saved 15-25%, against 439, 823, and 921 ns/call in the
built runtime. Values varied across 64 prebuilt argument lists. Preparation
cost 208-390 ns; descriptors used 100-252 bytes excluding allocator overhead.
The standalone object's text grew by 2,250 bytes with the ordinary formatter
retained. Forty-three cases matched output and complete errors in both
prepared modes. Star-bearing and malformed formats used the ordinary path;
star analysis and translation-time preparation were not implemented.

This supports further runtime design, not a compiler speed claim. No
production callers were found in the searched compiler/library, examples,
or commands. The local evidence and reproducible probe are in
`.context/prepared-format-spike/`; logs are `debug/format-spike-*`.
The follow-up design explored a file-scope declaration with borrowed static
storage. The subsequent workload investigation defers its production adoption.

`String.format` in `lib/string-format.x` scans format text on every call.
Split syntax analysis from execution so one shared analyzer can produce
literal spans and conversion specifications at either stage.

A literal-format entry point could compute that description during
translation. Dynamic formats use the same analyzer at runtime. Runtime
execution still consumes values, resolves star widths and precision,
performs conversions, and formats under the process locale.

Settle the public surface and error timing before implementation. Preserve
checked formatting, staged output, and missing/excess argument behavior.
Do not turn a runtime format failure into a translation failure implicitly.
Use `$dedent` as an existing staging example, not as proof that formatting
has identical semantics or implementation needs.

### 4. Prepare fixed grammar metadata earlier

`Definition.finish` in `src/macros.x` derives fresh rows, invocation patterns,
rebuild keys, and leaf classification. Some facts depend only on a template.
Explore emitting portable descriptors for one shipped source form during the
compiler build. Retain unit-specific rebinding and expansion identities.
Preserve complete declaration initializers and their retained macro stack
across collection and full parsing. Imported protocol installation must
precede operator and member lookup; descriptor preparation must reuse that
resolution owner rather than bypass it.

This candidate is less certain than item 1 because partial preparation
already exists. Keep it only if it removes repeated work or a source owner.
A descriptor that merely adds storage beside unchanged analysis does not
meet the objective.

The operator ledger is now implemented locally. `src/operator-ledger.x`
owns 22 binary operators, including 11 compound pairs, seven direct protocol
mappings, and five derived mappings. One helper projects switch cases, and
`src/operator-ledger.x` imports it once inside ordinary lookup function bodies.
The five public signatures and all callers remain unchanged. `src/ast.x` and
`src/protocol.x` retain declarations and remove the paired runtime tables.
API comments moved with their implementations; generated documentation follows
the new owner. The book's protocol table remains authored prose.

The prototype's native module is unnecessary in production. Function-body
generation works through the ordinary import path; whole-function generation
at file scope failed the meta target check. New linked meta functions were
staged before their callers and the portable bootstrap was regenerated through
the existing target. No build step, gate, runtime cache, or validator was added.

The integrated native object matches the original five lookups for 35 named
symbols and 4,096 raw Symbol values. Authored source grows by 25 lines;
the benefit is removing separately maintained positional relationships.
The existing test target now links the new implementation object. Generated
bootstrap and API documentation follow that owner. The full
`tools/gate-state.py ensure agent-pr-check` passes, including unchanged
diagnostic fixtures and byte-identical bootstrap/stage-0/stage-1 C/H files.
Source ownership is established; no compiler speedup is claimed.

Integration exposed an unstable redundant `String_add` prototype in one
constant diagnostic initializer. Adjacent literal fragments replace its two
runtime additions and preserve the exact diagnostic. Convergence now passes;
the general cause of that prototype difference remains unproved.

The advisory checkpoint compares converged origin/dev 26a29650 with candidate
25539444 on the same host. Nine alternating warm runs translate seven
byte-identical top-level inputs: transform, emit, expressions, generate,
parse, type, and tokenizer. Each compiler uses its own matching source tree
and prelude. Median elapsed time is 2.204 seconds for dev and 2.200 seconds
for the candidate. Median retired instructions total 30,869,262,837 and
30,829,044,110 respectively, a 0.13% reduction. These results support neutral
throughput, not a meaningful speedup. This is translation of seven modules,
not a full native build or application workload. The compiler executable grows
from 2,692,864 to 2,693,152 bytes, including the new linked meta helpers.

The earlier mixed-root comparison is invalid: the candidate used baseline
headers alongside its own prelude. A mixed-root live-symbol run also rejected
duplicate macro imports. Neither result describes normal matching-tree
throughput. The reproducible comparison and raw samples are retained in
`.context/operator-ledger-spike/compare-translation.py` and
`.context/operator-ledger-spike/translation-results.json`.

### 5. Extend canonical generation into packages and tools

`packages/torch/tools/gen-ops.py` owns schema selection, x2c signature
mapping, wrapper emission, and source-based discovery of existing names.
Initially retain external schema ingestion and C++ generation. Pass
canonical rows into x2c meta functions that select and construct x2c wrappers.
Preserve the package's supported operator surface and native error behavior.

Compiler-backed documentation already consumes definition records through
`tools/definitions.x`. Site highlighting already uses the editor grammar.
Reuse those owners. Do not add a parallel source scanner or grammar simply
to move a tool into x2c. Package checks remain optional outside their scope;
this roadmap adds no recurring package gate.

### Lower-priority experiment: numeric pair policy

The Var ledger has fixed numeric ranks and widths. `lib/varops.x` selects
common numeric tags at runtime. A generated pair policy is a possible
projection, but it must retain target-dependent widths and value promotion.
Compare it with the small current algorithm before selecting it. Table size,
lookup cost, and source clarity may favor retaining the current code.

## Continuation and delivery

The selected implementation is the operator ledger. Implementation, focused
parity, full correctness checks, and the advisory checkpoint are complete.
Deliver this change to dev under the existing final-tree publication checks.
Gary's explicit origin/dev instruction establishes the destination. Production
promotion to main is outside this change.
Match preparation and prepared formatting remain deferred. Record further
baseline drift before using their older prototype findings as current evidence.

Later items remain proposed scopes. Their detailed designs follow the evidence
and results of earlier work; the order does not authorize implementation or
create additional mandatory planning steps.

When implementation is requested, follow current repository delivery rules.
Review and fix the completed authored diff before publication validation.
Use existing focused checks and the required final-tree publication command.
Do not add, expand, or reorder recurring gates under this roadmap.

## Plan review

Existing parser, binder, category, and pattern producers establish canonical
syntax and semantic facts. Consumers should reuse those facts rather than
authenticate syntax origin or add a second AST validator. Arbitrary canonical
Lists constructed by compile-time code remain legitimate syntax.

The roadmap reuses Match preparation and execution, scalar ledgers, checked
formatting, macro derivation, and compiler definition records. New emitted
descriptions are justified only where they carry results across stages and
remove repeated analysis. A second cache, matcher, grammar, or generalized
execution framework is not presumed necessary.

Ordinary x2c functions, source-form macros, quotations, and canonical values
remain the authoring tools. The goal is direct source with one owner per
decision, not a framework imported from another language.

No new validator, dedicated diagnostic, or negative fixture is proposed by
this continuation plan. Detailed designs must identify existing public
behavior and unsafe native crossings before proposing such additions. No
whole-project performance improvement is claimed yet. The local Match
plan reports identical stage-1 and stage-2 compilers and a passing complete
unit executable at its older baseline; this refresh does not repeat them. Its generated storage and translation costs still
need reduction before adoption; the Match plan records comparable evidence.
