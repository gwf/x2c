# Design: Lisp-first (key: lisp)

Research spike, 2026-09-26. Stance: "it could all come down to having a
better Lisp implementation or a better compiler for it." Read-only; nothing
here is a decision. Line counts are `wc -l` on current dev; citations are
file:line in current source unless marked as the map's.

## 1. Thesis

The better compiler for compile-time x2c is the x2c compiler. Today a `meta`
function is not compiled; it is re-interpreted: src/comptime.x (3,435 lines)
translates its typed AST into Lisp that re-implements C inside the evaluator
(usual arithmetic conversions in `C.conv`/`C.compare`, etc/comptime.xlisp:
14-25; structs and pointers as native bytes through `lisp_peek`/`lisp_poke`,
lib/lisp.x:1204-1237; `defer` through `lisp_unwind`, lib/lisp.x:1260; loops
as tail calls, src/comptime.x:5-16; struct layouts computed a second time,
src/comptime.x:3327-3435), and then lib/lisp-machine.x plus the AUTO half of
lib/lisp.x (2303-3023) word-compile that Lisp to win back speed. The
built-in macros are x2c too (etc/builtin-macros.x, 684 lines) but reach the
compiler only as an 8,719-line generated Lisp artifact loaded from disk by
every process (src/macros.x:1054-1060, 1246-1270). The whole apparatus exists
so that x2c can run inside the compiler without being compiled by it.

The design compiles it instead. Every bodied `meta` function is translated
to C by the ordinary backend, compiled to a shared object, and loaded through
the native-module path that already exists (src/macros.x:1702-1709 dlopen +
`x2c_module_targets`; src/build.x:450-491 entry generation; docs/src/guide/
meta-functions.md:421-533). A meta function and a compiled function are then
the same thing, the "compile-time subset" (meta-functions.md:748-990) becomes
all of x2c, and comptime.x, comptime.xlisp, lisp-machine.x, the Lisp half of
machine.x and the AUTO/speculation tier of lisp.x are deleted. What remains of
Lisp is one small evaluator at the scale of examples/programs/literate-lisp.x
(1,000 lines with prose; ~1,300 lines in production form) serving `$(...)`
glue, `$lisp.bind`, imports and macro templates, checked by the existing
differential checker. The built-in macro algorithms are compiled into the
compiler as an ordinary src/ unit and registered under their Lisp names by
the `<compiler>` native table that already registers `x2c_*` operations
(src/macros.x:1064-1077, 1138-1143), so no .xlisp is generated at all.

This is option (a) with (b) as the shape of the survivor. Option (c),
quasiquote lowering plus one shared evaluator core, is rejected as the
primary: it shrinks the generated artifact (197 `%(` templates in
builtin-macros.x lower to 862 `(cons` and 1,057 `(quote` forms), but
generated lines do not count (brief), and it keeps the reinterpretation
layer that is the actual cost. Honest scale: Lisp-first removes about
8,000 hand-authored lines (10%), plus the 8,719-line artifact and its
generator, and lifts every documented rejection of the compile-time subset.
It does not by itself make the tree "substantially smaller"; section 2 says
why the compiler's own passes stay where they are.

## 2. Architecture

Components and the representation each owns, source to C:

1. Tokenizer (lib/tokenizer.x), collection (src/collect.x), parse
   (src/parse.x, statements.x, expressions.x, literals.x): bytes -> canonical
   untyped List AST. Unchanged.
2. Macro expander (src/macros.x): hygienic templates, invocation matching,
   `template.replace` (src/macros.x:3839-3862), hygiene renaming (2499-2576),
   the `x2c_*` SDK operations (147-961). Unchanged in kind; loses the shared-
   library lifecycle (1000-1281), the file-library loader, the native-meta
   inventory's ad hoc rows (478-568), and the comptime install path.
3. Meta staging (new src/stage.x, ~300 lines): when a `meta` definition with
   a body is installed (src/parse.x:2014), it is recorded; when an invocation
   first needs it, the group of same-file meta functions it reaches is
   emitted as C by the ordinary transform/emit pipeline, compiled to a
   shared object in the build cache, loaded, and its functions bound as
   native targets. Same-file use in source order therefore keeps today's
   semantics: a decorator defined at line 10 and applied at line 30 stages
   once at line 30. Imported `.xmacro` files stage as one module per file,
   content-addressed by file hash, transitive imports, flags and compiler
   stamp (src/build.x:75-181 already keys artifacts this way; src/script.x
   already caches a built executable by fingerprint).
