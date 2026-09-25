# Lifetime proof: results and possible next work

> Status: reference, 2026-09-25. The selected-root audit is shipped on
> `dev`. The extension below is a follow-up proposal, not dispatched work.

## What shipped

`x2c-graph certify --root NAME` audits reachable, bound and typed code from
the supplied units after macro expansion. It reuses the compiler's region
owner and parameter-effect rules, resolves project calls across units, and
reports `proved`, `violation`, or `incomplete` with paths and locations.
Native contracts are named assumptions in the report. The command does not
change normal compilation, its region diagnostics, or the checks run before
meta code executes. The
[meta sequencing plan](archive/meta-sequencing.md#4-conditional-lifetime-proof)
records the delivered scope and the first compiler-source case study.

The subsequent coverage pass added reviewed effects for scalar boxing and
unboxing, packed `Var` values, common string and collection operations,
and literal `printf` and `File.printf` formats without writes. The format
assumption is listed; dynamic formats and `%n` remain obstacles. Indexed
stores now reach the region walk, which reports a short-lived value stored
through an outer pointer. Calls and allocations inside branches and loops
also reach that walk. Focused fixtures show a safe conditional allocation is
proved, while a conditional dangling return and indexed store are violations.
These changes are in `60a89433`, `c9a003f5`, and `5175653a`; the last
final-tree `agent-pr-check` passed before delivery to `dev`.

The literate Lisp example's separate `Env` name collision was fixed in
`daa9fe9f`, restoring its build; that repair was not a lifetime proof.

The example sweep before the final branch and loop change found six
proved programs among 56 selected roots. This is a snapshot, not a current
corpus total. The first compiler-source case study remained `incomplete`,
with more than 19,000 obstacles and no reported violation; its report was
not a certification of the compiler.

On 2026-09-25, `x2c-graph certify --root main` over
`examples/power/word-count-summary.x` exits 3 (`incomplete`): no reported
violation, 11 obstacles, and the listed `printf` and `File_printf` format
assumptions. Four obstacles are pointer-bearing reads of `argv[i]`; seven
are unresolved effects: `File_open`, `File_close`, `File_iter`,
`Iter_try_next`, `Split_try_next`, and two `Map_try_get` calls. The earlier
word-count report had 29 obstacles, then 14 after effect coverage, then 11
after branch and loop coverage. None of these counts means the program
has been proved safe.

## Why the remaining rows cannot simply be filled

`File.open` returns a native stream that the caller must close. A no-effect
row would erase that obligation. `File.iter` keeps a borrowed file and a
Scope-owned line buffer in iterator state; `Iter.try_next` calls its stored
callback. `Split.try_next` also calls a stored callback and can write a
pooled `String` through an output parameter. `Map.try_get` writes a shallow
copy of a stored `Var` to an output parameter. The current summary forms
cannot express the provenance of those outputs or the lifetime of values
stored in a container. Calling any of these effect free would create a
misleading `proved` result.

The four `argv` reads need a defined borrow rule too. A pointer read from
an arbitrary indexed pointer cannot inherit the container's lifetime:
the element may point to storage with a different owner. A rule for the C
entry point's `argv` must identify that parameter by binding, state its
caller lifetime contract, and retain provenance through later uses.

## Recommended extension, if commissioned

Keep this an optional audit over selected roots. Add audit-only provenance
and resource facts while reusing the region walk for scoped allocations and
stores. Continue to name trusted native assertions and leave unrecognized
callbacks or memory transformations as obstacles. Deliver in the following
order so each step has a direct, falsifiable result.

1. **Indexed borrows.** Track the binding and owner of a pointer-bearing
   indexed read. Cover the entry-point `argv` contract and propagation into
   immediate calls. A local pointer array whose elements have shorter-lived
   targets must remain an obstacle or produce a violation when it escapes.
2. **Container values and output parameters.** Track the ownership of
   values stored in a `Map`, separately from the Map allocation. Propagate
   the possible stored value facts through `Map.try_get` into its output,
   including the untouched-output path on a miss. Resolve the ordinary
   `Var` hash and equality behavior for the observed keys; custom or unknown
   callbacks remain obstacles. A stored stack borrow returned through
   `try_get` must fail the proof.
3. **Native handle obligations.** Model successful `File.open` as an owned
   stream and `File.close` or `File.cleanup` as its discharge. Check lexical
   `defer`, `$auto`, early returns, and exception exits. Report transfer to
   a caller explicitly. A missing close, double close, borrowed standard
   stream close, or use after close must not pass.
4. **Known iterator producers and pulls.** At the bound `foreach`, connect
   `File.iter` to its `Iter.try_next` callback and `String.words` to its
   `Split.try_next` callback. Carry the yielded value's owner to the loop
   binder; account for the File iterator's retained Block and borrowed
   stream through exhaustion or scope cleanup. An arbitrary callback stays
   an obstacle. Probe premature Pool closure, file closure before a pull,
   and escaping iterator state.
5. **Integrated case study.** Rerun word count after each model, inspect
   every remaining obstacle and violation, and report `proved` only if the
   actual command does. Check reversed input order and negative variants,
   then rerun the example corpus and selected compiler entry points. Record
   changes in proved paths, violations, obstacles, and runtime cost. Review
   the authored and generated diff and use the required final-tree gate;
   add no recurring gate.

The main design review question is whether each new fact describes an actual
owner, a borrow, or a trusted external obligation. Reuse existing bindings,
region facts, and cleanup semantics; avoid special-casing the word-count
source or pretending that a Map owns the pointees of its stored `Var`s.
The extension should earn its cost by proving representative programs and
finding the corresponding deliberately broken variants. If it does not,
keep the current honest `incomplete` reports rather than broadening the
meaning of `proved`.
