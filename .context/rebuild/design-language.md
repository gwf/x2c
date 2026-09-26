# Rebuild design: licensed language changes (key: language)

Research spike, 2026-09-26. Advice to Gary; nothing here is a decision.
Scope and baseline: the map's hand-authored total, 80,404 lines (map.md:19-22).
`lib/machine.x` (540) appears in both map sections 2.4 and 2.9; this ledger
counts it once, under 2.9. Every `file:line` below was read in current `dev`
unless it says "map".

## 1. Thesis

x2c has two backends. One lowers x2c to C (`src/emit.x`, `src/generate.x`);
the other lowers x2c to Lisp (`src/comptime.x`, 3,436 lines, 160 functions
of expression, statement, loop, switch, initializer, store and cleanup
lowering; grep count at src/comptime.x:70-3434) so that a `meta` body can run
inside the compiler. The second backend then needs its own runtime
(`etc/comptime.xlisp`, 399 lines of `C.*` semantics), its own optimizer
(`lib/lisp.x` AUTO tier, lib/lisp.x:2332-2957, plus `lib/lisp-machine.x`,
480), a 12.7x generated artifact (`etc/builtin-macros.xlisp`, 8,770 lines)
and a lifecycle for sharing the preloaded library across units
(src/macros.x:1000-1281). Meanwhile the library already executes most of its
compile-time surface natively: `meta native` and bodyless `meta` prototypes
(lib/cmath.x:15-18, lib/string.x:228-466, lib/var.x:124-475) run the
compiler's own linked copy, and user code can load compiled modules with
`--native-module` (docs/src/guide/meta-functions.md:421-542, dlopen at
src/macros.x:1702-1709). The one licensed language change that matters
finishes that move: every `meta` body executes natively, compiled by the
only backend and linked into the compiler (shipped) or built on demand and
cached (user code). The x2c-to-Lisp backend, its runtime, its optimizer, its
generated artifact, and the wordcode half of the machine are then deleted,
and compile-time Lisp shrinks to what `$(...)` interop actually needs: a
reader, a tree-walking evaluator, and ~640 lines of Lisp library. Two
smaller changes (retiring the legacy macro body forms; dropping the quoted
`%[...]`/`%{...}` forms) are cheap and included. The other candidates on the
list were measured and declined below; they buy tens of lines each and one
of them (generic selection) has no mechanical migration.

## 2. Architecture

Components, the representation each owns, and pass order. "Kernel" means
the operation needs facts only the compiler has (binding, types, layout,
lifetimes, emission order). "Meta" means an x2c function over canonical
syntax, compiled natively and called by the kernel or by a macro.

| component | owns | kernel or meta |
|---|---|---|
| `lib/tokenizer.x` | bytes -> Token array; mode family (lib/tokenizer.x:484-550) loses the `array`/`map` quoted modes (change L3) | runtime, as today |
| collect + parse (`src/collect.x`, `src/parse.x`, `statements.x`, `expressions.x`, `literals.x`) | canonical AST Lists; one classification step with skip-body and parse-body continuations (map 2.1 note 1) | kernel |
| `src/macros.x` | macro definitions as hygienic templates; invocation claiming at every MacroPos; `$(...)` slot parsing (src/macros.x:1283-1291, 2951-3010); native meta table (src/macros.x:147-961) | kernel |
| meta loader (new, ~150 lines in `src/macros.x` + `src/build.x`) | binds shipped meta modules linked into the compiler; builds, caches and dlopens user meta modules | kernel |
| `lib/lisp.x` (reader + evaluator + natives) | `$(...)` forms, `.xlisp` imports, `defun`/`defmacro`, `$lisp.bind`; one session per unit preloaded from `etc/init-core.xlisp` + `etc/lisp-values.xlisp` | runtime, redesigned (AUTO tier removed) |
| `etc/builtin-macros.x` + `.xmacro`, `lib/*.xmacro` | foreach, scope, let, lock, auto, class, match lowering, var-tags ledger, autodiff, system macros, as x2c meta functions linked into the compiler | meta |
| `src/type.x`, `type-ledger.x`, `protocol.x`, `compiler.x` | `Type` as canonical List; `Sym`; `SymTxn`; protocol registries and adapter synthesis | kernel |
| `src/transform.x`, `lambda.x`, `cleanup.x`, `regions.x` | fixed-point lowering; closures/adapters; defer/try regions; region warnings (one walk, no meta variant) | kernel |
| `src/cache.x`, `generate.x`, `emit.x`, `format.x`, `diagnostics.x` | constants; .h/.c partition; C tokens; #line rendering; diagnostics | kernel |
| `src/build.x`, `toolchain.x`, `main.x`, `cli.x`, `project.x`, ... | fingerprints, workers, publication; plus meta-module cache | driver, as today |

Pass order, source to C, per unit:

1. Tokenize (as today, lib/tokenizer.x:793).
2. Collect declarations (as today, src/collect.x:567), including `meta`
   definitions and `$(import ...)` targets.