4. Kernel Lisp (lib/lisp.x, ~1,300 lines): reader over the shared Tokenizer
   (today lib/lisp.x:547-830), evaluator with the ten special forms
   (lib/lisp.x:385-389), free-name capture, session parent/adopt/freeze
   (lib/lisp.x:770-799), natives applied through `Func_apply`, the generated
   native target table. No wordcode.
5. Compiled builtins (new src/builtins.x, ~615 lines): today's
   etc/builtin-macros.x and etc/init.x algorithms, minus their emit/write
   collectors (etc/builtin-macros.x:1-25, etc/init.x:1-25) and the
   `$builtin.emit()` markers, compiled into the compiler and registered
   under `foreach.expand`, `scope.expand`, `class.*`, `member`, `assoc` and
   the rest through the compiler target table. etc/builtin-macros.xmacro
   (57 lines, embedded at src/macros.x:43) is unchanged: its templates call
   `$(foreach.expand ...)` exactly as now (etc/builtin-macros.xmacro:14-23).
6. Resolution and conversion (src/expressions.x), protocols (src/protocol.x),
   types and symbol table (src/type.x, compiler.x): unchanged. The meta-call
   case in `_resolve_content` (src/expressions.x:2062-2065) evaluates through
   the session as today; the callee is now a native `Func`.
