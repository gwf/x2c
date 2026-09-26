# Design: kernel plus macros

Research spike, 2026-09-26. Stance assigned: a small kernel plus system
macros and meta functions written in ordinary x2c for every syntax-directed
rewrite. Read-only; nothing under src/, lib/, etc/, docs/ was edited. Line
counts are `wc -l` on current dev; citations are file:line in this tree or
in .context/rebuild/map.md.

## 1. Thesis

The reduction does not come from doing more compiler work through macros.
It comes from deleting the second execution engine that today makes macro
work expensive: the x2c-to-Lisp lowering in src/comptime.x (3,435 lines),
the Lisp wordcode tier (lib/lisp.x:2332-2960, lib/lisp-machine.x, the Lisp
half of lib/machine.x), and the generated artifacts and name tables that
exist only to feed them. In the redesign a `meta` function is compiled by
the compiler's own C backend, exactly like every other x2c function, and
called natively at expansion time: linked into the compiler binary when it
ships with the compiler (foreach, class, scope, interpolation, match, Var
operators, printf, adapters, and the rest), or built once into a cached
native module when a user unit defines it. The macro boundary then costs a
function call, not an interpreter, so passes that are today hand-written
walks in src/transform.x, src/cleanup.x, src/lambda.x, src/protocol.x,
src/emit.x, and src/generate.x can be moved behind it without a throughput
regression. Measured evidence says the strong form of Gary's hypothesis is
false for this tree: every pass in src/ is already a match-and-template
walk over canonical `List` syntax (src/transform.x:1590-1768), so moving it
behind the macro boundary relocates it rather than shrinking it. What
shrinks is the engine (about 5,000 lines net), the emitter cases that exist
only because transforms mint private node kinds (src/emit.x:423-862), and
the generation halves of protocol.x and generate.x, which become templates.
The honest total is roughly 80,400 to 71,900 hand-authored lines, an 11%
reduction, with compile throughput unchanged for shipped macros and
compile-time x2c 5x to 100x faster than today's lowered Lisp
(plans/archive/x2c-lowers-to-lisp.md:627-672).

## 2. Architecture

Representation is unchanged: `Ast` is `List` (src/ast.x), `Type` is `List`
(src/type.x:17), Lisp data is `List`, and match templates are `List`
(map.md section 1). The kernel is the set of operations that need facts
only the compiler has; everything else is a rule: an ordinary x2c function
from bound, typed canonical syntax to bound canonical syntax, registered in
a table the kernel drives.

Kernel components, in pass order from source to C:

| component | owns | source today |
|---|---|---|
| tokenizer (lib) | bytes -> Token array, `#pragma indent` layout, list/array/map/string modes | lib/tokenizer.x:793, 484-550 |
| collect | include graph, shallow declaration environment, `.xi` replay, process cache | src/collect.x:567; src/compiler.x:1669 |
| parse | C grammar plus x2c syntax positions; every macro position (unit, block, field, enumerator, map-entry, statement, expression) | src/parse.x:1953; src/statements.x:564; src/macros.x:4154 |
| bind and type | `Sym` scopes, binding identity, typedef chains, protocol member resolution, `Var` tag facts, conversions | src/compiler.x:2470-3905; src/expressions.x:2447-4366; src/protocol.x:901-1740; src/type.x |
| macro engine | definitions, capture projections, hygiene, expansion envelope (transaction, origin, guards), `$(...)` session, imports, native modules | src/macros.x:3153, 2499-2576, 3757-3867, 1155 |
| rule driver | fixed-point rewrite of typed syntax through the rule table; `(at ID node)` origin anchoring; early-declaration queue | src/transform.x:1590-1617, 1776-1801; src/compiler.x:2459 |
| lifetimes | region warnings (kept, coarsened); cleanup exits and `volatile` qualification for `sigsetjmp` frames | src/regions.x:1212; src/cleanup.x:242-624, 628-735 |
| backend | literal cache identity, header/source partition, C token emission, `#line` rendering, diagnostics | src/cache.x; src/generate.x:357-602; src/emit.x:1449; src/format.x:90; src/diagnostics.x:171 |
| driver | CLI, build, project, toolchain, install, script, bootstrap, editor, workers | src/main.x, cli.x, build.x, ... |

Rules (macro or meta over canonical syntax), each an x2c function in a new
`src/rules/` directory, registered by node head and invoked by the driver
at the same point the corresponding `case` runs today in
src/transform.x:1707-1766. A rule receives what today's helper receives (a
bound, typed node and the `Compiler`) and returns syntax the kernel binds
again through `bind_syntax` (src/parse.x:2433-2445 is the precedent: a
`syntax-recipe` returned by a macro is evaluated by name and rebound). The
rules and what they need:

| rule | today | compiler fact needed | exposed today? |
|---|---|---|---|
| interpolation `$name`/`${e}` | src/expressions.x:2089-2108; src/transform.x:1055-1100 | segment types; `str` member resolution | yes: `x2c_syntax_type`, `x2c_method_resolve` (lib/meta.x:147, 271) |
| percent literals, quote/unquote to cons/append | src/literals.x:75-97, 631-737; src/transform.x:991-1053 | which subtrees are constant (cache identity) | new: `x2c.cache.constant(node)` wrapping src/cache.x |
| flat destructuring | src/transform.x:408-550 | RHS type; fresh temporaries | yes: `x2c_syntax_type`; `using`/fresh binders (src/macros.x:3819-3832) |
| `with` | src/statements.x:571-613 | parse-time expression substitution, lvalue use, no evaluation when unused | stays kernel: it is binding, not rewriting (45 lines) |
| `match` statement | src/statements.x:416; src/transform.x:559-573, 1473-1486; src/emit.x:717-862 | typed capture binders introduced by the pattern literal; binder ordinal; per-site static | binders: kernel literal parser (src/literals.x:154-260); ordinal: lib/match.x layout, callable natively; static site: ordinary `static` local |
| `defer`, `try`, `catch`, `raise` | src/transform.x:1102-1420; src/cleanup.x:56-240; src/emit.x:600-716 | rest of enclosing block; enclosing function's return type; labels | new capture projection `Rest`; new `x2c.function.current`; labels are syntax |
| Var operators, indexing, compound updates, `in`, `is` | src/transform.x:587-960 | operand types; protocol members; lvalue shape | yes: `x2c_protocol_member`, `x2c_type_is_value`; new `x2c.type.var-tag` (src/type.x:597-608) |
| printf inference | src/transform.x:52-287 | format literal value; argument types | yes: `x2c_literal_value`, `x2c_syntax_type` |
| lambda lifting | src/lambda.x:1474-1648 | free locals of the enclosing function; sibling declarations | new `x2c.function.locals`, `x2c.unit.add-early` (src/compiler.x:2459) |
| typed callback and Func adapters | src/lambda.x:153-853; etc/builtin-macros.xmacro:8-12 | parameter and result types; per-unit memo of synthesized bridges | yes: `x2c_type_parameters`, `x2c_type_return`; new `x2c.unit.memo` |
| protocol adapters, thunks, descriptor registration | src/protocol.x:1927-1971, 2051-2287, 2295-2343 | conformance rows; `VarMethods` fields | partial: `x2c_protocol_member` answers one member; new `x2c.protocol.conformance` returns the rows (src/protocol.x:1318) |
| type-owned init and shutdown | src/generate.x:59-300; src/parse.x:1533-1600 | the unit's collected `(init ...)` rows and `init_fn`/`fini_fn` names; emission order | ownership check stays kernel; synthesis is a unit-level rule fed by `x2c.unit.inits` |
| delegate fields | src/expressions.x:410-500 | member resolution through delegate paths | stays kernel: it is resolution, not rewriting |
| reference parameters | src/expressions.x:1428, 1486, 1643; src/type.x:640, 956 | callee parameter types (present on typed call syntax) | call-site `&` insertion becomes a rule; declarator canonicalization stays kernel |

The rule driver is today's `_node` (src/transform.x:1590) with the
`switch` at 1707-1766 replaced by a table lookup, keeping identity-based
fixed-point termination (src/transform.x:1605-1617, `c.fixed`) and the
`(at origin inner)` anchoring at 1601-1618. That is about 200 lines of
kernel in place of the 300 that drive today's transform, and it is the only
new mechanism the stance needs besides native meta execution.

## 3. The compile-time execution model

Three execution paths exist today: templates replaced by `List.replace`
(src/macros.x:3849), `$(...)` Lisp evaluated by lib/lisp.x, and `meta`
x2c lowered to Lisp by src/comptime.x and run through the evaluator or the
wordcode tier. The redesign keeps the first two and replaces the third.

**Meta functions are compiled, not lowered.** A `meta` function is an
ordinary x2c function. The kernel calls it through a function pointer and
passes `List` values directly: a compiled meta function and the kernel
share `Var`/`List`, so there is no marshaling (this is the fact that makes
native modules work today: docs/src/guide/meta-functions.md:421-470). Two
placements:

- Shipped: the meta functions behind system macros and rules live in
  `src/rules/` and `etc/builtin-macros.x`, compile into the compiler
  binary, and register under their Lisp names at session start through the
  existing native-target mechanism (`_install_native_operations`,
  src/macros.x:1170; `lisp_native_targets`, lib/lisp.x:1607-1819;
  `_meta_lisp_name`, src/macros.x:1077-1083). `$(foreach.expand ...)` in a
  template (etc/builtin-macros.xmacro:20) resolves to a native. The
  generated etc/builtin-macros.xlisp (8,770 lines), etc/init.xlisp,
  etc/lisp-bindings.xlisp, tools/gen-lisp-init.py, and the `$builtin.emit`
  collectors (etc/builtin-macros.x:5-25, etc/init.x:1-25,
  etc/lisp-bindings.x:5-30) disappear.
