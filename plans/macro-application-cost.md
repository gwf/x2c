# Macro application cost

> Status: active. Phases 1 and 2 and the undo-log transaction landed in
> PR #129 (2026-10-03). Phase 3 is implemented and submitted to the
> integrator.

## Result

Applying a quotation or a named template should cost about what building the
same syntax as a raw `%(...)` List costs. Today the compiler spends about 27%
of its own translation in two parts of macro application: semantic
transactions and the rebuild path. Most of that work depends only on the
definition or on nothing at all. The research also found that units with many
applications compile in quadratic time.

Language behavior does not change. Generated C for `src/` and `lib/` must
stay byte-identical through phases 1 and 2.

## Evidence

Workload: `x2c translate --no-deps --quiet src/*.x lib/*.x` (87 units,
serial) on converged trees at equal-length paths; mean of four alternating
runs of instructions retired; noise about 1%.

| Cost at dev tip | Instructions | Share of 235.6 G |
| --- | ---: | ---: |
| Semantic transactions opened by `_bind_invocation` (`src/parse.x:2682`), 7,758 per translation | 32.7 G | 13.9% |
| `_rebuild` (`rebuild_expression`, `rebuild_statement`), 189,653 applications | 30.9 G | 13.1% |
| of which the two `search_replace` walks over the template | 17.9 G | 7.6% |

The largest `_rebuild` site is the `$called` template in
`src/grammar.xmacro`: 172,745 applications and 28.6 G. The largest
transaction site is `compiler_wrapper` in `src/protocol.x`: 1,161
transactions at 6.8 M instructions each.

A transaction copies the active scope's `symbols`, `bindings`,
`enumerators`, and `macros` maps, plus `statics`, `binding_facts`, and the
name counters (`SymTxn._stage`, `src/symbols.x`). At file scope these maps
cover the whole unit, so each copy costs time proportional to the unit.
Generated units of N small functions show the result:

| N | plain loop | `foreach` | user macro, raw List | user macro, quotation |
| ---: | ---: | ---: | ---: | ---: |
| 500 | 0.93 s | 0.87 s | 1.05 s | 1.38 s |
| 1,000 | 1.06 s | 6.76 s | 1.78 s | 2.96 s |
| 2,000 | 1.85 s | 19.87 s | 5.83 s | 8.58 s |

At N = 2,000, 94% of `foreach` profile samples are in
`begin_semantic_transaction` and 4,782 of 5,126 in `Map_copy`.

Two smaller costs apply to project `meta` functions:

- A quotation returned from the meta helper crosses the pipe as reader text
  that carries its whole macro definition: 1,234 characters for
  `$!{ $target += $by; }`, against 110 for the equal raw List.
- Each quotation application counts toward the 10,000 expansion limit of a
  unit (`Expansion.check`, `src/macros.x:110`). A unit with 12,000
  quotation applications fails; the raw-List version translates in 1.4 s.

The earlier 3% foreach measurement does not reproduce for the conversion now
on dev (+0.19%, within noise). A full conversion of every foreach List costs
+4.06%, and 66% of that is the transaction.

Probes and logs are in the session scratchpad (`qcost/`, `qdesign/`); the
numbers above are the record.

## Phase 1: open the landing transaction only where it can roll back

`_bind_invocation` opens a transaction for every Macro value application at
statement, block, or unit position. A rollback is observable only when an
error is caught, and `Compiler.report_error` raises only while
`recovery_depth > 0`; otherwise it exits the process
(`src/diagnostics.x`). Every site that catches `<malformed>` raises
`recovery_depth` and owns its own transaction: `_try_unit_macro`
(`src/compiler.x`), `_speculate` (`src/initializers.x`), and the meta group
(`src/meta-group.x`).

Change `_bind_invocation` to open its transaction only when
`c.recovery_depth > 0`. Without one, expand directly.

Before relying on this, the implementer confirms that no other cause raised
inside an expansion is caught and resumed with `recovery_depth == 0`, by
reading the catch sites that can enclose `bind_syntax`. If one exists, the
rule becomes "open a transaction when a catch can resume", and that catch
raises `recovery_depth` like the others.