7. Transform (src/transform.x fixed point 1776-1801), lambda.x, cleanup.x,
   regions.x: unchanged. `check_meta_regions` (src/regions.x:1237-1255)
   keeps its hard-error role; the compile-time lifetime rule ("a compile-time
   call frees its locals when it returns", src/regions.x:19-21) is exactly
   the native-module handle rule (meta-functions.md:467-478), so one rule
   now covers both.
8. Backend (generate, cache, emit, format, diagnostics): unchanged. It gains
   one caller: stage.x emits a function group through it.
9. Driver: build.x's `Build.module_entry` (src/build.x:479-491) and toolchain
   compile the staged object; the `.xlisp` load list and gen-lisp-init.py
   disappear; `bootstrap-refresh` (Makefile:228-234) drops its first line.

Kernel versus macro/meta. The brief asked how much of interpolation,
destructuring, foreach, with, match, defer/raise, lambda lifting and Var
operator lowering should move into Lisp or meta x2c. Answer: none of the
typed ones, and the design says so as a finding against the first
hypothesis. Each of those passes consumes facts only the compiler has:
interpolation boxes segments by type (src/transform.x:1055-1100);
destructuring reads element types (408-550); `match` declares typed capture
locals with compiler-issued binding identity (src/statements.x:246-425);
defer/raise wire cleanup regions and `volatile` rules (src/cleanup.x:
242-624); lambda lifting needs capture analysis over binding identity
(src/lambda.x:1309-1340); Var operators resolve protocol members
(src/transform.x:587-940). All of it is already x2c over Lists written with
match templates; moving it behind a `meta` marker or into a macro would
change the file it lives in, not its size, and would run it after parse
instead of after typing. The kernel boundary stays where the map draws it:
binding, types, layout, lifetimes, emission order. What does move: nothing
new needs to, because the things that belong at macro time (foreach, scope,
let, lock, auto, class, switch, dedent, todo, assert, callback adapters,
foreign aliases) are already macros or meta functions; the design makes
them compiled rather than interpreted. `with` stays a two-line parse-time
binding (src/statements.x:522-530).

## 3. Compile-time execution model

Meta functions. `meta T f(...) { ... }` is parsed, typed and region-checked
as today (src/parse.x:2014, src/macros.x:2045-2048). Its runtime form is
emitted with the unit as now unless it reaches a compiler query
(`meta_comptime`, lib/meta.x:16-21); reachability is a callee scan over the
typed body (~40 lines in stage.x, replacing `lower_reached_meta`,
src/comptime.x:3070-3076). Its compile-time form is the same C, compiled
into the unit's meta module. A `$f(args)` call resolves through the session
to the module's `Func` and applies it with the typed adapter that
`lisp.native.targets` already generates for prototypes (lib/lisp.x:
1607-1619; src/macros.x:1064-1069), so `$(f args)` from Lisp keeps working.
Constant-argument folding (M5) becomes an ordinary native call. There is no
compile-time subset: unions, bitfields, `goto`, `try`/`raise`, `File.open`,
static arrays and every row of the rejection table (meta-functions.md:
948-963) simply compile. The twenty `comptime-declines-*` fixtures pin
rejections that become acceptances; they are diagnostic-wording fixtures of
a limitation, not behavior a program can observe, and are listed in
section 9.

Staging cost, concretely. A unit that defines no bodied meta function and
imports no `.xmacro` with one pays nothing. A cache hit costs one `dlopen`
(~1 ms) plus ~10 us per bound function, versus today's re-parse, lowering
and evaluation of the import in every unit (0.3 ms per declaration,
plans/archive/comptime-x2c-generalization.md:503-506). A cache miss costs
one in-process translation of the group (~10-30 ms) plus one `cc -O1 -fPIC
-shared` of a small file (~60-150 ms), once per changed source per compiler
stamp. Modules are stamped by the compiler that built them, as today
(meta-functions.md:516-523), so each bootstrap stage rebuilds them.
Self-use inside one unit (a decorator defined and applied in the same file)
stages once per first-use point, typically one per file. `meta static`
values are per-unit state today (lib/autodiff.xmacro:19-22; `C._meta_globals`
reset at src/macros.x:1048-1051); a module keeps them as C statics, so the
generated entry exports `x2c_module_reset()` which re-runs the group's
initializers in a fresh per-unit meta Scope at unit start. Builds already
translate one unit per forked worker (src/utils.x:373; src/main.x:329-331),
where module statics are naturally per unit; the reset covers in-process
multi-unit translation.

`$(...)` Lisp, `$lisp.bind`, imports. `$(...)` at unit level, in macro
bodies and in `${$(...)}` positions evaluates in the unit's session
(src/macros.x:2191); a macro body's hole bindings still reach it through
`_lisp_bindings` (3843). `$lisp.bind`/`$lisp.binding`/`$lisp.install` are
today x2c meta functions in etc/lisp-bindings.x (137 lines) whose Lisp is
generated; they become compiled builtins in src/builtins.x. `$(import
"x.xlisp")` reads the file into the session; `$(import "x.xmacro")` parses
definitions into the importing unit's symbol table and stages that file's
meta group as one module. Cycle detection and replay are unchanged.

Native modules. User modules (`--kind meta-module`, `--native-module`,
package `builds/<name>.module`, `--extension`) and staged meta modules are
one mechanism. `Compiler.load_native_module` (src/macros.x:1723-1735) is the
single loader; the compiler's own operations remain the `<compiler>`
supplier consulted first (src/macros.x:1071-1077).

Hygiene. Unchanged: definition-time renaming of template binders
(src/macros.x:2499-2576), `using` fresh names, the macro stack guards
(3775-3805).

Shared library session. Today `Frontend.preload_macro_libraries` fills a
parent session from five files and a preload of lib/meta.x, and a unit that
needs a session before the parent exists raises `<lisp-late>` and is
retranslated (src/frontend.x:327-339, 288-320; src/main.x:170-181;
src/macros.x:1244-1251). With no files to evaluate and no meta surface to
preload (the builders are compiled), the parent is built eagerly in
`Frontend.open` from the embedded init-core text and the compiler target
table, then frozen and adopted by every unit session as now
(lib/lisp.x:783-799). The lifecycle flags, restart path and
`library_definitions` table (src/macros.x:1000-1281) collapse to a
constructor; the map's 2.3 note recommended exactly this.

Survivors, merges, replacements:

| module | disposition |
| --- | --- |
| src/comptime.x (3,435) | replaced by src/stage.x (~300): group extraction, emit through the backend, build via `Build.module_entry`, load, bind, reset, REPL submission |
| etc/comptime.xlisp (399) | deleted; the `C.*` runtime has no client |
| lib/lisp.x (3,190) | kernel only: reader, evaluator, session, natives, generated target table (~1,300); AUTO, `LispLower`, machine slots, speculation (`_expansion_*`, 34 sites) deleted |
| lib/lisp-machine.x (480) | deleted |
| lib/machine.x (540) | Lisp half deleted (`LispMachine`/`LispFrame`, `MW_L*`, `MACHINE_LOCAL_*`, `MACHINE_CALL_RESERVE`); the Match half folds into lib/match-machine.x (~250 lines kept) |
| lib/match-machine.x (541) | unchanged: Match is 10-12% of translate samples and a runtime hot path |
| lib/match-recursive.x (445) | relocated under unittest/ as the oracle (map 2.9); not a deletion |
| etc/builtin-macros.x + init.x + lisp-bindings.x (987) | become src/builtins.x (~865) compiled into the compiler; the three generators, `$builtin.emit`/`$init.emit`/`$binding.emit` and tools/gen-lisp-init.py go |
| etc/init-core.xlisp (176) | kept, embedded as the Lisp standard source (defmacro/defun/if/and/or/let sugar need quasiquote) |
| etc/lisp-values.xlisp (465) | replaced by the rule already in `_meta_lisp_name` (src/macros.x:1081-1088): every `meta` prototype in lib/ binds as `Type.method`; ~40 lines of exceptions remain |
| etc/builtin-core, compiler-sdk, lisp-bindings-core (90) | deleted; forwarding defs are the target table, argument checks are the native signature |
| etc/lisp-extras, lisp-io (33) | kept |
| examples/programs/literate-lisp.x + check-reference-lisp | become the kernel's differential oracle, as today |

## 4. Feature coverage

Language surface (map section 4):

- kernel, unchanged: C foundation and expression-bodied functions; scalar
  declarations, literals, arithmetic; collection and string literals;
  string interpolation; symbol and atom literals; indexing and slicing;
  method-style calls; postfix chains, sizeof, offsetof, _Generic, va_arg,
  casts, designated initializers, compound literals; generic selection;
  mixed declaration rows; C initializers and static assertions; exact
  Var-tag tests; membership `in`; flat destructuring; Var boxing,
  conversion, operators, dispatch; lambdas and typed callback adapters;
  control flow; `with`; `match` statement and typed capture patterns;
  raise, filtered catch, finally, defer; reference parameters; delegate
  fields; protocols; checked foreign aliases; type-owned initialization and
  shutdown; managed-initializer syntax; named types and declaration
  production; package imports and `name__` prefixing; source files,
  pragmas, script units; indentation syntax; host preprocessing; region
  model and lifetime warnings; structured diagnostics; two-pass
  compilation and `.xi`; editor overlays and queries; stable `x2c_*` entry
  points.
- macro/meta, now compiled: foreach and iterator destination omission;
  system macros ($scope, $let, $lock, $auto, $class, $switch, $dedent,
  $todo, $unreachable, $time, $assert); class declarations; callback
  adapter and foreign-alias decorators; `$lisp.bind`/`$lisp.binding`/
  `$lisp.install`.
- kernel, redesigned: compile-time macros and decorators (definitions,
  holes, result kinds, hygiene, keyword aliasing) keep src/macros.x; meta
  functions (introspection, dual form, constant folding) move from
  lowering to staging; compile-time Lisp `$(...)`, `$(import ...)` and
  native module loading run on the kernel evaluator and the one loader.
- dynamic numeric conversion, truthiness, protocol-backed updates: runtime
  as today.

Runtime library:

- runtime as today: args, array, atom, autodiff (runtime tape), block,
  buffer, common, context, diff, digest, dispatch, error, exception, file,
  func, iter, json, lib, list-selectors, list, logger, map, match and
  match-machine, meta (surface unchanged), mutex, path, pool, process,
  regex, scope, scripting, split, string-classify, string-number, string,
  symbol and symbolset, thread, typed collections and generics, var and
  its ledger/adapters/unbox, varconvert, varops, static-init, clibc,
  cmath, native scalar types, integer ops.
- runtime redesigned: Lisp runtime (reader, session, evaluator) as the
  kernel evaluator; `Lisp.new` still evaluates the embedded standard source
  (lib/lisp.x:752-756), now init-core plus the compiled standard algorithms
  bound as natives, so embedding programs (examples/programs/lisp.x, the
  magic examples) keep the same vocabulary.
- runtime redesigned: wordcode machine becomes the Match-only machine
  inside match-machine.x; `MachineBuilder`/`MachineProgram`/`MachineView`
  stay as its private types.
- drop (justified): the AUTO tier and its public API, `Lisp.auto_prepare`,
  `auto_disable`, `auto_instrument`, `auto_stats`, `Lisp.program`,
  `LispAutoStats` (docs/src/library/modules/lisp.md:358, 574-598, 667,
  1095), unittest/test-lisp-auto.x (36 tests) and
  unittest/benchmarks/lisp-auto-benchmark.x. Justification: compile-time
  Lisp is 1.7-2.7% of a translate's samples after the lowering engine
  (plans/archive/comptime-x2c-generalization.md:1034-1035) and drops
  further when meta code is native; the tier's acceptance gate only
  requires prepared/evaluator <= 0.90 (unittest/benchmarks/
  run-lisp-auto-benchmark.sh:7-9), so its guaranteed benefit is 10%; its
  API exists to observe a transparency contract that a deleted tier
  satisfies vacuously. Lines: 480 (lisp-machine) + ~290 (machine.x Lisp
  half) + ~770 (lisp.x 2303-3023 and the `_expansion_*` sites) = ~1,540.
- drop (justified): reference matcher as a shipped module page
  (lib/match-recursive.x, docs "reference matcher"): relocated to
  unittest/ as the oracle; 445 lines leave lib/ but stay maintained.
- drop (justified): the documented rejection table of the compile-time
  subset (meta-functions.md:948-963) and the `comptime-declines-*`
  fixtures. Nothing that compiles today changes meaning; programs that
  were rejected now compile. This is a widening, listed here because
  fixtures pin the old diagnostics.

Tooling: CLI, manifests, incremental build, worker pool, install,
bootstrap payload, script execution, reporting, graph, lint: unchanged.
REPL: its execution path changes (section 9).

## 5. Line ledger

Current lines are the map's subsystem totals (map 2.1-2.13); lib/machine.x
is counted once, in 2.9. "Other" holds the hand-authored lib/src/etc files
the map assigns to no subsystem (lib/protocols.x, error_init, diff, digest,
static-init, generics, system-macros and the rest) so both columns reach
the map's 80,404.

| subsystem | now | after | reasoning |
| --- | ---: | ---: | --- |
| 2.1 front end | 5,341 | 5,300 | `collect_forget_preload_entries` and lisp-late glue go; nothing else changes |
| 2.2 syntax | 6,618 | 6,600 | meta-call/macro-slot cases unchanged; small `lift_macro_lisp_expression` trim |
| 2.3 macros and comptime | 8,818 | 5,130 | comptime.x 3,435 -> stage.x 300 (reference: build.x:450-491 + script.x fingerprint cache + `install_meta_function` already do the parts); macros.x 4,160 -> 3,700 (lifecycle 1000-1281, file loader, inventory rows 478-568, comptime install); meta.x 315 kept; builtin-macros.x+xmacro 741 -> 672 (collectors and emit markers); init.x 166 -> 140 |
| 2.4 Lisp and machine | 5,338 | 1,917 | lisp.x 3,190 -> 1,300 (reference: literate-lisp.x 1,000 with prose covers reader, eval, quasiquote, macros, natives; production adds session API, generated table, error contracts); lisp-machine 480 -> 0; comptime.xlisp 399 -> 0; lisp-values 465 -> 40; init-core 176 kept; bindings.x 157 counted in 2.3; core/sdk/extras/io 123 -> 33; x2c-payload 348 kept |
| 2.5 transforms | 5,542 | 5,542 | untouched by this design |
| 2.6 backend | 4,141 | 4,141 | untouched; one new caller |
| 2.7 driver | 6,045 | 6,035 | module entry reused; gen step removed from bootstrap-refresh |
| 2.8 values | 11,454 | 11,454 | untouched; var-tags.xmacro now runs native |
| 2.9 match | 5,232 | 4,497 | machine.x 540 -> 250 folded into match-machine; match-recursive 445 relocated (still maintained) |
| 2.10 runtime infrastructure | 7,638 | 7,638 | untouched |
| 2.11 services | 4,953 | 4,953 | autodiff.xmacro unchanged, now native |
| 2.13 types, protocols, compiler.x | 7,492 | 7,440 | `meta_layouts`, `meta_values`, `meta_comptime`, `native_meta` plumbing and their transaction rows |
| other (not in a map subsystem) | 1,792 | 1,792 | unchanged |
| total | 80,404 | 72,439 | -7,965 hand-authored (9.9%); plus 8,719 generated lines and tools/gen-lisp-init.py (53) deleted; 445 relocated |

Per-file check of the two largest deletions: comptime.x's function
inventory (src/comptime.x:70-3435) is entirely lowering, layout or lowering
cache; its only non-lowering exports are `meta_is_comptime_only`,
`lower_reached_meta` and `lowered_meta_regions` (3018-3089), which stage.x
reproduces from the typed AST. lib/lisp.x's AUTO region is delimited by the
`#define LISP_AUTO_*` block (2310-2330) and `_apply` (2960); the natives
(344-1596) and evaluator (1830-2303) are what the kernel keeps, minus the
comptime-only natives `lisp_cell/address/load/store/bytes/at/copy/zero/
record_result/session_copy/peek/poke/array/source_function/unwind`
(1108-1290, ~180 lines) whose only client is lowered code.

## 6. Performance ledger

| dimension | expected change | payoff | measured by |
| --- | --- | --- | --- |
| build-cost score (cycles per source line, translator + cc) | +5% to +12% on a clean stage: ~15 meta modules (var-tags, autodiff, system-macros, meta.x builders, the fixture and test importers) each cost about one more small C file to compile, once per compiler stamp; translator cycles fall by the compile-time Lisp share (1.7-2.7%) and the per-unit import lowering | 4,000 lines of reinterpreter deleted; the subset becomes all of x2c | `make bm-build-scaling` against unittest/benchmarks/build-scaling-baseline.json (464,833 cycles/line) |
| per-unit translate, steady state | -1% to -3%: import of a meta `.xmacro` is a cached dlopen instead of parse + lower + evaluate (0.3 ms/declaration today) | faster incremental builds | translation CSV (unittest/benchmarks/run-compiler-translation.sh) |
| per-unit translate, cold cache | +100-200 ms per changed meta source (in-process translate + `cc -O1 -fPIC -shared`); fixtures: ~409 meta-bearing fixtures pay it once per rebuilt compiler, +15-40 s on a cold `verify-fixtures` | same | wall time of `make verify-fixtures` cold vs warm |
| macro expansion time | expansion share 9.6-13.1% -> ~8-10%: the Lisp glue call becomes a native call; template.replace, invocation match and bind_syntax dominate and are unchanged; one foreach expansion 800 us -> est. 400-600 us | same | `sample` share table as in comptime-x2c-generalization.md:1031-1036; marginal cost of 100 foreach expansions |
| generated-code speed | none: same backend, same runtime | - | shootout, bm-all |
| runtime hot paths: Var ops, Match, Scope/Pool, errors | none: match-machine.x, varops, scope, pool, error untouched | - | bm-all |
| runtime Lisp (embedding programs) | 1.0x-1.5x slower on hot lambdas without AUTO; the tier's own gate guarantees only a 10% gain, and the plan record shows word compilation of 698 programs costs 6.8 ms of a 970 ms translation (plans/archive/meta-functions.md:570-573) | -1,540 lines, one execution model | the evaluator lane of run-lisp-auto-benchmark.sh before/after; examples/programs/benchmark-reference-lisp.py |
| compile-time execution of meta code | 10x-100x faster: a 104-row ledger scan costs ~13 ms through the evaluator (comptime-x2c-generalization.md:507-509); native is microseconds. The var-tags decline (3.07 s vs 10.48 s on lib/, section 6 of the map) was caused by evaluator execution and no longer applies | ledger and autodiff run at C speed; meta code can be written naturally | re-port lib/var-tags.xmacro's row lookup and translate lib/ (the plan names this as the settling measurement, comptime-x2c-generalization.md:526-528) |
| process startup | -5 to -15 ms: no five-file library evaluation (9,500 lines of Lisp text parsed per process today) | - | ordinary startup lane (29.1-29.7 ms today, lisp-to-x2c-migration.md:132) |
| REPL submission latency | +100-200 ms (compile and load) instead of ~1 ms lowering | full x2c in the REPL; no subset | wall time per submission |

Nothing here approaches the 2x rope except REPL latency, which is a
different kind of cost and is named.

## 7. Bootstrap plan

The checked-in bootstrap compiler is stage 0 and consumes the new source
unchanged: there is no syntax change, and the new compiler's own use of
`foreach`, `$scope`, `match` and meta functions is expanded by the old
compiler's Lisp path as today. Once built, the new stage-0 compiler
translates lib/ and src/ for stage 1: a lib unit that imports
lib/var-tags.xmacro (lib/var-ledger.x, src/type-ledger.x) triggers a module
build with the stage-0 compiler, whose runtime the module links against
through the executable's exported symbols (builds/stage.mk:47-56 already
links the whole archive with `-rdynamic` for native modules). Stages 1-3
repeat this with their own compilers; modules are build intermediates in
the stage's cache directory and are not part of the C/H comparison. The
bootstrap directory keeps holding generated C for src/ and lib/; the
compiled builtins are ordinary src/ C in it, so no `.xlisp` needs to exist
in a fresh tree. `bootstrap-refresh` (Makefile:228-234) loses its
gen-lisp-init line and nothing else.