- User-defined: when a unit defines a `meta` function with a body and a
  later expansion needs it, the kernel writes a module entry unit exactly
  as `Build.module_entry` does (src/build.x:478-500), translates the
  closure of meta functions defined so far in that unit with the same
  pipeline, compiles it with the toolchain, and loads it with the existing
  `dlopen` path and stamp check (src/macros.x:1702; docs meta-functions.md
  :522). The artifact is cached by content hash under the script cache
  directory (src/script.x:70-110 already implements lock, fingerprint, and
  prune for scripts). The source-order rule is unchanged: a meta function
  reaches only meta functions defined before it (src/regions.x:19-22
  states the same rule for lowering).

`lib/` functions marked `meta` (about 450 definitions across 34 lib files,
for example lib/string.x:228-457, lib/cmath.x, lib/iter.x) need nothing:
they are linked into the compiler and are bound to the session by the
generated target table. etc/comptime.xlisp (399 lines) goes because it is
the runtime for lowered code (`C.true?`, `C.conv`, `C.peek`; map.md 2.4).

**`$(...)` Lisp and `$lisp.bind` keep lib/lisp.x** as the evaluator, with
the AUTO tier removed (lib/lisp.x:2332-2960, the `_expansion_*` speculation
at 1855-1905, lib/lisp-machine.x, and the `LispFrame`/`LispMachine` parts of
lib/machine.x:216-292). Its remaining job is glue in templates
(`$(list 'expr nil (list 'tadapt $target $source))`,
etc/builtin-macros.xmacro:12) and user Lisp macros. One 25-line addition:
memoize a Lisp macro expansion per call site, which the measured
`match-case` re-expansion cost (plans/archive/x2c-lowers-to-lisp.md:755-783)
identified as the dominant evaluator cost. lib/match-machine.x and the
Match half of lib/machine.x stay: Match is a runtime hot path (map.md
section 6, admission memos).

**Hygiene, binding identity, ancestry.** Templates keep definition-time
renaming (src/macros.x:2499-2576, `_replacement_binder`,
`_definition_local`) and fresh `using` binders allocated per expansion
(src/macros.x:3819-3832). Rules and meta functions obtain identities only
from the kernel: `x2c_ident` for a public name they intend to capture
(lib/meta.x:51), `sym.introduce(fresh_name(...))` for private names
(src/cleanup.x:56; src/lambda.x:1477-1483; 137 such sites in src/ today).
They never spell a binder as text; binding records are opaque
(docs/src/reference/language.md:1866-1868) and are spliced unchanged by
`%(...)` templates. Since a rule receives bound syntax and returns syntax
that `bind_syntax` binds again, and `_resolve_content` already accepts a
binding record where an identifier is expected (src/expressions.x:2057),
nothing about identity changes. Diagnostic ancestry is preserved by
running every rule under the same envelope the driver uses today: push a
`(generated occurrence xform)` origin (src/transform.x:1615), bind under
`$let(c.origin, ...)` (src/transform.x:1608, src/macros.x:3858), and let
`origin_location` walk the chain (src/diagnostics.x:293-299). A rule
reports through `x2c_diagnostic_fail` (lib/meta.x:304) at the anchored
origin. No origin validator is added (AGENTS.md; language.md:1863).

**The shared library session** (src/macros.x:1155, `open_macro_library`)
becomes a sequential preload: init-core, lisp-values, compiler-sdk, then
native registration. With no lowering and no `<lisp-late>` race the
lifecycle flags (src/macros.x:1000-1281) collapse to one boolean, as map.md
2.3 already suggests.

**What survives, merges, or goes**

