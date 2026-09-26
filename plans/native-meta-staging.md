# Native meta execution: staging user meta code and removing the Lisp lowering

> Status: needs author scoping - design spike, 2026-09-26. Nothing is
> implemented. This records the mechanism, the removal list, and the
> order of work so it can proceed in the background. Estimates are
> deliberate overestimates of what becomes removable; each removal is
> gated by the validation named beside it.

## The result

A bodied `meta` function has one execution model: it is compiled by the
ordinary C backend and called as native code during translation. Meta
code that ships with the compiler is linked into it. Meta code a user
writes is compiled once into a module and loaded, automatically, the
first time a `$name(...)` needs it. The x2c-to-Lisp lowering
(`src/comptime.x`), its C-semantics runtime (`etc/comptime.xlisp`), the
Lisp wordcode tier (`lib/lisp-machine.x`, the AUTO region of `lib/lisp.x`,
the Lisp half of `lib/machine.x`), the generated Lisp artifacts and their
generator go. Compile-time Lisp (`$(...)`, `.xlisp` imports, `defmacro`,
`$lisp.bind`) stays as a documented feature on one tree-walking evaluator.
The documented compile-time subset becomes all of x2c.

What already exists and is reused unchanged: `meta native` and bodyless
`meta` prototypes bind compiled functions for compile-time calls; `x2c
build --kind meta-module` writes an entry unit whose
`x2c_module_targets()` returns a name-to-`Func` Map and stamps the module
(`src/build.x` `_write_entry`, `Build.module_entry`);
`Compiler.load_native_module` checks the stamp, `dlopen`s
`RTLD_NOW | RTLD_LOCAL`, and records the targets
(`src/macros.x:1645-1735`); `_bind_native_meta` resolves a name against
the `<compiler>` supplier, `lisp_native_targets`, linked extensions, and
loaded modules; `_evaluate_meta_value` lifts constant arguments, calls,
catches, and `meta_value_expression` turns the result into syntax
(`src/macros.x:2173-2225`); `check_meta_regions` rejects a body whose
call-scope storage escapes. The new work is the group, its trigger, the
cache, the `meta static` reset, and one rule about `$` inside meta bodies.

## Resolving the circularity

"To compile a meta function you need an x2c compiler, and the compiler
needs an interpreter to run it" does not hold, because the compiler that
meets the definition is already a running native program. It emits the
function to C the same way it emits the function's runtime copy today
(a dual-form `meta` function is already translated for the program), runs
`cc -shared` on that C, loads the object into its own process, and calls
the symbol. No x2c is interpreted at any level. The compiler's own
built-in meta code is not staged at all: it is compiled into the compiler
when the stage is built, by the previous stage, and the checked-in
bootstrap C carries it like any other compiler unit. The remaining
interpreter is the Lisp evaluator, which runs Lisp source, never x2c.

The dependency order inside one unit is the source order the language
already documents (definitions and imports become visible in source
order). A meta function is emitted only after it is bound and typed as an
ordinary function, which the parser already does; a `$` call that reaches
it can only appear later in the source; so at the moment of the first
call every function it can reach is already parsed. Mutual calls between
meta functions inside a body are ordinary C calls inside one module: a
body runs entirely at compile time, so `$f(x)` inside a meta body means
`f(x)`. `$` keeps its meaning only at the boundary between program code
and compile-time code, where it says "evaluate now and insert the
result". This is the one language-level rule the design adds; today the
lowering evaluates a nested `$f(x)` through the session, and the
documented behavior of a program does not change.

## The mechanism

**Group.** Each translation unit keeps a pending group: the bodied
`meta` definitions parsed so far that are not yet bound to native code,
in source order, as typed AST. An imported `.xmacro` contributes its
definitions to the importing unit's group when the import runs, exactly
as its macro definitions become visible then. `meta native` definitions
and bodyless prototypes are not in the group; they bind as today.