The compiler's own builtin macros compile the compiler that defines them:
src/builtins.x uses `foreach`, and the stage-N compiler that translates it
already carries the compiled expander from stage N-1, exactly as the
current compiler carries its builtin Lisp today. The circularity is the
ordinary self-host loop, not a new one.

Parts that must exist before self-hosting: the kernel evaluator (so
`$(...)` and templates work), src/builtins.x with its target registration,
and stage.x (so lib/var-tags.xmacro and lib/meta.x's bodied builders run
during the stage-1 lib build). Nothing else is on the path.

Migration order if staged on the current tree, each step gated by
agent-pr-check and the differential checker:

1. Kernel Lisp: delete the AUTO tier, machine slots and speculation from
   lib/lisp.x and lib/lisp-machine.x; move match-recursive.x under
   unittest/; fold machine.x into match-machine.x. Validated by
   test-lisp.x (65 assertions), check-reference-lisp, test-match.
2. Compiled builtins: src/builtins.x registered through the compiler
   target table; delete etc/builtin-macros.xlisp, init.xlisp,
   lisp-bindings.xlisp, builtin-core, lisp-bindings-core, compiler-sdk and
   tools/gen-lisp-init.py; embed init-core. comptime.x still serves user
   meta functions at this point. Validated by stage-diff and fixtures.