3. Meta binding. Every `meta` definition visible to the unit resolves to a
   native entry point: (a) the compiler's own linked functions, which is
   every `meta native` and bodyless prototype in lib/ (today's rule,
   docs/src/guide/meta-functions.md:428-437) and every shipped `.xmacro`
   meta body, compiled into the compiler the way `--extension` links a
   package's compile-time part (docs/src/guide/meta-functions.md:532-542);
   (b) a user meta module, built on demand from the defining sources by the
   ordinary backend, keyed by content hash under `builds/`, and dlopened
   (src/macros.x:1702). Binding is lazy: the module for a unit's own `meta`
   bodies is built at the first `$name(...)` call, batching every meta
   definition parsed so far.
4. Full parse with macro expansion (as today, src/compiler.x:1999). A
   `$name(args)` call marshals resolved constant arguments through
   `lib/func.x` (the adapter shape at lib/lisp.x:1363-1480 already does
   this for Lisp callers) and lifts the result with the existing
   `lift_macro_lisp_expression` rules (src/expressions.x:2081-2084).
5. Protocol adapters, regions, transform, cleanup (as today; regions has one
   walk, `check_regions`, because native meta bodies obey ordinary Scope
   lifetimes, see section 3).
6. Cache, generate, emit, format (as today).

Nothing in the AST, `Type`, macro template, or match representation changes.
`Ast` stays `typedef List`.

## 3. Compile-time execution model

- **Meta functions.** A `meta` function is ordinary x2c compiled by the one
  backend. It is dual-form exactly as documented (language.md:1683-1692):
  the runtime program links its own copy; the compiler runs the linked or
  loaded copy. The compile-time-only inference (a body reaching a bodyless
  compiler operation, an explicit `$` call or a template constructor emits
  no runtime form; language.md:1785-1793) stays as a ~60-line reachability
  pass over resolved call targets, replacing src/comptime.x:47,365-367,2897.
  The "compile-time subset" (docs/src/guide/meta-functions.md:748-1094)
  lapses: unions, every library method, and every control form compile,
  because the body is C. File-scope state rejection for dual-form bodies
  (language.md:1717-1723) stays as a diagnostic on the runtime form.
  `meta static` per-unit copies hold because translation forks one worker
  per unit (src/main.x:220-243); sequential in-process translation reloads
  a module per unit (risk R3).
- **`$name(...)`.** Constant-argument resolution and M5 folding rules stay
  (src/comptime.x:3089-3311 today, ~250 lines retained). The call crosses
  into native code through `Func`; results are marshalled as today.
- **`$(...)` Lisp.** Unchanged surface (language.md:1381-1391). The session
  is `lib/lisp.x`'s reader and evaluator (lib/lisp.x:549-830, 1832-2350),
  preloaded from `etc/init-core.xlisp` (176) and `etc/lisp-values.xlisp`
  (465). Every native meta function and every `x2c.*` operation is bound
  under the documented derived name (language.md:1755-1765) through one
  generated target table; the three-way hand-merged table at
  lib/lisp.x:1607-1808 is replaced by that generated list. `$(foreach.expand
  ...)` in etc/builtin-macros.xmacro:19-22 keeps working because
  `foreach_expand` is bound as a native Func, not because it was lowered.
- **`$lisp.bind` / `$lisp.binding` / `$lisp.install`.** As today
  (etc/lisp-bindings.xmacro, lib/lisp.x:3182); they bind C functions into
  the session.