**Trigger.** `_evaluate_meta_value` (and the macro-template slot that
calls a meta function, `lower_meta_expression`'s callers) first asks
`_bind_native_meta` for the name. If the name is in the pending group,
the group is staged, then bound, then called. A unit with meta
definitions and no `$` call never stages; its definitions are emitted for
the program only, as now.

**Staging.** Staging emits the whole pending group as one C unit through
the ordinary backend: the functions, every static or type they depend on
that the unit has already bound (the same closure the runtime copy
needs), an entry table in the shape `_write_entry` writes today, a stamp,
and a reset entry (below). It compiles with the configured toolchain
(`src/toolchain.x`, `cc -O1 -fPIC -shared`, the flags `--kind
meta-module` uses), places the object under the script cache root
(`src/script.x` gives the shape) at a content hash, and loads it with
`Compiler.load_native_module`. The hash covers the group's source text,
the compiler stamp, and the toolchain identity, so an unchanged group is
loaded without compiling. The group is emitted cumulatively: a later
staging in the same unit emits every definition parsed so far, so a
function that calls an earlier one is a C call inside one module; the
earlier module stays loaded (modules are never unloaded), and the newer
module's own copies win under `RTLD_LOCAL`. Cumulative staging is the
simplest correct rule; per-definition modules linked with `DT_NEEDED`
against earlier ones are an optimization if the REPL needs it.

**Binding and calling.** Loaded targets are `Func`s with signatures. A
`$name(args)` lifts its arguments with the existing rules (constants,
syntax Lists, Symbols, Strings, computed values from other meta calls),
boxes them, calls through the `Func` adapter, and lifts the result with
`meta_value_expression` and `lift_macro_lisp_expression` as today. A call
runs inside a kernel-owned `$scope()`, and the lifted syntax is built
before that scope pops, which is what `_meta_data` does now.

**Compiler operations.** A body that calls `x2c_type_fields`,
`x2c_ident`, or any `lib/meta.x` operation calls a function in the
compiler binary. The compiler links with `-rdynamic`
(`builds/stage.mk`) so a module resolves those symbols against the host
process; native modules already reach the runtime this way. Nothing new
binds them. The compile-time-only inference stays: a body that reaches a
compiler operation, an explicit `$` call, or a template constructor gets
no runtime form (`meta_is_comptime_only`, `src/parse.x:2018`), decided by
a callee scan over the typed body instead of by the lowering's
`lower_reached_meta`.

**`meta static`.** Documented as a separate per-unit value built from the
same initializer. A module loads once per process and workers translate
several units, so every module exports `x2c_module_reset()`, generated
from the group's `meta static` initializers, called when a unit starts
using the module, in a per-unit meta `Scope` opened at unit start and
destroyed at unit close (the role `C._meta_globals` plays in the lowering
today, `src/macros.x:1047-1051`).

**Errors.** A raise inside a staged body transfers through the compiler's
own runtime to the existing `catch %(?code *detail)` in
`_evaluate_meta_value` and is reported at the call site. The two
`call-stack` arms (step budget, depth) no longer fire for native bodies;
a runaway native body hangs as a runaway `meta native` body does today.
`check_meta_regions` stays as the one hard error: a body returning the
address of call-scope storage would hand the compiler a dangling
pointer.

**Shipped meta code.** `etc/builtin-macros.x` (the `foreach`, `scope`,
`let`, `lock`, `class`, `auto`, callback-adapter algorithms),
`etc/init.x` (the standard Lisp vocabulary written in x2c),
`etc/lisp-bindings.x`, and the meta bodies of `lib/*.xmacro` that the
compiler itself uses (`var-tags`, `var-unbox`, `varops`,
`native-scalar-types`, `autodiff`, `system-macros`, `lib/protocols.x`,
`lib/meta.x` builders) become compiler units: `src/builtins.x` and
`src/linked-meta.x`, ordinary functions spelled `meta native`,
registered through the `<compiler>` supplier (`$compiler.targets()`,
`src/macros.x:1064-1068`, with its `x2c_` filter widened to the linked
inventory) under the derived Lisp names (`_meta_lisp_name`). A linked row
carries the FNV hash of its definition's source span; an imported
definition binds to the linked row only when the hashes match, otherwise
the file is staged like user code, so editing `lib/autodiff.xmacro` still
works without a compiler rebuild. The E1 probe on this branch
(`src/var-tag-rows.x`) is this route done by hand for one group.

**Imports and workers.** An imported `.xmacro` is one group with one
hash, staged once and loaded once per compiler process. A parent that
loads modules before forking lets workers inherit them
(`Compiler.preload_native_module`); a worker that stages loads for
itself. The eager parent Lisp session (below) is built in
`Frontend.open` before any unit starts.

**REPL.** A submission defining meta code is a group staged per
submission; later submissions' modules link against earlier ones or
re-stage cumulatively. Latency per such submission is one `cc` run
(100-300 ms on a fast host, 2.6 s on the spike's container) against ~1 ms
today; `:lowered` shows C instead of Lisp; `:stats` loses the AUTO
fields. This is the one consumer regression and is Gary's decision.

**Editor.** `x2c editor` answers one query per process; a unit's group is
keyed by the hash, so keystrokes outside meta bodies hit the cache and an
edit inside one pays one staging.

**Platforms.** Native modules are compiled out under `__COSMOPOLITAN__`,
`_WIN32`, `__CYGWIN__` (`src/macros.x:1712-1716`). Shipped meta code is
linked, so every documented build path (the APE seed delegates every
translation to the installed native compiler; Windows is WSL2) keeps
working; a user-defined bodied meta function on a host without `dlopen`
is the one new limitation.

## The evaluator without the machine

Removing the wordcode tier needs one addition first: `lib/lisp.x`'s
evaluator has no tail calls, and without the machine a recursive walk in
`lisp_native_targets` exceeds `LISP_CALL_DEPTH_MAX` (1024), so `lib/lisp.x`
itself fails to translate (measured on this branch). Add a tail-call
trampoline in `_call_lambda_slots` (~60 lines) so a self call in tail
position reuses the frame, and make the depth limit a stack limit. A
per-call-site memo of `defmacro` expansions (~25 lines in `_apply_lambda`,
`lib/lisp.x:2166-2174`; measured 505 -> 186 ms on the macro-heavy case)
replaces what AUTO bought on hand-written Lisp. Measured cost of
evaluator-only translation today: 5-11% on `src/` and `lib/`, before the
lowering goes; the Lisp share that remains after it is `$(...)` glue.

## Removal list

Overestimates on purpose; each row names its gate. Lines are current
`wc -l` or the region's size.

| what | lines | how | gate |
|---|---:|---|---|
| `src/comptime.x` | 3,436 | replace by `src/stage.x` (~530): the retained lifting rules (`_meta_value_type`, `_meta_immutable`, `_meta_refuse_address`, `_meta_data`, 3130-3310), `check_meta_call` (3311-3321), the layout helpers a struct result needs (3330-3435), reachability scan, group emission, cache, load, reset; `lower_meta_initializer` (3089, used at `src/macros.x:1578`) becomes the reset entry | fixtures `.c/.h` byte-identical; `meta-*` fixtures; `comptime-declines-*` become acceptances |
| `etc/comptime.xlisp` | 399 | delete; its client was lowered x2c | check-reference-lisp |
| `etc/builtin-macros.xlisp`, `etc/init.xlisp`, `etc/lisp-bindings.xlisp` (generated), `tools/gen-lisp-init.py`, the `$builtin.emit`/`$init.emit` collectors | 9,234 + 53 + 50 | delete; `etc/builtin-macros.x`, `etc/init.x`, `etc/lisp-bindings.x` become `src/builtins.x` and `lib/lisp-init.x` (runtime `Lisp.new` keeps its vocabulary through ~27 `(def name (bind "name" nil))` rows in `etc/init-core.xlisp`) | stage comparison; `make examples`; `lisp_suite` |
| `lib/lisp-machine.x` | 480 | delete | `lisp_suite`; `test-lisp-auto.x` retired (995) |
| `lib/lisp.x` AUTO region (2303-2957), machine bridge (107-300), speculation (1855-1910), slots and AUTO typedefs, comptime-only natives (1104-1270), frame bookkeeping | ~1,200 | delete; add trampoline and memo (+85) | `lisp_suite`; check-reference-lisp with `init-core` and `lisp-values` as standing inputs |
| `lib/machine.x` Lisp half (`LispFrame`, `LispMachine`, `MACHINE_CALL_RESERVE`, `MACHINE_LOCAL_*`, `MW_L*`) | ~140 | delete; the file becomes Match-only | `machine_suite`, `match_suite` |
| `lib/lisp.x` hand target rows (1607-1808) | ~100-150 | generate from the native-meta target table where a `meta native` spelling exists (the lifetime certifier, `src/macros.x:1926-1939`, bounds this) | `lisp_suite` |
| `etc/lisp-values.xlisp` derivable rows | ~165 | generate from the target table | check-reference-lisp |
| `etc/builtin-core.xlisp`, `etc/compiler-sdk.xlisp` argument checks | 34 + ~15 | aliases become template renames in `etc/builtin-macros.xmacro`; a native signature checks itself | fixtures |
| `src/macros.x` shared-library lifecycle flags, `<lisp-late>` restart-by-exception (1000-1281), comptime install/evaluate plumbing (`install_meta_function`, `lower_meta_expression` callers) | ~370 | build the parent session eagerly in `Frontend.open` (~650 Lisp lines to evaluate instead of ~9,900), freeze, adopt per unit; delete the deferred fill, the restart, `collect_forget_preload_entries` (`src/frontend.x:288-339`), `DiagnosticsHold` (`src/diagnostics.x:77-108`), `main.x` restart paths (107-118, 174-182, 371-379) | translation of a small unit within 1.1x; `run-cli-boundary.sh` |
| `src/macros.x` meta import replay (1350-1365), Lisp call-budget arms (2194-2201), `x2c_comptime_lower` (956) and its `lib/meta.x:315` declaration | ~60 | delete; lowered definitions are no longer session-bound; three callers were the generators | fixtures |
| `src/regions.x` `lowered_meta_regions` replay (1239-1246) and `Compiler.meta_regions` fill from the lowering (`src/comptime.x:2970`) | ~15 | delete the replay; keep the analyzer and the meta hard error; the native-row summary path (`src/macros.x:1931`) still fills the map | `regions-*` fixtures |
| `src/compiler.x` lowering caches, `meta_layouts` and its `SymTxn` row | ~40 | delete with the lowering | fixtures |
| `commands/repl/repl-session.x` `lower_repl` path (490-507), `repl.x` AUTO stats and call budget (126-140, 368-371) | ~80 net | stage submissions as modules; `:lowered` prints C | REPL probe; Gary's decision on latency |
| documentation: the compile-time subset and its rejection table (`docs/src/guide/meta-functions.md` "The compile-time subset", `language.md:1717-1723`), "Native modules" reworded as the automatic path, `x2c_comptime_lower` paragraph, `plans/macro-sdk-and-system-macros.md` references | doc-check | rewrite | `doc-check` |

Total removable by this change: about 5,900 hand-authored lines net of
`stage.x`, the builtins unit, and the evaluator additions, plus 9,234
generated lines, the generator, and 995 lines of AUTO tests.

## Also strip or consolidate (independent of the engine, from the reviews)

Overestimates; each is a separate small change with its own gate.

| what | lines | how |
|---|---:|---|
| `src/transform.x` + `lambda.x` + `cleanup.x` as one lowering walk with a per-node fixed point; `c.fixed` memo, sibling rounds, the cleanup skeleton, two cache-id walks (`src/cache.x:504-558, 588-634`) go | 250-1,000 | `src/lower.x`; expected faster; `.transform` sidecars change shape |
| private emitter node kinds (`try`, `defer`, `vcompound`, `vpostfix`, `vseqcall`, `dstrvalue`; `src/emit.x:511-712, 1300-1325`) emitted as ordinary AST | 50-230 net | lower.x builds C-shaped AST; emit.x loses the cases |
| two top-level dispatchers (`_shallow_parse_loop` `src/compiler.x:1669-1744` vs `parse_top_level` `src/parse.x:1953-2032`) | 130 | one classifier with a skip-body continuation |
| `SymTxn` copy-on-begin (`src/compiler.x:2545-2661`) | 70-100 | environment frames; O(1) begin |
| four typedef-chain walkers (`src/compiler.x:3557, 3584, 3724, 3743`), `Sym.declare` vs `Sym.bind_identity` (3213-3263) | 65 | one walker, one facts helper |
| six adapter memo sites (`src/lambda.x:236, 496, 577, 645, 703, 786`) | 60 | one memo helper |
| `convert_expression` (`src/expressions.x:4053-4378`) | 60-175 | an ordered rule list in the documented order |
| the 33 `<macro-expr>` resolver sites and deferred typing state | 60-190 | templates held as unresolved syntax |
| CLI: `_apply_option` switch (894-984) and package switch (1013-1032) | 65 | setter column in the option table; help text and response files stay byte-pinned |
| `src/build.x` fingerprint spellings (315-340, 551-563, 582-591, 1010), `src/utils.x:287-294` vs `build.x:99-119` | 70 | one identity hash |
| `src/project.x` per-field setters (219-275) | 40 | field table |
| JSON and text diagnostic renderers (`src/diagnostics.x:212-284`) | 15 | one field-to-Var pass |
| `lib/array.x:64-460` and `lib/map.x:114-445` | ~1,000 | instantiate `$array.typed.family` / `$map.typed.family` with three hooks; gate: `bm-var` map-get, `bm-varops`, hash-table compare within 1.1x |
| error record: one Scope plus two Pools per record (`lib/error.x:579-585`); five value-transfer copies (`error.x:605, 751; logger.x:549; context.x:267; list.x:95`) | 300, then up to 730 with a frame-chain merge that needs its own prototype | one-Pool record; one `Var.transfer` walk |
| three recursive-mutex `pthread_once` blocks (`error.x:76-104, logger.x:109-137, dispatch.x:254-282`) | 56 | one primitive beside `lib/mutex.x`, recursive only where documented |
| `Context` export arms (`lib/context.x:194-284`) | 20 | fold identical arms |
| `lib/match-recursive.x` | 445 | relocate under `unittest/` as the oracle (consumers: test-support.x, test-match-plan.x, the benchmark) |
| `MatchCache` LRU, leases, generations (`lib/match.x:2002-2460`) | 80-480 | a private direct-mapped plan table; gate: `run-match-cache-benchmark.sh` hit <= 1.1x, cold <= 1.3x; the admission memos stay (measured 2.35x) |
| `lib/autodiff.xmacro`, `lib/autodiff.x` | 1,566 relocated | to `packages/autodiff`; only reference is the include at `lib/lisp.x:36`; their fixtures leave `make check` (Gary's decision) |
| `ScopeStats.largest_request`, `.peak_live_requested_bytes`; `Var.parse`; alias methods `List.subseq`, `Array.indexof`; public `Var.fallback_*`, `Var.wide_*` | ~200 | delete or make private; module pages change |
| legacy macro body forms (`language.md:808-820`, `src/macros.x:3073-3096`) | 35 | retire; fixtures only |

Not to remove, confirmed on reading: `src/regions.x` (one analyzer, three
entries, and the meta hard error guards the compiler's memory); the
native-meta inventory (`src/macros.x:478-568`, live consumers); the Match
admission memos; the freeze/thaw and `.xi` serializations (layers, not
copies); the compiled Match engine (the reference matcher alone measured
1.9-2.0x on whole translation).

## Order of work

1. Staging prototype on the existing native-module path, no removal:
   group, trigger, cumulative emission, cache, reset entry, the `$`
   inside-a-body rule. Prove it on one unit with mutually calling meta
   functions, a `meta static`, a compiler-operation call, a raise, and a
   struct result; on an imported `.xmacro`; on two workers. Measure
   per-edit cost and REPL latency. Gate: `make verify-fixtures` unchanged.
2. Shipped meta code into `src/builtins.x` and `src/linked-meta.x` with
   hash-checked linked rows; the E1 probe is the template. Two builds
   with a bootstrap refresh between them (the checked-in bootstrap must
   carry the capability before the `.xmacro` files can rely on it).
3. Switch every bodied `meta` function to the native path; delete the
   lowering rows of the removal list; rewrite the docs and the 18
   fixtures. Gate: `agent-pr-check`, stage comparison, `make examples`.
4. Evaluator: trampoline, memo, AUTO and `lisp-machine.x` out,
   `machine.x` Match-only, eager parent session, lifecycle and restart
   out. Gate: `lisp_suite`, check-reference-lisp, translation within
   1.1x of the step-3 baseline.
5. REPL staging, then the independent consolidations above in any order,
   each with its named gate.

## Decisions for Gary

- REPL submission latency and the loss of `:stats` AUTO fields.
- The language rule that `$f(x)` inside a meta body is a plain call
  (today it is evaluated through the session; no documented program
  changes meaning, but it is a statement in the reference).
- Withdrawing `x2c_comptime_lower` and the compile-time subset as a
  documented boundary.
- Autodiff to `packages/`, and the small public-surface drops.