In the same change, stop counting applications of slot-free templates toward
the expansion limit and skip their recursion comparison. A template without
slots or nested invocations cannot recurse; compute that once per
definition. This removes the 12,000-application failure.

The source-macro transaction in `_invoke_definition` (`src/macros.x`) is
out of scope: it rolls back on purpose on some successful paths. It makes
plain user macros superlinear too (5.83 s at N = 2,000), and needs its own
design, such as an undo log over the staged maps. It is recorded under
"Outside this plan".

Validation:

- Byte-identical self-translation of `src/*.x` and `lib/*.x` against dev.
  Commit merges staged rows in a different order from direct mutation, so
  any difference here is a map-order effect to review.
- `unittest/compiler-fixtures/run.sh check`.
- Instruction counts on the workload above; expected saving up to 32.7 G.
- The N = 2,000 `foreach` unit approaches the plain-loop time.
- The 12,000-quotation unit translates.

## Phase 2: do definition work once in `_rebuild`

`_rebuild` (`src/macros.x`) rewrites the template on every call: one
`search_replace` per Expr hole to drop the `(expr (<macro-expr>) ...)` shell,
and one to strip `(at m-origin ...)` anchors. Both depend only on the
definition. It then builds capture rows and runs the definition's generic
Match pattern to find bindings whose positions the definition also fixes.

Compute the rebuild template once, in `Definition.finish`, and store it as a
`rebuild` row of the `macrodef`. `_rebuild` then fills that template with
bindings made directly from the hole list and the projected values, without
the capture-row Match. The projection rules stay in
`_capture_row_project`; the direct bindings call it per hole.

A new `macrodef` row changes every definition literal, so this is a
capability-before-callers transition: build, `make bootstrap-refresh`,
`make build-safe`, then a second refresh round. Shipped meta bodies in
`lib/*.xmacro` that hold Macro values need the intermediate-compiler
sequence recorded in `plans/quotation-adoption-audit-2026-10-03.md`.

Validation:

- Byte-identical self-translation, apart from definition literals in the
  generated C of files that define templates.
- All compiler fixtures, `make verify`, and the autodiff and yyjson package
  checks.
- Instruction counts; expected saving most of the 17.9 G of rewrites plus
  part of the capture-row and Match cost.

## Phase 3: compile slot-free quotations to direct construction

Decide after phases 1 and 2 are measured. After them, the remaining
in-process gap is the template fill and binder walk, about 1.3 G for the
full foreach conversion. The remaining cases are the helper pipe text and
quotations in project `meta` functions.

The design: a slot-free quotation builds its filled template directly at the
quotation site with the existing List-literal cell builder, wrapped in
`("x2c.quoted" (FRESH-ROW ...) SYNTAX)`. The landing (`bind_syntax`,
`resolve_expression`, `_helper_result`) allocates the private names from the
fresh rows and binds `SYNTAX`. Quotations with slots keep today's carrier,
because slot evaluation needs the quotation's macro-stack frame. The hole
projections move from `src/macros.x` to `lib/macro-value.x` so the compiler
and the meta helper share one implementation. A `meta` body that inspects a
quotation value would see the marker instead of a carrier; the book does not
describe the carrier.

## Delivery

Phases 1 and 2 touch different code (`src/parse.x` and `src/macros.x`
expansion checks; `src/macros.x` `_rebuild` and `Definition.finish`). Two
workers implement them in parallel. The orchestrator combines them and
submits one PR to the shared integrator with the measurements. Phase 3, if
approved, is a later PR.

## Results

Phase 1 alone did not fix the quadratic case: user source is parsed inside
the `FullParse.form` recovery boundary, so its expansions keep their
transaction. The undo log fixed it instead. `Sym.put` and `Sym.drop` record
the row a write replaces while a transaction is active; begin records the
log length, rollback restores rows back to it, and commit does nothing.
Binding-fact writes go through `Compiler.set_fact` and `drop_fact`.
Generated-name counters are still copied, because related compilers share
`c.names`.