3. Staging: src/stage.x; `install_meta_function` stages instead of
   lowering; `meta static` reset; REPL moved to staged submissions; delete
   comptime.x, comptime.xlisp, the comptime-only natives, `meta_layouts`
   and the lifecycle/restart machinery. Validated by the 409 meta-bearing
   fixtures with the `comptime-declines-*` expectations updated, the
   autodiff suite and examples, and the REPL probes.
4. lisp-values.xlisp replaced by the prototype-derived table.

Steps 1, 2 and 4 are independent of 3 and deliver on their own.

## 8. Language changes

None. The design widens what a `meta` body may contain; every program that
compiles today keeps its meaning.

## 9. Risks and unknowns

- REPL. commands/repl/repl-session.x:490-503 calls `Compiler.lower_repl`
  and evaluates the forms in the session; `:lowered` and `--dump` show
  lowered Lisp (repl.x:39, 297). The consumer surface the brief protects
  changes: submissions become staged modules that link against earlier
  submissions' symbols, and persistent values move from `C._globals` to
  module statics in the session Scope. A bounded change to a consumer that
  is not rebuilt, and the largest single risk of the design; latency per
  submission rises to 100-200 ms. Not verified: whether `dlopen` symbol
  resolution across successive submission modules handles redefinition the
  way the REPL's replace-a-definition flow needs.
