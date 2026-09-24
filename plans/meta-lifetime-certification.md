> Status: active
> Decided by Gary on September 24, 2026. This replaces phase 8 of
> [internal-adoption-campaign.md](internal-adoption-campaign.md). The
> decisions are recorded below.

# Meta lifetime certification

Make the 10 methods held back by phase 8 callable from meta code, and prove
their lifetimes with the existing per-definition region walk. The runtime
table in `src/regions.x` holds each native callee's proof. Nothing needs a
whole-project escape pass.

## Why the whole-project pass is not needed

`Compiler.region_escapes`, deleted in `3f42981e`, seeded `_fixpoint` with the
summaries of other units, so cross-unit escapes in compiled code could be
found. A meta body does not need that. `Compiler.check_meta_regions` already
walks each `meta` definition when it is installed, using `c.meta_regions`.
That map summarizes every meta function installed before the current one, and
a meta body can call only installed names. The only callees without a summary
are bodyless native `meta` prototypes. For those, `_summary` falls back to the
`runtime` table and otherwise treats the callee as clean with `%(0 ())`
(`src/regions.x` ~263-272). So certification comes down to one rule: every
native target reachable from a meta body has a proved `runtime` row.

## Proved effects

A native meta target is certified when its `runtime` row states all four
facts:

1. **Allocation owner.** Fresh result storage lives in one of four places:
   nowhere, the active Scope (the session's user slot in meta), the active
   String pool, or, for observable resources only, the evaluator frame of the
   calling lowered function.
2. **Parameter effects.** Which arguments the result aliases (`return`) or
   retains (`result`). These are the existing sink facts.
3. **Callback effects.** None of the 10 methods takes a `Func`. Re-entry
   already goes through the adapter rows in `lib/lisp.x`.
4. **Finalization.** Every observable resource has exactly one attached Scope
   finalizer. It runs when the evaluator frame of the lowered function that
   created the resource ends, and not at `Lisp.destroy`.
   `Scope.malloc_finalized` already guarantees the finalizer runs exactly
   once, on both return and raise.

A native meta prototype becomes unproved when its signature carries a native
handle and it has no row. The rule is applied where native meta prototypes are
installed or bound (`_bind_native_meta`, `install_native_meta_function` in
`src/macros.x`). The shared walk does not change, so ordinary `check_regions`
still treats unknown callees as clean.

## Rows

- `(wrap)` already means "the result is the argument unchanged", which also
  describes unboxing a borrowed handle. It covers:
  - `Var_as_iter`, `Var_adnode`, `Var_token`, `Var_file` and `Var_job`;
  - the boxing duals `Iter_var`, `AdNode_var`, `Token_var`, `File_var` and
    `Job_var`.
- A new literal row form, `(summary OWNER SINKS)`, needs one case in
  `_summary`. It covers:
  - `String_lines` and `String_words`: `(summary 1 ((0 result)))`;
  - `String_splits`: `(summary 1 ((0 result) (1 result)))`;
  - `Var_fallback_iter`: `(summary 0 ((1 return)))`.
- A new owner kind, `(alloc final)`, behaves exactly like `(alloc)` in the
  ordinary pass. In the meta walk, its result is born in `w.frame`, so a Job
  that is returned or stored outside its frame is reported by the existing
  frame-escape finding. This needs one `int meta` field on `Walk`, set by
  `check_meta_regions`. `List_job` uses this kind.

## Methods

| Method | Owner | Sinks | Finalizer |
|---|---|---|---|
| `String.lines`, `String.words` | active Scope | (0 result) | none |
| `String.splits` | active Scope | (0 result) (1 result) | none |
| `Var.as_iter` | borrowed | wrap | none |
| `Var.fallback_iter` | caller's `dest` | (1 return) | none |
| `Var.adnode` | borrowed; tape in the active Scope | wrap | none |
| `Var.token` | borrowed from the token stream | wrap | none (not meta) |
| `Var.file` | borrowed | wrap | owned by its producer |
| `Var.job` | borrowed | wrap | owned by `List.job` |
| `List.job` | evaluator frame | (0 result) | `Job.cleanup`, exactly once |

`Var.job` exists only as the generated `Var_job` of the `Var(Job)` protocol,
so its `meta` mark comes from that conversion, in deliverable 4. The Split
methods return a `Split`, which crosses into meta through the `<split>`
`Var` conversion (decision 8).

## Decisions

Gary decided these on September 24, 2026:

1. Certification always applies when a native meta function is installed. It
   is not an opt-in mode.
2. The `runtime` table stays shared between compiled and meta code. The new
   rows may make ordinary advisory warnings more precise, and the first
   deliverable shows the repository's own warnings are unchanged.
3. `Job.new` attaches `Job.cleanup` as a finalizer for all code, through
   `Scope.malloc_finalized`. A compiled job that is still running when its
   Scope ends is now terminated and reaped.
4. A Job started in meta code ends when the lowered function that started it
   returns or raises, even if it was started inside an inner `$scope` block.
5. `Var.file` is enabled now, although nothing meta-callable produces a File
   yet.
6. `Var.token` stays out of meta. It is deliberately private in
   `lib/tokenizer.x`, so its row stays in the table but no `meta` mark is
   added.
7. `Var.job` moves to deliverable 4. It is generated by the `Var(Job)`
   protocol and has no meta producer until `List.job` lands.
8. `Split` gains a `Var` conversion: `Split.var`, `Var.split` and
   `protocol Var(Split)` under the `<split>` tag, plus
   `meta protocol Iter(Split)`. A native meta target must box its result, so
   `String.lines`, `String.words` and `String.splits` need it. The `<split>`
   tag takes one custom descriptor row: a program linking the whole library
   uses 17 of 32. Meta `foreach` over a `Split` binds `Split_try_next`
   lazily in `etc/comptime.xlisp`, with a native target row in `lib/lisp.x`,
   as the other `try_next` rows do.

## Deliverables

Each is one coherent change delivered to `dev`, and each ends with a review of
its authored diff before the gate.

1. **Rows and the install rule.** This touches only compiler code and adds no
   native targets.
   - Add `(summary ...)`, `(alloc final)` and `Walk.meta` to
     `src/regions.x`, plus the rows above.
   - Add an "unproved native meta lifetime" error at native meta installation.
   - First inventory the existing `meta` prototypes, and give each prototype
     that returns a handle and has no row an accurate row.
   - Validate:
     - the repository's region warnings are unchanged;
     - `meta-heap-regions` still passes;
     - a new negative fixture rejects a meta body that returns an
       `(alloc final)` result.
2. **Finalize `Job`.**
   - Make the `Job.new` change in `lib/process.x`.
   - Validate with a compiled test where a `$scope` ends while a `sleep` job
     is running and the child is reaped. Existing process tests stay green.
3. **Mark the seven memory-only methods `meta`.** This touches
   `lib/split.x`, `lib/common.x`, `lib/autodiff.x`, `lib/lisp.x` and
   `etc/comptime.xlisp`. `Var.token` is left out and `Var.job` moves to
   deliverable 4 (decisions 6 and 7). It adds new native targets, so it
   takes two rounds:
   - round one adds the marks, the `Var(Split)` conversion,
     `meta protocol Iter(Split)` and the `Split_try_next` rows
     (decision 8), and refreshes `bootstrap/`;
   - round two adds meta fixtures that call each method.
4. **`List.job` in meta.** This also takes two rounds.
   - Round one adds bodyless `meta` prototypes for `List.job`,
     `Job.start`, and the generated `Var.job` and `Job.var` in
     `lib/process.x`, and adapters `_lisp_List_job` and `_lisp_Job_start` in
     `lib/lisp.x` that run the call under `$scope(_lowered_owner())`. Their
     target rows follow the generated targets, so they replace the direct
     rows. `Job.start` gets the row `(summary 0 ((0 return)))`. Round one
     refreshes `bootstrap/`.
   - Round two adds the fixtures below and drops the local `meta` mark from
     `meta-final-regions`.
   - Add a fixture: a meta function starts a long job and returns without
     waiting, and the process is gone when the call returns. Repeat with a
     raise.
   - Add a negative fixture: a meta function that returns its Job is
     rejected.
5. **Close phase 8.**
   - Reclassify the 10 methods in `meta-authoring-and-coverage.md`.
   - Point phase 8 of the adoption campaign here.

## Plan review

- **Trusted facts.** The meta region walk, `c.meta_regions`,
  `Scope.malloc_finalized` and the per-call Lisp frame already establish
  their facts. Certification adds only the missing summaries for native
  callees, and no consumer rechecks them.
- **Reuse.** The plan reuses `Region`/`Fact`, `_summary`, the `runtime` table,
  `(wrap)`, `w.frame`, the Func adapter rows and `Job.cleanup`. It does not
  revive `region_escapes`, and it adds no allocation registry and no second
  analyzer.
- **New pieces.**
  - One row form, `(summary ...)`, is needed because rows must be able to
    state sinks.
  - One owner kind, `(alloc final)`, with the `Walk.meta` flag, is needed
    because frame ownership differs between compiled and meta code.
  - One adapter is needed because frame ownership has to be chosen at the
    call.
- **Diagnostics.**
  - The unproved-lifetime error prevents an unsafe native crossing.
  - The frame-born Job fixture guards against use after free and leaked
    child processes.
  - Nothing else is added.