Phase 2 stores `(rebuild (TEMPLATE KEYS))` and `(leaf 0|1)` rows. A leaf
template applies no templates and uses each hole at most once, so it cannot
recurse or multiply its arguments' applications; it is not counted. A
template that applies other templates gets no rebuild row, so a definition
never embeds a copy of another definition.

| Workload | Before | After |
| --- | ---: | ---: |
| 2,000-function `foreach` unit | 37.6 s | 2.8 s |
| 2,000-function unit using a raw-List user macro | 5.3 s | 2.3 s |
| 12,000 quotation applications in one unit | fails | translates |

Combined, on converged trees at equal-length paths (dev 5b4fda8e against
the branch tip; mean of four alternating runs after a warm-up), translating
`src/*.x lib/*.x` takes 12.4 s instead of 17.0 s: 184.6 G instructions
instead of 236.3 G. The 2,000-function `foreach` unit takes 1.6 s instead
of 18.8 s when both runs are warm.

## Integration review

The integrator reproduced and repaired two gaps before publication:

- In-place symbol maps made rejected declaration source metadata survive
  rollback. Source metadata writes now use the same undo log. A native probe
  retained the original declaration on dev and the rejected declaration on
  the submitted tree; the repaired tree retains the original declaration.
- An empty binder-use map was mistaken for an absent map. A template with no
  holes therefore still reached the 10,000-expansion limit. Definition
  finishing now tests map identity, so empty templates receive rebuild and
  leaf rows too. A 12,000-application probe verifies that case.

Phase 3 builds a quotation without slots where it is written, as
`("x2c.quoted" FRESH SYNTAX)`, with `("x2c.hole" ...)` for each hole use
and `("x2c.at" NODE)` for each origin anchor. `Compiler.land_quotation`
names the private binders, projects each hole through the existing
capture-row code at the landing, and binds without an expansion count or
a Match. It opens the existing semantic transaction during recovery, as
the pending Macro carrier does. A native integration probe verifies that
rejected syntax leaves no binding identities or facts behind. Projection
stays at the landing because a rebuild keeps `src` wrappers that a site
projection would strip; the
projections therefore stay in `src/macros.x` and the helper needs no copy.

| Probe (seconds) | Quotation before | Quotation after | Raw List |
| --- | ---: | ---: | ---: |
| 1,000 functions | 0.65 | 0.53 | 0.51 |
| 2,000 functions | 1.23 | 0.99 | 0.95 |
| 9,000 quotations in one meta call | 2.2 | 0.72 | 0.52 |

Self-translation improves another 1.2% (184.6 G to 182.4 G instructions).
The remaining gap in the 9,000-quotation probe is mostly the hole headers in
helper reply text (270 characters against 110); a compact header would need
one more bootstrap transition.

## Outside this plan
- Two bootstrap-refresh rounds are needed when a change alters the
  compiler's own emitted C. After one round, `.xi` files carry the old
  compiler's identity, every include is walked cold (`src/collect.x`), and
  instruction counts read about 7.7% low.

## Plan review

- Facts relied on: `report_error` exits without a recovery boundary, and
  each recovering catch raises `recovery_depth` and owns a transaction.
  Phase 1 checks the catch sites once during implementation and adds no
  runtime check. Phase 2 relies on `Definition.finish` fixing hole
  positions; `_rebuild` stops rediscovering them with Match.
- Reuse and deletion: phase 1 deletes work, adding one condition and one
  per-definition flag. Phase 2 replaces two per-call walks and a Match with
  one definition row; `_capture_row_project` stays the single projection
  owner. Phase 3 moves the projections instead of copying them.
- Idiom: the changes reuse the existing transaction, definition, and
  List-literal machinery. No cache keyed by List identity is introduced.
- Validators, diagnostics, negative fixtures: none. The expansion-limit
  diagnostic keeps protecting recursive templates, which still count.