- `meta static` per-unit reset. The generated `x2c_module_reset` must
  re-run file-scope initializers; the emitter's static-init path
  (lib/static-init.x, `init_fn` in src/generate.x) runs once by
  constructor today. Not verified that re-entry is a small change.
- Cold fixture cost. +15-40 s on a cold `verify-fixtures` after a compiler
  rebuild is an estimate from cc timings, not a measurement; if `cc -O0`
  for meta modules keeps it under ~20 s it is noise on the gate, which
  already rebuilds stages 0-3.
- Diagnostic wording. Roughly twenty `comptime-declines-*` fixtures and the
  Lisp-boundary argument checks (etc/compiler-sdk.xlisp:11-19) change
  wording or disappear; fixtures pinning wording may change per the brief.
- Runtime Lisp speed without AUTO is bounded above only by the tier's own
  gate; the real ratio on the reference benchmark cases is unmeasured.
- Refutation. The thesis fails if a meta function must observe compiler
  state that a separately compiled module cannot reach; every `x2c_*`
  operation in lib/meta.x is an exported compiler function today
  (src/macros.x:147-961), so no such case is known. It also fails if the
  staged-module cache misses in steady state (for example because the
  stamp changes per build rather than per compiler binary); the stamp is
  `build_module_stamp()` of the running compiler (src/build.x:480), which
  is stable per binary.
