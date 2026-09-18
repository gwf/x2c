# Cleanup lowering out of `src/emit.x`

> Status: active - Phase 1 done 2026-09-15 in 68eea0a; Phases 2 and 3 are
> optional and unscheduled. Item 2 of
> `plans/archive/architecture-salvage.md`, the last surviving piece of the
> declined compiler redesign.
> Notes: Phase 1 landed as `src/cleanup.x`, a pass that decides regions, the
> cleanup spliced before each exit, volatile locals, and the two `goto`
> diagnostics. The emitter still prints each region's push, frame, and
> `sigsetjmp` text, and generated C changed.

## The result

`defer`, `$auto`, `try`, `catch`, and `finally` are lowered into C control
flow while their text is being printed. The lowering becomes an ordinary
transform pass, so the shape it produces is an AST the compiler can show,
match, and test, and `src/emit.x` prints ordinary constructs only.

After Phase 1:

- `x2c translate --dump-transforms` shows the exception frame, the cleanup
  push and leave calls, the branch on `sigsetjmp`, and the cleanup statements
  spliced before each `return`, `break`, `continue`, and `goto` that leaves a
  region.
- The two diagnostics "goto target label is not defined in this function" and
  "goto cannot enter or cross a protected cleanup region"
  (`src/cleanup.x:221`, `src/cleanup.x:231`) come from the pass, at the stage
  that owns diagnostics.
- Generated C changed. Byte-identical output was the intended check, and it
  did not hold; the fixture and self-host comparisons carried the proof
  instead.

## Not the 2026-07-26 experiment

`agents/x2c-philosophy.md:649-656` records a relowering experiment that
failed on 2026-07-26: emitting cleanup only on locally visible exit edges
cannot serve a transfer that originates in a callee, and the callable cleanup
chain is what proved equivalent unwinding on 2026-07-27. This plan does not
reopen that. The runtime contract stays exactly as it is - the callable
chain, the per-frame `cleanup_watermark`, and the drain on transfer - and
both halves of the current design stay: the runtime registration and the
local exit edges. What moves is which compiler stage builds that structure.
A change that emits local edges alone is the failed experiment and is out of
scope.

## What is where today

`_rewrite_defer_list` and `_lower_defer_region` (`src/transform.x:1334-1366`)
turn a `defer` statement into either a callable defer region or
`(try body () finalizer)`, lifting the finalizer into a callback with a
capture environment.

`src/cleanup.x` then owns the analysis Phase 1 moved out of the emitter:

| Piece | Location |
| --- | --- |
| Region stack, barriers, exit splicing | `src/cleanup.x:124-148` |
| Label collection and `goto`, with two diagnostics | `src/cleanup.x:149-239` |
| Volatile locals, including the pointee rule | `src/cleanup.x:387-553` |
| Region rewriting and the per-function walk | `src/cleanup.x:566-702` |

`src/emit.x` prints the region text the pass placed: the defer record and its
push and leave (`src/emit.x:513-547`), and the exception frame, catch-site
registration, and `sigsetjmp` branch (`src/emit.x:575-640`). No `Emitter`
field carries cleanup state any more.

## Phase 1 - move the lowering, keep the output

Done in 68eea0a. `src/cleanup.x` is a transform pass that runs after the
existing defer rewrite and after lambda lifting, and consumes the two region
forms:

- `(defer body env callback records written)` becomes the environment
  declaration, the `X2CCleanup` record, `x2c_cleanup_push`, the body, and
  `x2c_cleanup_leave`.
- `(try body clause finalizer)` becomes the frame declaration, the catch-site
  registration, `x2c_exception_push`, the `sigsetjmp` branch, the landing and
  catch arms, and the trailer.

Both already exist as emitted text; the pass builds the same sequence as AST
using the real runtime types and functions rather than raw strings, so the
result types and binds like any other code. `$auto` needs no case of its own:
it already lowers to the same defer record.

The runtime rules the sequence has to keep, from `lib/exception.x`:

- `x2c_cleanup_leave` unlinks a record before calling its function, so a
  raising cleanup cannot rerun, and leaving out of order is fatal
  (`lib/exception.x:79`).
- `x2c_exception_leave` asserts that the cleanup chain is back at the frame's
  watermark and reports "exception frame cleanup imbalance" otherwise
  (`lib/exception.x:199-202`). Any exit the pass rewrites has to restore that
  balance.
- Return lowering evaluates and saves its expression before draining, and
  returns the saved value.

Three analyses move with it, unchanged in behavior:

1. **Region stack.** The pass walks each function carrying the stack of open
   regions, which replaces `cleanups` and `cleanup_path`.
2. **Exit splicing.** At `return`, `break`, `continue`, and `goto`, the pass
   inserts the cleanup statements of the regions being left, down to the same
   barriers `break_stop` and `continue_stop` express today. Phase 1 keeps the
   current copy-per-exit shape, because that is what makes the output
   identical.
3. **Volatile locals.** The setjmp rule that `_collect_function_state`
   implements becomes an analysis in the pass that marks the declarations,
   including the pointee rule in `_preserve_pointee`.

Ordering: the pass must run where its output is stable under the fixed-point
driver. The lowered forms use ordinary heads, so the region matchers cannot
fire again; confirm that with `--dump-transforms` on a nested case before
building the rest.