| module | disposition |
|---|---|
| src/comptime.x (3,435) | replaced by native meta execution: ~350 lines of module synthesis, cache, and binding in src/macros.x plus src/build.x reuse |
| lib/lisp.x (3,190) | survives without AUTO and speculation: ~2,400 |
| lib/lisp-machine.x (480) | deleted |
| lib/machine.x (540) | Match-only: ~380 |
| lib/match-machine.x (541) | survives unchanged |
| etc/comptime.xlisp (399) | deleted |
| etc/*.xlisp generated (8,770 + 235 + 229) | not regenerated; their sources become natives |
| examples/programs/literate-lisp.x | survives as the differential checker's reference; the checker keeps its role |

## 4. Feature coverage

Every row of map.md section 4. "Kernel" means it needs binding, types,
layout, lifetimes, or emission order; "rule" means macro or meta over
canonical syntax invoked by the driver or at a macro position.

Language surface, parsing and typing (kernel): C foundation and
expression-bodied functions; scalar declarations, literals, arithmetic;
symbol and atom literals (tokenizer modes plus src/literals.x:1194-1253);
indexing and slicing resolution (the getindex/setindex/slice rewrites at
src/transform.x:1645-1705 become one rule); method-style calls; postfix
chains, unary, sizeof, offsetof, `_Generic`, va_arg, casts, designated
initializers, compound literals; generic selection; mixed declaration rows;
C initializers and static assertions; exact Var-tag tests `is`/`is not`
(typing kernel, lowering rule); membership `in` (rule); Var boxing and
conversion (`convert_expression` kernel; operator lowering rule); dynamic
numeric conversion, truthiness, binary operators (runtime as today);
protocol-backed direct updates (rule over `x2c_protocol_member`); control
flow if/while/for/do/switch/goto/labels (kernel parse, truthiness rule);
`with` (kernel, src/statements.x:571-613); named types, declaration
production, class declarations (macro/meta as today, etc/builtin-macros.x
:232-692); managed-initializer syntax `$auto` (macro as today; the
block-local check at src/transform.x:1593-1597 stays in the driver);
checked foreign aliases (macro shell as today, kernel `falias` binding);
package imports and `name__` prefixing (kernel, src/collect.x:637-643);
source files, pragmas, script units (kernel); indentation syntax (tokenizer
as today); host preprocessing (kernel/driver as today); region model and
lifetime warnings (kernel, coarsened per map.md 2.5; meta hard-error path
removed, see claim 9); structured diagnostics (kernel); two-pass
compilation, `.xi` cache, dependency files (kernel); editor overlays and
semantic queries (kernel); stable `x2c_*` entry points (runtime as today).

Language surface, rules (macro/meta): collection and string literals with
quote/unquote (percent-literal datum to cons/append rule; parsing kernel);
string interpolation; flat list destructuring; lambdas (lifting rule over
the typed function node; parsing and capture bookkeeping
src/literals.x:894-1106 stay kernel); typed callback adapters; foreach and
iterator destination omission (macro as today); match statement and typed
capture patterns (arrangement rule; capture literals kernel); raise,
filtered catch, finally, defer (rule plus kernel volatile pass); reference
parameters (call-site rule; declarator kernel); delegate fields (kernel
resolution, src/expressions.x:438-500); protocols: declaration, adoption,
member resolution, punctuation (kernel, src/protocol.x:261-1740);
conversions and adapters (rule); type-owned initialization and shutdown
(kernel ownership check src/parse.x:1533-1567; synthesis rule); compile-time
macros and decorators with holes, sequences, result kinds, hygiene, keyword
aliasing (kernel macro engine as today); meta functions: introspection,
dual-form, constant folding (kernel calls the compiled function; M5 folding
rules unchanged); inline Lisp bindings `$lisp.bind` and friends (runtime
lib/lisp.x plus etc/lisp-bindings.x as a table of names, no lowering);
`$(import ...)` and native module loading (kernel as today, the same path
now also serves user meta functions); system macros `$scope`, `$let`,
`$lock`, `$auto`, `$class`, `$switch`, `$dedent`, `$todo`, `$unreachable`,
`$time`, `$assert` (macro/meta as today, lib/system-macros.xmacro).

Runtime library: every module page row is "runtime as today" except:
Lisp runtime (reader, session, evaluator, AUTO): runtime redesigned, AUTO
dropped (justified in section 8's drop list); wordcode machine: runtime
redesigned, Match-only; compiler surface for meta functions (lib/meta.x):
runtime as today plus the new operations named in section 2; typed
Array/List/Map generics, Var tags, adapters, unbox, varops, autodiff
`.xmacro` files: runtime as today, their meta functions now compiled;
script-unit modules, static-init, clibc, cmath: as today.

Tooling and packaging: all rows "kernel/driver as today". REPL: the
session executes submissions as native modules instead of lowered Lisp
(commands/repl/repl-session.x:490 calls `Compiler.lower_repl`, which no
longer exists); the `:lowered` inspection (docs/src/guide/repl.md:87) shows
generated C instead of Lisp forms. graph and lint touch neither comptime
nor Lisp (grep over commands/graph, commands/lint: Lisp appears only as a
value type). torch: outside make check, unaffected.

Drop (justified), listed once here and in section 8: none of the language
rows. The Lisp AUTO tier is dropped as a runtime feature.

## 5. Line ledger

Current counts are map.md's per-subsystem totals (lib/machine.x counted
once, under 2.4). "Other lib" holds the 21 lib files no subsystem lists
(protocols.x, error_init.x, diff.x, digest.x, list-selectors.x,
scripting.x, string-classify.x, string-number.x, thread-state.x,
typed-list.x, list-generics.xmacro, var-adapters.xmacro, var-unbox.xmacro,
varops.xmacro, error-private.xmacro, private-keywords.xmacro,
integer-ops.xmacro, native-scalar-types.xmacro, static-init.x, clibc.x,
cmath.x) so the column sums to the map's 80,404.

| subsystem | now | after | reasoning |
|---|---|---|---|
| 2.1 front end | 5,341 | 5,120 | one top-level classification with two continuations (map 3, -140); one canonical-Lisp serialization for freeze/thaw and `.xi` (-50); meta.x preload simplification (-30) |
| 2.2 syntax | 6,618 | 6,220 | literals: quoted array/map/cons construction (src/literals.x:75-97, 631-737) moves to the percent-literal rule (-200); expressions: segment conversion and the cons/append duplicate (-110); statements: match arrangement to a rule (-60); ast unchanged |
| 2.3 macros, comptime, meta | 8,818 | 5,530 | comptime.x deleted (-3,435); native meta driver (+350); library lifecycle and native inventory (-250, map 3); comptime install hooks (-150); new x2c.* operations (+150 in macros.x, +90 in meta.x); collectors removed from builtin-macros.x and init.x (-50); builtin-macros.x otherwise stays as the reference implementation of what a rule looks like |
| 2.4 Lisp and machine | 5,530 | 3,440 | AUTO and speculation out of lisp.x (-680, lines 1855-1905 and 2332-2960), hand native rows replaced by the generated table (-150), memoized expansion (+25); lisp-machine.x deleted (-480); machine.x Match-only (-160); comptime.xlisp deleted (-399); lisp-values.xlisp dictionary rows generated from the target table (-165); lisp-bindings.x/.xmacro become a name table (-97) |
| 2.5 transforms and rules | 5,542 | 4,940 | kernel: driver 200, cleanup.x 620 (region naming and defer thunks leave; exits, labels, volatile stay), regions.x 900 (meta path and one walker out), lambda.x 1,250 (adapter unification, map 3). Rules, written like etc/builtin-macros.x: interpolation 90, percent literals 170, destructuring 110, printf 190, Var operators and indexing 330, truthiness/cast/return/call 120, match 130, defer/try/raise 420, reference parameters 50, protocol adapters 260, init/shutdown 100 (1,970). This row absorbs 1,140 lines from 2.2, 2.6, and 2.13 |
| 2.6 backend | 4,141 | 3,600 | emit.x: match, catch, and raise emission (423-862) reduce to frame push and `sigsetjmp` because rules emit ordinary `static MatchCaptureSite` declarations and runtime calls (-320); generate.x init/shutdown synthesis to a rule (-180); diagnostics share one field pass (-50) |
| 2.7 driver | 6,393 | 6,220 | CLI table with setters (-60), one structured-text reader (-40), one identity hash (-20); the script cache helper generalizes to cached native artifacts for meta modules (-50) |
| 2.8 values | 11,454 | 11,300 | Block/Buffer growth as one generics family (-100); X2CVarNumericInfo embedding (-10); var-tags.xmacro ledger as x2c data now that its scan is compiled (-50, see claim 6) |
| 2.9 match | 4,692 | 4,690 | unchanged: compiled engine, admission memos, and the reference matcher are measured or documented (map 6) |
| 2.10 runtime infrastructure | 7,638 | 7,480 | one recursive-mutex primitive (-90), Context export arms shared (-40), error_init.x ordering kept (-30 from duplicated once-blocks) |
| 2.11 services | 4,953 | 4,650 | autodiff forward/reverse on one mode-parameterized walker (-250); comptime-subset workarounds no longer needed (-50) |
| 2.13 types, protocols, compiler | 7,492 | 6,900 | protocol.x generation to a rule (-330) and one classification pass (-80); compiler.x meta caches and transaction snapshots for lowering (`meta_comptime`, `meta_regions`, `meta_values`, `meta_layouts`; compiler.x:2526-2536) (-100); typedef walkers and declare/bind duplicates (-55); type.x (-27) |
| other lib | 1,773 | 1,773 | unchanged |
| src/ast-rewrite.xmacro | 19 | 19 | unchanged |
| total | 80,404 | 71,882 | -8,522 (10.6%) |

Reference implementations for the estimates:

- The rule sizes are calibrated against etc/builtin-macros.x, where the
  complete `class` defaults (constructor, alloc, free, cleanup, var/unbox,
  equal, hash, str/repr writers, adoptions) are 460 lines of x2c
  (etc/builtin-macros.x:232-692) and `$scope` is 11 (29-39). A rule that
  emits ordinary calls is shorter than a transform that mints a private
  node kind, because the emitter case for that kind goes with it; emit.x
  carries `vseqcall`, `vpostfix`, `vpair`, `vmap`, `vcompound`, `varray`,
  `dstrvalue`, `guarded`, `localinit`, `sourceinit`, `initcode`, `initval`,
  `raise` cases that exist only for transforms (src/emit.x `case %(` heads).
- The comptime deletion is accounted line for line; the driver that
  replaces it reuses `Build.module_entry` (src/build.x:478-500) and
  `script_prepare` (src/script.x:70-110).
- The Lisp reductions are the AUTO tier's own line ranges. The remaining
  evaluator at ~2,400 lines is 2.4x examples/programs/literate-lisp.x
  (1,000 lines, differential-checked), which is the excess a session
  hierarchy, native bridge, expansion guards, and `def`-on-inherited rules
  cost; that excess is not claimed as savings.
- The consolidations in 2.1, 2.7, 2.8, 2.10, 2.11, 2.13 are map.md section
  3 rows with their own estimates, not new claims of this design.

The number to notice is that the rule rows in 2.5 total 1,970 against the
roughly 2,600 lines of the transforms and emitter cases they replace: a
24% reduction on the moved code, all of it from deleting private node
kinds and their emitter cases and from the map's adapter unification. The
transforms were already macros in every sense but placement.

## 6. Performance ledger

Instruments: build-cost score (`make bm-build-scaling`), the translation
CSV, the shootout, `bm-all` (agents/performance-checkpoints.md:37-62).

| dimension | expected change | payoff | measured how |
|---|---|---|---|
| compile throughput, warm build of src/ and lib/ | 0 to +5%: shipped rules are compiled code called through one table lookup per node head instead of a `switch` (src/transform.x:1707); the Lisp evaluator does less work (no lowered bodies to run, no AUTO analysis) | deletion of comptime.x and AUTO | build-cost score before and after; translation CSV per unit |
| compile throughput, cold build of a unit that defines `meta` functions | one toolchain invocation per such unit per content hash, about 0.1 to 0.3 s; 41 units in the tree define meta functions, but the ~34 lib units need none (linked in), so the cost falls on the six lib `.xmacro` files, etc/, and user units | replaces lowering, which today costs 0.3 ms per declaration per importing unit plus re-parse (plans/archive/comptime-x2c-generalization.md:477-486) | `x2c translate` of lib/ cold and warm; the 3.07 s lib/ baseline at comptime-x2c-generalization.md:474 |
| macro expansion time, shipped macros | unchanged or faster: foreach, class, scope bodies run compiled instead of through the evaluator or wordcode; measured precedent is 20 ms against 98 ms per derivation and 22 ms against 2.57 s per lowering pass (plans/archive/x2c-lowers-to-lisp.md:627, 666-672) | same | translation CSV on lib/common.x (nine `$var.tag.unbox` expansions per unit, comptime-x2c-generalization.md:508) |
| macro expansion time, user Lisp macros with heavy bodies | up to 3.4x slower without AUTO (plans/archive/x2c-lowers-to-lisp.md:739-744 measured on a 30-function lowering); template macros with `$(list ...)` glue are unaffected (7 ms across 17 native calls, same plan line 771) | AUTO's only heavy consumer was lowered x2c, which becomes native; remedy for a user is `meta` (now faster than today) | unittest/test-lisp-auto.x workloads timed with and without the tier; no in-tree macro Lisp remains that is not a name table (comptime-x2c-generalization.md:87-121) |
| generated-code speed | unchanged: rules produce the same runtime calls and the same C | none needed | stage comparison byte-for-byte where the migration keeps expansions identical; shootout otherwise |
| runtime hot paths: Var ops, Match, Scope/Pool, errors | unchanged; runtime modules are "as today" | none needed | bm-all |
| runtime Lisp embedded by programs (`Lisp.new`) | up to 3.4x slower on interpreter-bound scripts | tier deletion (1,300 lines) | bm-all Lisp rows |
| REPL | each submission pays a toolchain invocation (about 0.1 to 0.3 s) instead of a lowering; well under the 2x ceiling only if today's submission cost is measured first | removes the REPL's dependence on the comptime subset (docs/src/guide/repl.md:120) | time a fixed submission script |

Unexplained regressions to watch for: the rule table adds a Map lookup per
node visit on the fixed-point path; if it measures above noise, key the
table by the head `Symbol`'s integer, which is what `switch` does today.

## 7. Bootstrap plan

The current compiler is stage 0 throughout. Nothing in the new source
needs a language feature stage 0 lacks:

1. Rules and shipped meta functions are written as ordinary x2c functions
   that call the kernel's `x2c_*` implementations directly (they are in
   the same binary: src/macros.x:147-961). They must not be spelled `meta`
   in the compiler's own tree, because stage 0 would treat a function that
   reaches a bodyless `meta` prototype as compile-time only and emit no
   runtime body (lib/meta.x:16-21; src/comptime.x:47, 365-367). Stage 0
   compiles them as C functions and links them; the new binary registers
   them under their Lisp names at session start.
2. Stage 1 (built by stage 0) is the new kernel plus rules plus a lib/
   whose `.xmacro` meta functions stage 1 compiles into cached native
   modules on first use. lib/var-tags.xmacro is imported by lib/common.x
   (comptime-x2c-generalization.md:484-486), so the first translation of
   lib/ builds that module once.
3. Stage 2 and 3 as today; the stage comparison, fixtures, unit suites,
   examples, and the Lisp differential checker are the acceptance suite.

If staged on the current tree rather than rebuilt, the order that keeps
every step green:

1. Native meta execution beside comptime, behind a flag; port the shipped
   expanders to linked-in natives; stop generating the `.xlisp` artifacts.
   Gate: stage comparison byte-identical.
2. Delete comptime.x, AUTO, lisp-machine.x, comptime.xlisp; port the REPL
   session to native submissions. Gate: suites, REPL probes.
3. Move rewrites into rules one family at a time, in this order because
   each is independent of the others: interpolation, percent literals,
   destructuring, printf, reference parameters, Var operators, match,
   protocol adapters, init/shutdown, defer/try/raise, lambdas and
   adapters. Each step's ideal gate is byte-identical C; where a rule emits
   ordinary calls in place of a private node kind the C changes in form,
   so that step gates on suites and examples plus a shootout run.
4. Map section 3 consolidations in 2.1, 2.7, 2.10, 2.11, 2.13, which are
   independent of the stance.

## 8. Language changes

None. This design is not the licensed architect.

Drops (justified, for the report's separate list):

- Lisp AUTO tier (lib/lisp.x:2332-2960, 1855-1905; lib/lisp-machine.x;
  Lisp parts of lib/machine.x): about 1,300 lines. Its documented
  purpose is transparent acceleration of hot Lambdas; its measured value
  is 3.4x on lowered-x2c workloads that no longer exist. `Lisp.auto_*`
  entry points and unittest/test-lisp-auto.x (995 lines) go with it. The
  differential checker keeps passing because AUTO is transparent by
  contract (map.md 2.4 "must preserve").
- REPL `:lowered` shows generated C rather than Lisp forms. Behavior
  change in commands/repl, which constraint 4 says is a consumer: it must
  be updated, not rebuilt.

## 9. Risks and unknowns

- The 11% figure refutes the assigned stance as a route to a "big"
  reduction. If Gary's expectation is 30% or more, this design does not
  deliver it, and no reading of the source found a pass that would shrink
  by moving behind the macro boundary; the passes are already
  match/template x2c.
- Native meta compilation makes translation depend on a C compiler being
  present and fast at expansion time. Units that define meta functions
  and use them in the same file (docs/src/guide/meta-functions.md:42-66)
  will feel the cold cost on every edit to the meta function. The script
  cache bounds it to one build per content hash; the number was not
  measured in this spike.
- A meta function's closure must be extractable at the point of first
  use: it may reference file-scope statics and earlier functions of its
  unit (docs meta-functions.md:986-1090, "Lifetime and state"). The
  module gets its own copy of that state, which is what a lowered session
  global is today; a meta function that reads a runtime static expecting
  the *program's* value already cannot do so. Not verified against every
  fixture under unittest/compiler-fixtures/meta-*.
- The defer/try rule needs a "rest of block" capture, which the macro
  engine does not have (src/macros.x:2590-2773 projections). It is ~40
  lines by analogy with `Block`, but a `defer` inside a `switch` case run
  interacts with `$switch`'s own block splitting (lib/system-macros.xmacro
  :94-108) and with `_rewrite_defer_list` (src/transform.x:1311); the
  ordering was not traced.
- `volatile` qualification (src/cleanup.x:242-624) stays a kernel pass
  over the enclosing function. A rule that emits the frame and the kernel
  pass that qualifies locals must agree on which locals are live across
  the frame; today one file owns both.
- The REPL port is the largest consumer change and was not designed
  beyond "submissions become native modules with `RTLD_GLOBAL` chaining".
  Persistent globals across submissions, `:inspect` payload accounting
  (docs repl.md:114), and the Lisp call budget (repl.md:185) need a design.
- Whether the rule table's per-node lookup is measurable on the build-cost
  score was not tested.
- comptime.x lines 1300-3435 and match.x 2260-2677 were not read in this
  spike either; the deletion of comptime.x rests on its purpose
  (src/comptime.x:1-16) rather than a line-by-line reading.

What would refute the thesis: a measurement showing that the toolchain
round trip for meta modules costs more than the lowering it replaces on the
common edit loop (a user editing a `.xmacro` and rebuilding one program),
or a fixture set under unittest/compiler-fixtures/meta-* that depends on
lowered-Lisp semantics (session globals shared between units in one
process, `x2c_comptime_lower` inspection) that native execution cannot
reproduce.

## 10. Claims

1. Every transform pass in src/ is already a match-and-template walk over
   canonical `List` syntax dispatching on the node head; the driver's
   `switch` at src/transform.x:1707-1766 and the helper inventory at
   src/transform.x:36-1590 contain no walk that a rule would express
   differently. Moving them relocates lines.
2. Meta functions that reach a bodyless `meta` prototype get no runtime
   body: lib/meta.x:16-21; src/comptime.x:47, 365-367. Therefore the
   compiler's own rules must not be spelled `meta` for stage 0 to link
   them (section 7 step 1).
3. Compiled x2c does the same compile-time work 5x faster per derivation
   (20 ms vs 98 ms) and 111x faster per lowering pass (22 ms vs 2.57 s)
   than the Lisp it replaces: plans/archive/x2c-lowers-to-lisp.md:627-631,
   666-672.
4. AUTO is worth 3.4x on lowered-x2c workloads (2.90 s vs 9.83 s) and
   is invisible on template glue (7 ms across 17 native calls):
   plans/archive/x2c-lowers-to-lisp.md:739-744, 764-771.
5. The Lisp evaluator re-expands a `defmacro` on every call
   (`_apply_lambda`, lib/lisp.x:2166-2174; plans/archive/x2c-lowers-to-lisp.md
   :755-761); memoizing per call site recovers all but 23 ms of a 335 ms
   cost in the cited measurement.
6. The var-tags port was reverted because a lowered `foreach` walks the
   104-row ledger through the evaluator, 13 ms per scan, nine scans per
   unit through lib/common.x (comptime-x2c-generalization.md:461-531). A
   compiled scan of 104 rows is microseconds, so the measurement does not
   apply to native meta execution; the decline is re-opened on that basis
   only, and the ledger row in section 5 claims 50 lines, not the port.
7. Native modules already pass `List`/`Var` values between the compiler
   and compiled code without marshaling, stamp-check the loading compiler,
   and are built by `Build.module_entry`: src/build.x:478-500,
   src/macros.x:1702, docs/src/guide/meta-functions.md:421-533.
8. The kernel already invokes named expanders on syntax it produced:
   `syntax-recipe` and `declaration-recipe` at src/parse.x:2433-2445 call
   `evaluate_declaration_recipe` (src/macros.x:2349) and rebind the
   result. The rule driver generalizes this to node heads.
9. regions.x's only hard-error consumer is the meta path
   (src/regions.x:19-22, 1237; map.md section 3 row 2). Under native
   execution a meta call runs inside a kernel-owned `$scope` whose result
   is copied out, the same convention native modules use for returned
   handles (docs meta-functions.md:462-470), so the hard-error path is not
   needed for correctness; warnings remain a documented feature and stay.
10. emit.x carries emitter cases for transform-minted node kinds
    (`vseqcall`, `vpostfix`, `vpair`, `vmap`, `vcompound`, `varray`,
    `dstrvalue`, `guarded`, `localinit`, `sourceinit`, `initcode`,
    `initval`, `raise`; src/emit.x `case %(` inventory) and string-emits
    match sites and catch sites (src/emit.x:464, 617, 798, 600-640). A rule
    that returns `static MatchCaptureSite` declarations and runtime calls
    as ordinary AST needs none of them.
11. commands/repl is the only consumer of `Compiler.lower_repl`
    (commands/repl/repl-session.x:490; src/comptime.x:2915); graph and
    lint reference neither comptime nor the Lisp session (grep over
    commands/graph, commands/lint).
12. In-tree macro Lisp outside name tables is gone: lib/system-macros
    went 145 to 69 lines when ported to meta functions, varops.xlisp was
    deleted, and the remaining `.xlisp` lines are a dictionary
    (comptime-x2c-generalization.md:87-121, 437-451). Removing AUTO
    therefore regresses no shipped macro.
13. The comptime lowering costs 0.3 ms per declaration per importing unit
    plus a second parse (comptime-x2c-generalization.md:477-486, 497-503);
    native execution pays neither on warm builds because lib/ functions are
    linked and user modules are cached.
14. 41 units define `meta` functions with bodies; 34 are lib/*.x whose
    functions link into the compiler, six are lib/*.xmacro, and three are
    etc/ (grep `^meta ` over src, lib, etc). The cold toolchain cost of
    section 6 therefore falls on at most nine in-tree units.
15. The stage comparison, fixtures, suites, examples, and differential
    checker are unchanged instruments (map.md section 5); rules that keep
    expansions identical gate on byte-identical C, which is how the varops
    port was verified (comptime-x2c-generalization.md:447-451).