- Not read: lib/lisp.x 1290-1596 (adapter rows) in detail; the exact split
  of `MachineBuilder` between Match and Lisp use; commands/repl beyond the
  cited lines.

## 10. Claims

1. src/comptime.x exists only to run x2c inside the evaluator: its 100+
   functions are lowering, layout or lowering cache (src/comptime.x:70-3435);
   struct layouts for compile-time bytes are computed there
   (3327-3435); its C-semantics runtime is etc/comptime.xlisp:14-45 and
   lib/lisp.x:1108-1290.
2. Native modules load and bind like compiler-linked functions:
   src/macros.x:1702-1709 (dlopen/dlsym `x2c_module_targets`),
   1723-1735; src/build.x:450-491 writes the entry; docs/src/guide/
   meta-functions.md:421-533; the compiler links its whole runtime and
   exports symbols for modules (builds/stage.mk:47-56).
3. The compiler already registers its own compiled functions under Lisp
   names as the `<compiler>` module (src/macros.x:1064-1077, 1138-1143), so
   compiled builtins need no new binding mechanism.
4. The .xlisp libraries are read from disk per process (src/macros.x:
   1054-1060, 1257-1270); only init.xlisp (lib/lisp.x:85-86, 383) and the
   two .xmacro texts (src/macros.x:40-43) are embedded.