- **Imports.** `$(import "x.xmacro")` parses macros and meta definitions into
  the consuming unit (src/macros.x:1440-1460) and binds the file's meta
  bodies to a module (shipped: linked; user: built on demand, cached by the
  import's content hash, so a project pays one cc per changed `.xmacro`).
  `.xlisp` imports evaluate as today. Cycle detection and replay unchanged.
- **Native modules.** The existing `--native-module` and manifest
  `native-modules` paths become the general mechanism; the compiler-identity
  check (docs/src/guide/meta-functions.md:508-517) covers on-demand modules
  too, since the cache key includes the compiler fingerprint.
- **Hygiene.** Unchanged: definition-time renaming in src/macros.x:2499-2576
  and `using` binders (etc/builtin-macros.xmacro:19).
- **Shared library session.** With ~640 lines of Lisp to preload instead of
  ~9,900 (init 235 + lisp-values 465 + comptime 399 + builtin-macros 8,770),
  each unit loads its own session sequentially; the parent/adopt/freeze
  hierarchy (lib/lisp.x:770-799) and the `<lisp-late>` restart
  (src/macros.x:1229-1281) go. `def` on an inherited name must still raise
  `(bad-state (why "inherited"))` (language.md:1424-1432): the two preloaded
  files are marked frozen in the single session, which is the existing
  freeze bit without the hierarchy.
- **Survivors.** `lib/lisp.x`: reader, evaluator, natives, session API
  survive; AUTO (2332-2957), speculative pre-expansion (1855-1905), machine
  slots (2800-2830) are deleted. `lib/lisp-machine.x`: deleted.
  `lib/machine.x`: Match half survives (opcodes, builder, MatchMachine
  state); Lisp half (LispMachine, LispFrame, MACHINE_CALL_RESERVE,
  lib/machine.x:262-292 map) deleted. `lib/match-machine.x`: unchanged.
  `src/comptime.x`: replaced by ~350 lines (inference, argument
  resolution, marshalling, module orchestration). `etc/comptime.xlisp`,
  `etc/builtin-core.xlisp`, `etc/compiler-sdk.xlisp`: deleted
  (`compiler-sdk` names move to the generated table). `tools/gen-lisp-init.py`
  and the `$builtin.emit`/`$init.emit` collectors (etc/builtin-macros.x:1-25,
  etc/init.x:1-25, etc/lisp-bindings.x:1-25): deleted; the three files
  become ordinary compiler units.

## 4. Feature coverage (map section 4)

Language surface:

| rows | disposition |
|---|---|
| C foundation, expression-bodied functions; scalar declarations, literals, arithmetic; indexing and slicing; method-style calls; postfix chains, unary, sizeof, offsetof, _Generic, va_arg, casts, designated initializers, compound literals; generic selection; C initializers and static assertions; control flow; reference parameters; delegate fields; checked foreign aliases | kernel, as today |
| mixed declaration rows | kernel, as today (evaluated for dropping, declined, section 8) |
| collection and string literals (percent literals, quote, unquote) | kernel; `%[...]`/`%{...}` dropped under L3 with a mechanical migration, `%(...)`, `%<<...>>`, `%"..."` stay |
| string interpolation; symbol and atom literals; exact Var-tag tests; membership; flat destructuring; Var boxing/conversion/operators/dispatch; dynamic numeric conversion; truthiness; protocol-backed updates; dynamic compound assignment; Var/Null/void triple | kernel + runtime as today |
| lambdas; typed callback adapters | kernel (`src/lambda.x`) + runtime `lib/func.x`, as today |
| foreach and destination omission | macro/meta (already; etc/builtin-macros.xmacro:14-24), now native |
| with statement | kernel-parsed; lowered as a local bare-invocable Expression macro over the existing local-macro machinery (src/statements.x:571-620 and `with_binding` at 522-530, expressions.x:2731 hook collapse to one flag on a local definition); no language change |
| match statement, patterns, typed captures | kernel parse (src/statements.x:303-425, literals.x:154-260); lowering as a meta function in etc/builtin-macros.x replacing src/emit.x:423+254 to 423+440 and src/transform.x:559-573; break/continue semantics preserved by emitting `switch (0) default: {...}`; per-site plans still bound via `x2c_match_site_*` |
| raise, filtered catch, finally, defer | kernel (`src/cleanup.x`, `src/transform.x:1123-1420`) + runtime as today; `defer` cannot be a macro because it needs region wiring and volatile rules (src/cleanup.x:242-624) |
| protocols | kernel, as today (src/protocol.x) |
| type-owned initialization/shutdown; managed-initializer syntax | kernel, as today (src/parse.x:1421-1500) |
| named types, declaration production, class declarations | macro/meta, as today, now native |
| compile-time macros and decorators (local definitions, holes, result kinds, hygiene, keyword aliasing) | kernel (`src/macros.x`); legacy body forms dropped (L1) |
| meta functions (introspection, dual-form, constant folding) | kernel binding + native execution (section 3); `x2c_comptime_lower` withdrawn (drop, justified: its only callers are the three deleted generators, etc/init.x:9, etc/lisp-bindings.x:11, etc/builtin-macros.x:9) |
| inline Lisp bindings; `$(import ...)`; native module loading | kernel + `lib/lisp.x`, as today |
| system macros ($scope, $let, $lock, $auto, $class, $switch, $dedent, $todo, $unreachable, $time, $assert) | macro/meta, as today, now native |
| package imports, `name__` prefixing; source files, pragmas, script units; indentation syntax; host preprocessing | kernel, as today |
| region model and lifetime warnings | kernel, one walk; the meta hard-error variant (src/regions.x:1237-1256) is deleted because native meta bodies allocate in the caller's live Scope |
| structured diagnostics; two-pass compilation, `.xi`, dependency files; editor overlays and queries; stable `x2c_*` entry points | kernel/driver, as today |

Runtime library (module pages):

| rows | disposition |
|---|---|
| args, array, atom, autodiff (runtime tape), block, buffer, common, context, diff, digest, dispatch, error, exception, file, func, iter, json, lib, list-selectors, list, logger, map, mutex, path, pool, process, regex, scope, scripting, split, string-classify, string-number, string, symbol/symbolset, thread, typed families and generics, var/tags/adapters/unbox/ledger, varconvert, varops, static-init/clibc/cmath/native-scalar-types/integer-ops | runtime as today (map 2.8, 2.10, 2.11 consolidations apply but are not language work) |
| autodiff source-to-source (`lib/autodiff.xmacro`) | meta, now native; the 124 `meta static` helpers compile into the compiler |
| Lisp runtime (reader, session, evaluator) | runtime redesigned: AUTO removed (drop, justified: documented as transparent, map 2.4 "AUTO transparency"; the acceptance benchmark's gate is prepared/evaluator <= 0.90, unittest/benchmarks/lisp-auto-benchmark.x:9-11, so the tier's documented value is a >= 1.1x speedup on hot lambdas, and compile-time hot paths no longer run in Lisp) |
| wordcode machine (`lib/machine.x`) | runtime redesigned: Match-only |
| reference matcher (`lib/match-recursive.x`) | runtime as today, moved under unittest/ as the oracle (map 2.9 note) |
| pattern matching (`lib/match.x`, `match-machine.x`) | runtime as today |
| compiler surface for meta functions (`lib/meta.x`) | as today |

Tooling and packaging rows: driver as today, plus the meta-module cache in
`src/build.x` (the `meta-module` kind already exists, src/cli.x:155,879;
src/build.x:450-470 `_write_entry`). REPL: commands/repl/repl-session.x:490
calls `lower_repl` and evaluates the forms in Lisp; under this design each
submission is a meta module (compile, load, call), which is a consumer
change of ~100 lines in repl-session.x and a latency cost (section 6).
graph, lint, torch: unchanged surface.

## 5. Line ledger

"With" is this design (L1 + L2 + L3, plus the map's routine consolidations
that no language change is needed for). "Without" applies only those
routine consolidations, so Gary can see what the licensed changes buy.
Defended by: the deletion accounting in section 3 (comptime, AUTO, machine,
xlisp), the native-module reference implementation already in the tree
(src/macros.x:1633-1720, src/build.x:450-520), and map rebuild notes for
the routine rows.

| map subsystem | before | with | without | reasoning |
|---|---|---|---|---|
| 2.1 front end | 5,341 | 5,150 | 5,150 | one classification step for shallow/full dispatch (-140, map 2.1 note 1); freeze/thaw and `.xi` share one datum writer (-50) |
| 2.2 syntax | 6,618 | 6,340 | 6,420 | `with` as a local bare macro (-70: statements.x:571-620, 522-530, expressions.x:2731); quoted `%[`/`%{` parsers (-80, L3: literals.x:631-645, 691-729 and tokenizer array/map modes); postfix parsers and cons duplication (-45, map 2.2); the rest as today |
| 2.3 macros and comptime | 8,818 | 5,010 | 8,500 | comptime.x 3,436 -> 350 (section 3); macros.x 4,160 -> 3,600 (library lifecycle and `<lisp-late>` restart -220, src/macros.x:1000-1281; legacy bodies -35, L1, src/macros.x:3073-3096, 3277-3288, 3337-3341; native-meta inventory -90, src/macros.x:478-568 replaced by the generated table; comptime install/evaluate plumbing -215) plus ~150 for module orchestration; meta.x 315; builtin-macros.x 694 -> 670 + 140 for match lowering; builtin-macros.xmacro 57 -> 67; init.x 166 -> 140; total 350+3,750+315+810+67+140 = 5,432 minus the ~420 of comptime-only helpers that vanish with them = ~5,010. Without: only -220 lifecycle, -90 inventory, -8 collector |
| 2.4 Lisp (hand-authored, machine.x excluded) | 5,338 | 3,105 | 5,000 | lisp.x 3,190 -> 1,900 (AUTO 2332-2957 -625, speculation 1855-1905 -150, machine slots -100, hand target rows 1607-1808 -150, misc -265); lisp-machine.x 480 -> 0; comptime.xlisp 399 -> 0; builtin-core 34 -> 0; compiler-sdk 23 -> 10; lisp-bindings.x 137 -> 120; init-core 176, lisp-values 465, lisp-extras 28, lisp-bindings-core 33, lisp-io 5, lisp-bindings.xmacro 20, x2c-payload.x 348 unchanged. Without: target-table consolidation only (-200, map 2.4 note 5) plus car/cdr folding (-40), speculation kept |
| 2.5 transforms | 5,542 | 5,250 | 5,300 | adapter synthesis helper (-200, map 2.5); meta region variant (-50, src/regions.x:1237-1256 and comptime's `lowered_meta_regions`); match resolve arm (-15) |
| 2.6 backend | 4,141 | 3,900 | 4,090 | match lowering leaves emit.x (-190, src/emit.x:423+254..440, moves to meta at +140 counted in 2.3); diagnostics renderers share a field pass (-50) |
| 2.7 driver | 6,045 | 6,000 | 5,900 | meta-module build and cache (+100 over the existing meta-module kind); CLI table with setters (-60), three readers (-60), fingerprint and hash sharing (-25) |
| 2.8 values | 11,454 | 11,300 | 11,300 | Block/Buffer growth as one generics family (-140), varconvert embedding (-14) |
| 2.9 match + machine.x | 5,232 | 4,450 | 4,600 | match-recursive.x 445 moved under unittest/ (counted here as -445, +445 to tests); machine.x Lisp half (-150, L2 only); MatchCache narrowed to a plan cache (-150, map 2.9, admission memos kept per section 6) |
| 2.10 runtime infrastructure | 7,638 | 7,500 | 7,500 | one recursive-mutex primitive (-87), Context export arms (-40) |
| 2.11 services | 4,953 | 4,850 | 4,850 | mode-parameterized autodiff walker (-100) |
| 2.13 types, protocols, compiler.x | 7,492 | 7,250 | 7,280 | typedef walkers (-35), declare/bind facts (-20), protocol adapter template (-150), `meta_layouts` field and its SymTxn snapshot (-30, L2 only) |
| unmapped small lib/ modules | 1,792 | 1,792 | 1,792 | protocols.x, error_init.x, diff, digest, list-selectors, typed-list, list-generics, string-classify, string-number, static-init, clibc, cmath, native-scalar-types, integer-ops, thread-state, scripting, var-adapters, var-unbox, var-ledger, varops.xmacro, error-private, private-keywords, ast-rewrite (wc above); the map's 80,404 includes them |
| total hand-authored | 80,404 | 71,887 | 77,682 | with: -8,517 (-10.6%); without: -2,722 (-3.4%); the licensed changes are worth ~5,800 hand-authored lines |
| generated artifacts (not counted) | 9,234 | 0 | 9,234 | builtin-macros.xlisp 8,770, init.xlisp 235, lisp-bindings.xlisp 229, and tools/gen-lisp-init.py (53) |

The subsystem sum before is 78,612 plus the 1,792 unmapped row, 80,404.
Honest framing: the licensed changes delete a second compiler backend and
its optimizer, but they do not halve the tree; the parser, type system,
protocols, transforms, emitter and runtime are what they are. Any design
claiming a much larger reduction must find it in those, not in the
compile-time model.

## 6. Performance ledger

| dimension | expected change | payoff | measurement |
|---|---|---|---|
| compile throughput, warm (build-cost score) | -5% to -15% cycles per line: no Lisp session fill of ~9,900 lines per unit, macro algorithms (class, foreach, var-tags, autodiff) run as C; the `src/` and `lib/` columns moved ~4% when the Lisp engine changed before (plans/archive/comptime-x2c-generalization.md:1010-1018), so the ceiling is modest for those trees; test-autodiff-style units gain most | deletes comptime.x, AUTO, machine half | `make performance-snapshot`, build-scaling baseline, translation CSV per unit |
| compile throughput, cold | up to +0.3 s per unit that defines a non-native `meta` body and is not shipped in the compiler (one cc + dlopen, cached by content hash and compiler fingerprint); in this tree the shipped meta files (etc/ 3, lib/*.xmacro 5, lib/protocols.x, src/protocol.x) are linked, so the self-build pays nothing; unittest units defining meta bodies pay once per content change | same | cold vs warm `make check` wall time; must stay under 2x on the cold test build, and the design names that as the accepted cost |
| macro expansion time | faster: native expansion instead of tree-walking or wordcode Lisp; `$(...)` residue unchanged | same | translation CSV macro columns |
| generated-code speed (shootout) | unchanged: same backend, same runtime | none | shootout |
| runtime Var ops, Match, Scope/Pool, errors | unchanged; Match admission memos kept (map section 6 A/B) | none | bm-all |
| runtime Lisp hot lambdas | slower without AUTO, bounded by the tier's own gate: prepared/evaluator <= 0.90 (unittest/benchmarks/lisp-auto-benchmark.x:9-11), i.e. AUTO is documented to buy at least 1.11x; the upper bound is unverified (U2) and must be measured before the drop is accepted; if it exceeds 2x on a real Lisp program, keep AUTO and forgo ~1,250 lines | deletes lib/lisp-machine.x, AUTO, speculation | `run-lisp-auto-benchmark.sh` evaluator arm vs today's prepared arm |
| REPL latency | +100-300 ms per submission (compile, load) versus Lisp evaluation | consumer keeps surface, loses lower_repl | manual timing of commands/repl submissions |
| bootstrap/build orchestration | unchanged fork-per-unit model; one more cached artifact kind under builds/ | none | `make precommit` wall time |

## 7. Bootstrap plan

1. Stage 0 is the current compiler. It already compiles `etc/builtin-macros.x`,
   `etc/init.x`, `lib/*.xmacro` meta bodies and `src/*.x` as ordinary x2c,
   so the new compiler's sources need nothing stage 0 lacks; the `meta`
   marker is parsed by stage 0 and its runtime forms are emitted (or not)
   under today's rule.
2. Build the new compiler with stage 0. Its link set adds the shipped meta
   units as extension units (the `--extension` path,
   docs/src/guide/meta-functions.md:532-542, generalized to a fixed list in
   the Makefile). No `.xlisp` generation step; `bootstrap-refresh`
   (Makefile:228-235) drops the `gen-lisp-init.py` line.
3. Stage 1 compiles the tree with the new compiler: its linked meta functions
   serve the imports of `lib/var-tags.xmacro`, `lib/autodiff.xmacro`,
   `lib/system-macros.xmacro`, `lib/error-macros.xmacro`, and the built-in
   macros; an import whose content hash differs from the linked copy (an
   edited `.xmacro`) builds on demand. Stages 2 and 3 must reproduce stage 1
   C byte for byte; `stage-diff-all` is the check.
4. Order for a staged migration of the current tree, each step gated by
   `agent-pr-check`:
   a. L1 (legacy macro bodies) and the three fixtures; trivial.
   b. Generated target table replaces lib/lisp.x:1607-1808; no behavior change.
   c. Shipped meta bodies linked as extensions while comptime.x still exists;
      `$name(...)` prefers a native binding when one exists (the precedence
      rule already documented at docs/src/guide/meta-functions.md:518-523).
      Run the full suite both ways. This is the step that validates the
      thesis on real code (autodiff, class, var-tags).
   d. On-demand meta modules for user units and imports; REPL moved to it.
   e. Delete comptime.x's lowering, comptime.xlisp, builtin-macros.xlisp
      generation, meta region variant; collapse the library lifecycle.
   f. Drop AUTO and lisp-machine.x after measuring U2; drop machine.x's Lisp half.
   g. L3 percent collection forms, with the migration script run over the
      tree, docs and examples.
   h. `with` as local macro; match lowering as meta; routine consolidations.

## 8. Language changes (licensed)

Each change is small at the language, migrates by script, and does not
change the meaning of a program that still compiles.

**L1. Retire the legacy macro body forms.** What: `macro ... => { ... }`
and `macro Expression ... => (expression)` without a trailing semicolon
(language.md:808-820) stop parsing; the canonical `{ ... }` and
`=> expression;` remain. Migration: a sed pass over `.x`/`.xmacro`: on a
`macro` line, `=> {` becomes `{`; a `=> (...)` line not ending in `;` gets a
`;`. The tree has 6 uses, all in tests and the grammar fixture
(unittest/compiler-fixtures/macro-using-conflict.x:3,
macro-result-missing-kind.x:3, macro-result-legacy-trailing.x:3,
macro-function-style-syntax.x:25, etc/vsc-extension/test/current-grammar.test.x:324,329).
Deletes: `_macro_expression_continues`, `_legacy_expression_body`
(src/macros.x:3073-3096), the `legacy_expression` branches
(src/macros.x:3277-3288, 3337-3341), the doc paragraph, ~35 lines and two
fixtures. Cost to users: one script run.

**L2. Meta functions execute natively.** What: a `meta` body is compiled by
the ordinary backend and executed as native code inside the compiler, linked
(shipped) or loaded on demand (user code), exactly as `meta native` already
is. Language-visible consequences: (a) `x2c_comptime_lower` (language.md:
1767-1770, lib/meta.x:315, src/macros.x:956) is withdrawn; (b) the
compile-time subset restrictions (docs/src/guide/meta-functions.md:748-1094)
lapse, so more programs compile and none changes meaning; (c) compile-time
objects no longer "belong to the evaluator" (language.md:1717-1723): they
are ordinary Scope allocations of the compiler process, and `meta static`
remains one instance per translation unit process; (d) `$(name args)` from
Lisp keeps working through the native binding table. Migration: none for
user programs; the three `x2c_comptime_lower` callers are the generators
this design deletes. Deletes: src/comptime.x lowering (~3,086), etc/
comptime.xlisp (399), etc/builtin-core.xlisp (34), etc/builtin-macros.xlisp
and init.xlisp and lisp-bindings.xlisp generation (9,234 generated + 53 tool
lines), lib/lisp.x AUTO tier and speculation (~875), lib/lisp-machine.x
(480), lib/machine.x Lisp half (~150), the shared-library lifecycle and
`<lisp-late>` restart (~220), the native-meta inventory (~90), the meta
region variant (~50), `meta_layouts` (~30). Adds: ~150 lines of module
orchestration and ~350 of retained call evaluation. Cost to users: a cold
cc per unit or import that defines a non-native meta body; the REPL executes
submissions by compiling them; runtime Lisp loses AUTO (separable, section 6).
Why the declined measurement does not apply: "Var tag row lookup stays in
Lisp" (map section 6, plans/archive/comptime-x2c-generalization.md) compared
x2c-lowered-to-Lisp against hand-written Lisp; native x2c is the third
option that measurement did not cover, and lib/cmath.x, lib/string.x and
lib/var.x already run natively at compile time under today's rules.

**L3. Drop the quoted `%[...]` and `%{...}` forms.** What: the two quoted
collection grammars (language.md:2120-2125) go; the evaluated `[...]` and
`{...}` forms (language.md:2035-2082), `%(...)`, `%<<...>>` and `%"..."`
stay. Migration: a script that re-spells each element by the documented
rule (language.md:2136-2158): numbers, strings, `<sym>` unchanged; a bare
word becomes `<word>`; `$name` becomes `name`; `${e}` becomes `e`; a nested
`(...)` becomes `%(...)`; `%[` becomes `[`, `%{` becomes `{`; map keys keep
their bare spelling because the evaluated form already reads a bare key as
an Atom (language.md:2046-2049). The typed-family destination rule
(language.md:2127-2132) already applies to the bare forms. Uses: 86 `%[` and
98 `%{` in the tree, 32 of them in src/lib/etc. Deletes: literals.x
`_parse_quoted_array_elements` (631-645), `_parse_quoted_map_entry` and
`_parse_quoted_map_entries` (691-729), the `array`/`map` tokenizer modes
(lib/tokenizer.x:484-550 share the atom scanner, so ~25 lines), the table
rows and their doc paragraphs; ~80 lines. Cost to users: the script run and
one fewer spelling to learn. Optional: it is the smallest of the three.

Evaluated and declined (worth stated so nothing is re-litigated blind):

- Unify `$(...)` and `$name(...)`: buys ~0. `$(` parsing is `_lisp_form`
  (src/macros.x:1283-1291) plus ~50 lines of slot rules
  (src/macros.x:2951-3010); the evaluator stays for interop in any case.
  Of the 615 raw `$(` uses, 202 are `$(x2c.*`, which need no change under
  L2, and the other ~410 (`defun` 34, `def` 19, `list` 29, `quote` 13,
  `let` 9, ...) are Lisp programs with no mechanical rewrite to x2c.
- Lisp reduced to a data notation: not mechanically migratable for the
  same reason; L2 gets the deletion without it.
- Quasiquote-shaped templates: moot under L2 (no Lisp emission); as a
  stand-alone change it would shrink the generated artifact ~10x
  (etc/builtin-macros.x:65-66 versus etc/builtin-macros.xlisp:206-215) but
  no hand-authored line, since the parser already builds `(cons ...)`
  chains (src/literals.x:75) that comptime copies one to one
  (src/comptime.x:1362-1365, 1510-1511).
- match/with/foreach/defer as macros over a smaller core: foreach already
  is; `with` and match lowering move without a language change (section 4);
  defer is kernel. Worth ~250 lines total, taken internally.
- Mixed declaration rows: ~50 lines (src/parse.x:1400-1418 and the `seq`
  arms at 1434-1449, 1451-1456); ~300 uses in src/lib (heuristic count);
  the idiom carries readability in this tree. Declined.
- Generic selection: ~60 lines (src/expressions.x:789-806, 2158-2166,
  4113-4127; src/emit.x:1258); 19 uses. No mechanical migration exists for
  `_Generic` in user C, so it cannot be licensed. Declined.
- Designated initializers: ~80 lines (src/expressions.x:754-777, 2558-2600,
  3386-3420, 3609); ~700 uses; a positional rewrite is not
  meaning-preserving under struct reordering. Declined.
- Two-file .c/.h output model: src/generate.x:357-602 (~245) implements
  `#pragma private` visibility and typedef forward ordering across
  conditionals, which any header model needs; a unity build breaks the 2x
  budget on incremental edits (whole-program recompile). Declined.

## 9. Risks and unknowns

- R1 (refutes the thesis if true): a native meta function cannot reach the
  compiler's per-unit facts through `x2c_*` operations alone, because some
  operation depends on the calling unit's Lisp session state
  (`meta_layouts`, `meta_values`, `declaration_projection`, compiler.x
  field groups at map.md:836-842). Section 3 assumes every such fact is
  reachable through the SDK guard's current compiler (src/macros.x:148
  `_sdk_guard`). Unverified for `meta_values` and `declaration_projection`.
- R2: cold-build cost. The count of unittest units that define non-native
  meta bodies was not measured; if it is in the hundreds, the cold test
  build could exceed 2x. Mitigation: batch every test unit's meta bodies
  into one module per suite binary.
- R3: `meta static` per-unit isolation under sequential in-process
  translation (`-j1`, the REPL, editor queries): dlopen caches by path, so
  a per-unit copy path or `dlmopen` is needed. Unverified on macOS.
- R4: the REPL's `lower_repl` surface (commands/repl/repl-session.x:490)
  changes; the brief says consumer surfaces must survive. This design
  changes the REPL's implementation, not its CLI.
- R5: `check_meta_regions` today hard-errors because Lisp-lowered locals are
  freed on return (src/regions.x:20-21 map). The claim that native meta
  results live in the caller's Scope depends on how the kernel invokes the
  function; a native module returning a pointer into its own destroyed
  Scope would be wrong output. The existing native-module handle rules
  (docs/src/guide/meta-functions.md:462-478) already govern this and
  reject the unprovable shape; whether that rejection is a language change
  for bodies that pass today's analysis is unverified (U4).
- R6: byte-identical stage comparison depends on deterministic module
  loading order for name precedence (docs/src/guide/meta-functions.md:
  518-523); the generated table must be ordered by canonical path.
- U1: comptime.x lines 1300-3436 were read by inventory only; a retained
  behavior hidden there (e.g. `_lower_coerce`'s closed conversion list,
  M3) may need a native equivalent.
- U2: AUTO's real speedup on a Lisp program (not the microbenchmark).
- U3: lib/string.x's 38 `meta native` functions and lib/cmath.x's 114
  prototypes were sampled, not enumerated; the claim that every lib/ meta
  surface is already native rests on that sample.
- U4: see R5.

## 10. Claims

1. src/comptime.x is a complete x2c-to-Lisp backend: 160 lowering functions
   spanning expressions (500-1350), statements/loops/switch (1530-2050),
   initializers/stores (2050-2530), cleanup/defer/blocks (2530-2830) and the
   meta-call API (2911-3434). Measurement: grep of `_lower_*` heads.
2. The library's compile-time surface is already native: lib/cmath.x:15-18
   are bodyless `meta` prototypes; lib/string.x:228,284,409,435,457,466 and
   lib/var.x:124,132,448,475 are `meta native`; the compiler links the whole
   runtime (docs/src/guide/meta-functions.md:519-521).
3. Non-native meta bodies in the shipped tree live in nine files:
   lib/autodiff.xmacro (124 `meta`), lib/var-tags.xmacro (37),
   lib/varops.xmacro (10), lib/system-macros.xmacro (9), lib/var-unbox.xmacro
   (5), lib/protocols.x (4), etc/builtin-macros.x (4 + `$builtin.emit`
   decorated bodies), etc/init.x, etc/lisp-bindings.x, src/protocol.x (1).
   Measurement: `grep -c '^\s*meta '` per file.
4. Native modules exist end to end today: `--kind meta-module`
   (src/cli.x:155,879), entry writer src/build.x:450-470, loader
   src/macros.x:1633-1720 with dlopen at 1703, compiler-identity check
   (docs/src/guide/meta-functions.md:508-517), and `--extension` linking
   into the compiler (532-542).
5. `x2c_comptime_lower` has exactly three callers, all generators:
   etc/init.x:9, etc/lisp-bindings.x:11, etc/builtin-macros.x:9; the
   generation step is one line of `bootstrap-refresh` (Makefile:229) and a
   53-line tool.
6. The 12.7x artifact expansion is the one-to-one lowering of parser-built
   `(cons ...)` chains: src/literals.x:75 `_build_cons_cell`,
   src/comptime.x:1362-1365 and 1510-1511; etc/builtin-macros.x:65-66 versus
   etc/builtin-macros.xlisp:206-215.
7. Legacy macro body forms are used 6 times, all in tests/fixtures (section
   8); the handling is src/macros.x:3073-3096, 3277-3288, 3337-3341.
8. `$(` raw Lisp forms: 615 uses, 456 in unittest, 202 with an `x2c.*` head;
   `$(import` 244. Measurement: grep over 1,426 hand-authored files.
9. `with` is 60 lines of statements.x (571-620) plus `with_binding`
   (522-530) and one hook in expressions.x:2731 and parse.x:1064,1860,1871;
   it records the expression, not a temporary, so a local Expression macro
   reproduces its semantics (language.md:2924-2971).
10. match's C lowering is src/emit.x:423+254 to 423+440 (~190 lines) plus
    src/transform.x:559-573; `break` exits the match and `continue` targets
    the enclosing loop (language.md:3030-3032), which `switch (0) default:`
    preserves.
11. Translation forks one worker per unit (src/main.x:220-243), which is what
    keeps `meta static` per unit under L2.
12. The AUTO benchmark gate is prepared/evaluator <= 0.90 over 21 processes
    (unittest/benchmarks/lisp-auto-benchmark.x:9-11); test-lisp-auto.x is 995
    lines and would be retired with the tier.
13. lib/lisp.x regions: reader 549-830, natives and target table 841-1830,
    evaluator 1832-2350, AUTO 2332-2957, API 2958-3190; deleting AUTO and
    speculation leaves ~1,900 lines.
14. Hand-authored etc/ Lisp is 1,163 lines (init-core 176, comptime 399,
    lisp-values 465, builtin-core 34, compiler-sdk 23, lisp-extras 28,
    lisp-bindings-core 33, lisp-io 5); after L2, 707 remain.
15. The percent-literal element rule (language.md:2136-2158) makes the L3
    rewrite deterministic: a bare spelling is an Atom, `$name`/`${e}` are
    evaluated unquotes, nested lists are `%(...)`.
16. The map double-counts lib/machine.x (540) in sections 2.4 and 2.9; the
    ledger above counts it once.