### What Phase 1 must not change

- The run-once claim on a finalizer, and the rule that a `raise` inside a
  finalizer reaches the enclosing frame rather than re-entering its own
  (now `_try_cleanup`, `src/cleanup.x:100`).
- The order within one region: finalizers, then that region's leave
  statement, so an inner frame leaves before an outer `defer` runs
  (now `_unwind`, `src/cleanup.x:124`).
- The absence of labels in the trailer, which lets an enclosing finalizer
  copy a block into several exits.
- The documented owner. `agents/x2c-philosophy.md:628` now names
  `src/cleanup.x` as the owner of the volatile rule; the section moved with
  the code.
- Source-map origins. Emitted cleanup inherits the origin of the statement it
  came from; the pass must attach origins explicitly, or `--source-map`
  builds drift. Check a `-g --source-map` build's line table before and
  after.

## Phases 2 and 3 - optional, each measured on its own

These change generated C and are not part of the move. Sequence them only
after Phase 1 is in.

**Phase 2: share cleanup code between exits.** Today each exit gets its own
copy of the cleanup text. In `bootstrap/`, 321 `x2c_cleanup_push` calls are
matched by 659 `x2c_cleanup_leave` calls, and 44 `x2c_exception_push` by 110
`x2c_exception_leave`: roughly two copies per region. With the lowering in
the AST, a shared exit block reached by label becomes expressible. The
measurement that decides it is generated C size and native compile time
against the duplication it removes; the labels the current design avoids are
the risk to weigh.

**Phase 3: the two initializer-side candidates** that moved here from item 1.

- Skip the `_x2c_initializer_choice` macro pair when the captured body uses
  each operand once, which is the common case and costs six lines of
  generated C per initializer.
- Reconsider the lazy entry guards `_patch_func_with_init` installs as the
  portable fallback to `__attribute__((constructor))`, and the
  `_cache_reachable_function_ids` analysis that places them. Removing them
  needs evidence that every supported toolchain runs constructors, which this
  plan does not have.

## Risks

- **Volatile analysis.** The rule exists because a local written between
  `sigsetjmp` and the landing must be `volatile`. A miss is a
  miscompilation that only appears under optimization. An emission fix in
  this area landed on 2026-09-15 for `$let` inside `try`; keep that fixture
  in view.
- **Catch arms.** Each arm closes the borrowed error record through the same
  cleanup stack. The arm bodies are emitted inside the region
  (`src/emit.x:575-640`); the pass has to preserve that nesting.
- **Fixed-point interaction.** A pass that rewrites `return` inside regions
  must not re-walk its own output.
- **Diagnostics position.** The two `goto` errors currently report with the
  emitter's origin. Moving them changes which token they point at unless the
  pass sets the same origin; the existing fixtures pin the message text.

## Validation

- `make verify-fixtures`. The fixtures that already cover this area:
  `defer-only-cleanup` (a defer-only function emits no frame or `sigsetjmp`),
  `defer-try-cleanup`, `defer-inside-try-exit` (a defer inside a `try` must
  not borrow the try's run-once claim), `defer-outside-try-exit` (leaving a
  `try` leaves its frame before an outer defer runs), `cleanup-loop-boundary`,
  `cleanup-nested-finalizer`, `unresolved-cleanup-return`,
  `raise-in-finally`, `raise-in-finally-unhandled`, `goto-cleanup-regions`,
  `goto-cleanup-rejected`, `goto-cleanup-sibling-rejected`,
  `macro-deferred-free-index`, and `macro-deferred-slice`. The `catch-*`
  family covers dispatch rather than cleanup order, and is affected only
  through the arm nesting. Phase 1 must leave every `.c` expectation
  unchanged.
- The nested callee-transfer fixture is the boundary case for either
  lowering, per `agents/x2c-philosophy.md:655-656`; it must pass unchanged.
- New `.transform` expectations for a defer region, a `try`/`finally`, and a
  `break` out of a region, so the lowered AST is a checked artifact. 36
  fixtures already declare a `.transform` phase.
- Self-translate `src/*.x` and `lib/*.x` and diff against `bootstrap/`;
  Phase 1 is byte-identical or it is wrong.
- `make -C unittest sanitizer`, because cleanup is where leaks and
  use-after-free would appear.
- `(cd unittest && ./test-all)`, `examples/check.sh`, and the gate, which
  takes two rounds once emission code changes.

## Size

`src/emit.x` is 1,913 lines; the pieces listed above are roughly 300 of them
plus six fields. `src/cleanup.x` should land near that size, since Phase 1
moves rather than removes. The reduction to claim is in what `emit.x` stops
knowing, not in line count.

## Plan review

The pass replaces emitter state with an ordinary transform, and adds no new
artifact, validator, or runtime mechanism; the runtime contract is untouched.
Phase 1 is a move whose correctness check is byte-identical output, which is
why it is worth doing before either of the changes that follow it. The two
diagnostics move to the stage that owns diagnostics rather than being
duplicated. If the identical-output check cannot be met for some construct,
stop and report which one rather than updating expectations to match the new
emitter. The last implementation step reviews the authored diff before
publication validation.