5. Compile-time Lisp is 1.7-2.7% and macro expansion 9.6-13.1% of translate
   samples; Pool_lookup is 28.6-30.4% (plans/archive/
   comptime-x2c-generalization.md:1031-1036).
6. The AUTO acceptance gate is prepared/evaluator <= 0.90
   (unittest/benchmarks/run-lisp-auto-benchmark.sh:7-9); word-compiling all
   698 programs of a translation costs 6.8 ms of 970 ms
   (plans/archive/meta-functions.md:570-573).
7. Evaluator execution, not parsing, caused the var-tags decline: one scan
   of the 104-row ledger costs ~13 ms, 40 trivial meta functions cost 12 ms
   per unit, and the plan itself says the row lookup "has to stay Lisp"
   only because of that cost (comptime-x2c-generalization.md:495-528).
8. Lowered x2c ran the autodiff suite 63% faster than hand Lisp
   (plans/archive/lisp-to-x2c-migration.md:127-135); ordinary startup is
   29.1-29.7 ms.
9. The REPL depends on `Compiler.lower_repl` (commands/repl/
   repl-session.x:490-503; src/comptime.x:2915).
10. 409 of 873 compiler fixtures name comptime or meta; about twenty
    `comptime-declines-*` fixtures pin rejections of the subset
    (unittest/compiler-fixtures/).
11. etc/builtin-macros.x is 694 lines with 197 `%(` templates; the generated
    etc/builtin-macros.xlisp holds 862 `(cons` and 1,057 `(quote` forms; the
    generated section starts at line 27.
12. `meta` prototypes already mark 114 lib/cmath.x and 38 lib/string.x
    functions (and more) as compile-time natives; the `_meta_lisp_name`
    rule (src/macros.x:1081-1088) derives their Lisp names, which
    etc/lisp-values.xlisp (465 lines) restates by hand.
13. Builds translate one unit per forked worker (src/utils.x:373;
    src/main.x:329-331); `meta static` state is per-unit today
    (lib/autodiff.xmacro:19-22; src/macros.x:1048-1051).
14. `Lisp.new` evaluates the embedded standard source on every session
    (lib/lisp.x:752-756); etc/init.x's algorithms are already x2c (166
    lines) and etc/init-core.xlisp's sugar needs quasiquote (176 lines).
15. The shared session restart path exists only because the parent is
    filled from files and a meta preload between units (src/frontend.x:
    288-339; src/main.x:170-181; src/macros.x:1244-1251, 1000-1281).
16. Totals: src 41,950 (36 files), lib 35,835 (72 files excluding generated
    lib/x2c.x), etc hand-authored 2,585; the map's 80,404 is reproduced
    within 40 lines.
17. Every typed lowering the brief names reads compiler-only facts:
    src/transform.x:1055-1100 (segments), 408-550 (destructuring), 587-940
    (Var operators), 1123-1420 (defer/raise); src/statements.x:246-425
    (match captures); src/cleanup.x:242-624; src/lambda.x:1309-1340.
