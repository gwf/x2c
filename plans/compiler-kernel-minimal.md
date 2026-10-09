# How small the compiler kernel can get

> Status: reference
> Analysis updated 2026-10-09 against the recovered foundation branch
> `codex/language-components-foundation` at 8b78c595 (dev 7e946b86 plus one
> commit), whose continuation is owned by
> `plans/language-components-foundation.md` in that worktree. This document
> is architectural input to that plan: the two primitives the kernel should
> expose, the driver changes that make them cheap, one new measurement, and
> a migration catalog. The earlier version, written against
> `gwf/language-components` 5b7a7769, is archived there as
> `plans/archive/compiler-kernel-hypotheses.md`; this version supersedes
> it. No source changes. Gary selects what to execute.

## Answer

The kernel can give up about 8,000 of its 29,000 language lines, and the
way to do it is to expose two primitives that the kernel already uses
privately, then make the kernel's own lowerings their first clients.

**Recognition** answers "which construct calls me." The foundation has
it: a macro pattern recognizes the construct, `$rewrite` classifies the
pattern once into a family, and the compiler's own operation reaches the
rule. It needs a type key per family and a cheaper driver, below.

**Contribution** answers "where my output goes." The kernel has it in
seven private spellings and exposes none of them. `defer` is one
placement, the exits of the enclosing block, wrapped in a keyword. Unit
support, unit initialization, the include anchor, the statement after a
declaration, the rest of a block after a static local, and the entry of
the enclosing function are the same primitive under other names, and each
lowering reaches its ancestor through a private field. Two operations
replace all of them: `place(WHERE, code)` with a closed set of points, and
`enclosing(WHAT)` with a closed set of ancestors. The kernel keeps the
scheduling: the cleanup walk for block exits, the area order for unit
initialization, the memo for unit support.

With both primitives public, `$auto` keeps its spelling and becomes a
five-line macro with no marker, `defer`, `try`, and static locals become
three uses of one placement, and about thirty kernel call sites in seven
files collapse onto two operations. That collapse, not the move of feature
code into component files, is where total source falls.

The foundation also needs its rule driver to cost what a kernel arm costs.
One measurement, made for this update on the foundation's two synthetic
workloads plus an empty unit, splits the cost into a fixed part and a
per-use part:

| Fresh translation, instructions retired (median of 3) | dev | foundation | Added |
| --- | ---: | ---: | ---: |
| Empty unit (`#include "x2c.x"`, empty `main`) | 1.96 G | 2.30 G | 0.34 G |
| Native workload, 300 functions | 4.23 G | 4.59 G | 0.35 G |
| Access workload, 5,400 mutations and 240 reads | 10.30 G | 14.71 G | 4.41 G |

The native overhead is a fixed cost of about 0.34 G per translation unit,
paid before any user code is seen; the access overhead is about 0.72 M per
applicable rewrite on top of it. The fixed part scales with the number of
shipped components and the per-use part with how often a construct appears
in the compiler's own sources. Both fall under the driver changes below.

## Where the foundation stands

Recovered at 8b78c595, against dev:

- `$rewrite` in `lib/rewrite.x`; `Code.register_rewrite` and
  `Code.register_after_initialization` in `src/meta-sdk.x` classify a
  macro's pattern into `binary` by operator, `member` by canonical
  receiver type, `access` by use (`read`, an assignment operator,
  `prefix`, `postfix`), `node` for `switch`, and `decl`/`init`.
- `Compiler._rewrite` in `src/macros.x`: per candidate, a prepared
  `MacroMatcher`, `apply_meta_function`, a deep-equality decline test,
  then `bind_syntax`, `convert_expression`, and `normalize`.
- Dispatch sites: `_binary_expression`, `CallSite._method` on a miss,
  `_access_rewrite` before read or update lowering, `_statement_rewrite`
  for `switch`, and `finish_initializers` for postludes.
- `Code.type`, `Code.value`, `Type.is_named`, `Type.numeric`,
  `Type.is_text`, `Type.protocol_member`; pure Type algorithms in
  `lib/type.x` (617 lines moved out of `src/type.x`).
- `src/component-access.x` (132 lines) is a compiler prelude source,
  listed once in `compiler_prelude_sources()` and once in the payload, and
  linked through the generated `src/linked-meta.x`. Its 60 lines of
  transform arms are gone.
- The declaration-ownership repair in `collect.x` and `generate.x`, which
  removed 4,435 redundant prototypes from bootstrap C.
- Hooks, claims, facts, the auto and delegate components, and the try
  region form are gone; dev's owners serve. All 1,111 fixtures and
  `make verify` pass.

Authored source against dev: compiler 591 added, 745 removed, of which
`src/type.x` is 5 added, 616 removed. Excluding that move the compiler
grew by 457 lines for the mechanism, the library by 107 beyond the move,
and the component adds 132.

| File | Added | Removed | What |
| --- | ---: | ---: | --- |
| src/macros.x | 150 | 10 | rule registry, `_rewrite`, code-value binding |
| src/meta-sdk.x | 117 | 3 | classifier, Code and Type methods |
| src/collect.x | 66 | 12 | prelude sources, declaration ownership |
| src/transform.x | 63 | 68 | access dispatch in, collection arms out |
| src/meta-native.x | 47 | 8 | `apply_meta_function`, `matches_macro` |
| src/parse.x | 45 | 7 | postlude splitting, shared type alias |
| src/meta-helper-client.x | 42 | 2 | node diagnostics, helper queries |
| src/generate.x | 22 | 10 | declaration ownership |

## The kernel today

| Bucket | Files | Lines |
| --- | --- | ---: |
| Driver and tooling | main, cli, build, project, install, toolchain, report, script, editor, deps, cache, frontend, utils, meta-project, meta-group, meta-helper-client, stage, sourceview, format, diagnostics, preprocess | 11,700 |
| Macro and meta substrate | macros, meta-native, meta-sdk, linked-meta, builtins, lambdas, callables, expressions-reports | 10,700 |
| Language core | parse, expressions, statements, symbols, compiler, type, ast, grammar, collect, generate, emit, literals, initializers, transform, cleanup, regions | 26,500 |
| Protocols | protocol, operator-ledger, type-ledger, adapter-memo | 2,900 |

Movable parts of the core and protocols, by section in the current files,
with the compiler's own exposure to each construct:

| Feature | Where | Lines | Uses in src and lib |
| --- | --- | ---: | ---: |
| printf Var formats | transform.x 1208-1453, expressions.x 3206-3335 | 380 | 260 |
| Collection literals and order | transform.x 613-760, expressions.x 2887-3013 | 290 | many |
| String interpolation | literals.x 826-900, transform.x 759-825 | 200 | 730 |
| Destructuring | transform.x 826-1060, parse.x 1075-1135 | 330 | few |
| raise | transform.x 531-545 and 1066-1160, statements.x | 200 | 416 |
| Managed locals | parse.x 2677-2780, expressions.x 3043, transform.x 208 | 110 | 137 |
| Runtime static locals | cleanup.x localinit and staticinit | 320 | 12 |
| class defaults | compiler.x Defaults, builtins.x 229-830 | 780 | 7 |
| Truthiness, getindex, setindex, dynamic operators | transform.x 406-430 and 1508-1720 | 410 | 620 stores |
| match | statements.x 392-600, transform.x, emit.x 1282-1450, cleanup.x | 650 | 776 |
| Lambda lowering | lambdas.x, callables.x, less Func typing | 1,500 | 586 |
| Protocol declarations, conformance, owners, adapters | protocol.x 449-1490 and 1983-2779 | 1,850 | 153 |
| try, catch, finally | cleanup.x | 700 | 377 |

About 7,700 lines, plus the feature fields on `Compiler` and the second
statement entry described below. A rule that costs more per use than the
arm it replaces slows the self-build by the use count; `match` and
interpolation are the hot ones.

## The two primitives

### Recognition: rewrite families keyed by type

The foundation's classifier derives a family and a key, but only `binary`
and `member` carry a key that excludes unrelated code. `access` is keyed
by use alone, so every indexed mutation on an admitted collection runs the
matcher and the translator, and `decl`/`init` sees every initialized
declarator once any postlude rule exists. The families still to come,
`call` and `op`, would otherwise tax every expression.

The classifier derives a second key from the hole in the position the
family designates: the base for `access`, the receiver for `member`, the
left operand for `binary`, the declared type for `decl`, the callee
binding for `call`, the head for `literal` and `statement`. A typed hole
such as `Array $base` registers under its named root; an untyped hole
registers under a wildcard and pays for it. Dispatch resolves that
position's type to its named root, which index admission already does,
and probes `families[family][key]`.

| Family | Key | Site today | Clients |
| --- | --- | --- | --- |
| binary | operator, then left type | `_binary_expression` | protocol operators later |
| unary | operator, then operand type | `_operator`, `_postfix` | dynamic operators |
| access | use, then base type | `_access_rewrite` | collection access (done) |
| member | receiver type | `CallSite._method` on a miss | delegate |
| call | callee binding | `_call` | printf families |
| literal | head | `_step_tag` literal arms | collection literals, interpolation |
| statement | head | `_step_tag`, `_statement_rewrite` | switch, match, raise, with |
| declaration | declared type | `finish_initializers` | static locals, class |
| function | none | before the cleanup walk | lambda lifting, destructuring pre-pass |
| unit declaration | head, at collection | `collect.x` | protocol, class, delegate |

Ten families, closed by the kernel; authors never name one, and a pattern
the classifier cannot place is a registration error, as now.

### Contribution: placement and ancestry

The kernel's private placements today, each a spelling of one primitive:

| Private spelling | Placement point | Where | Callers |
| --- | --- | --- | ---: |
| `defer` statement and its region lowering | exits of the enclosing block | statements.x:370, cleanup.x:878 | the language |
| `localinit` | exits of the rest of the block, from a declaration | cleanup.x:179 | static locals |
| `try` finalizer and catch exits | exits of the body's block, plus a landing | cleanup.x:699 onward | try |
| `_cleanup_statement` | after the enclosing declaration | parse.x:2777 | managed locals |
| `_cell_declaration` | entry of the enclosing function | callables.x:668 | lambda cells |
| `add_early` | unit support | compiler.x:2283 | 13 in callables.x, 8 in protocol.x, 3 in cache.x, 1 in macros.x |
| `add_init(area, stmt)`, five areas | unit initialization | compiler.x:2290 | protocol.x, cache.x, initializers.x |
| `needs_exception = 1` | unit include anchor | cleanup.x:881, macros.x:4208 | raise, try |
| `early`, `cleanup`, `new-name` effects | the same points as a half-exposed carrier | macros.x:4201 | templates in cleanup.x |

The ancestry side is the same story. The parser knows the declarator it is
initializing (`init_tokens`, parse.x:1927), the function it is in
(`fn_name`, `return_type`), the enclosing block, and the unit. Each
lowering reaches the one it needs through a private field. No macro can
ask.

Two operations replace all of them, each with a closed set of points:

- `place(WHERE, code)`: `after-statement`, `before-statement`,
  `block-exit`, `function-entry`, `unit-support`, and `unit-init` with
  its existing areas. `block-exit` is scheduled by the cleanup walk, which
  stays the kernel's: it places the code on every transfer that leaves the
  block, rejects a jump into the region, and keeps landing-read locals
  volatile. `unit-support` keeps the `$adapter.memo` dedupe. `unit-init`
  keeps the area order. Code arrives through the existing code-value
  carrier at any stage, so a contribution that is already lowered is not
  rebound.
- `enclosing(WHAT)`: `declarator`, `statement`, `block`, `function`,
  `unit`, each answering a `Code` the macro can read with the existing
  methods. An ancestor that does not exist at the invocation answers
  nothing, which is the macro's position error.

Both run under the expansion's semantic transaction, as the carrier's
effects do today, so a failed expansion leaves no contribution behind.
Six points and five ancestors; a lowering that needs a seventh point
presents it rather than adding it.

### `$auto` on the two primitives

The marker approach today: [etc/builtin-macros.x:52](etc/builtin-macros.x:52)
expands `$auto(v)` to `(managed-init v)`, and five kernel sites recognize
the marker: typing it (expressions.x:3043), binding it (parse.x:2899),
finding it as a complete initializer and splitting the declaration
(parse.x:2682-2780), and reporting one left over (transform.x:208). The
ancestor looks down for the note because the macro cannot look up.

With the primitives, the macro looks up and the marker goes:

```x2c
macro Expression $auto(Expr $value) {
  Code local = enclosing(<declarator>);
  Type type = local.type();
  if (type.is_static() || type.is_extern() || type.is_threaded())
    x2c_diagnostic_fail("managed initializer requires automatic local storage", %());
  if (!type.protocol_member("cleanup"))
    x2c_diagnostic_fail("managed initializer requires Cleanup participation", %());
  place(<after-statement>, $!{ defer $local.cleanup(); });
  @$value
}
```

The "complete initializer" rule holds without the marker: the declaration
finisher checks by identity that the expansion's result is the declarator's
whole initializer, which `_managed_initializer` does by shape today.
Forwarding through another macro works because the contribution is
attached when `$auto` itself expands, whatever wraps it. Mixed comma
declarations keep the finisher's existing split, which the foundation's
postlude path already shares. The spelling does not change.

### `defer`, `try`, and static locals on one placement

`defer BODY` is `place(<block-exit>, BODY)`; the keyword stays, the
cleanup walk stays as the implementation of that point, and nothing else
in cleanup.x is defer-specific. A `try` finalizer is the same placement on
the body's block, and the catch arms are the same placement on each arm;
only the landing, the `sigsetjmp` frame and the volatile analysis, is
try-specific. A static local with a runtime initializer is the same
placement from its declaration to the block's end. Three lowerings that
each own a region today become three clients of one point, which is what
the spike's region rows were reaching for after the fact.

## Making the driver as cheap as an arm

### A process-scoped rule table

The 0.34 G fixed cost is paid once per translation unit with one shipped
component. The candidates, all per `Compiler`: replaying the component as
a prelude source and installing its fifteen macro definitions, deriving a
`MacroMatcher` per registration in `_register_rewrite`, binding the linked
meta targets into the Lisp session, and the declaration-ownership scan of
every runtime module's rows in `runtime_function_declarations`. A profile
of the empty unit decides the split; the fix is the same in each case.
Shipped rules belong in a table built once per process from the prelude,
as `_process_cache()` already holds collected interfaces, with per-unit
user rules layered over it. A matcher is derived on first probe of its
family. The runtime declaration inventory is computed once per process.
Guard: the empty unit within one percent of dev with every shipped
component installed.

### Prepared replacements

The 0.72 M per applicable rewrite is the replacement path: the translator
queries `Code.type` and `Type.protocol_member`, builds a typed quotation,
and the driver binds, converts, and normalizes it from scratch each time.
The spike measured the same floor on `match`: 52 M per use against 12 M
built in, with the component's output written by hand at 45 M.

A translator's quotation is a template whose holes arrive as bound and
typed `Code`. Bind the body once per template and hole-type signature into
a bound skeleton with slots, and instantiate by substituting the hole
values. The pieces exist: `macro-invoke` and the `"x2c.template"` stage
carry an unexpanded invocation, `_adapter_memo` memoizes per key, and the
foundation folds constant typed quotations at their producer. A name in a
prepared replacement binds once, in the component's scope, exactly as a
kernel-built call does; the declaration-ownership repair recovered that
property by other means.

### Direct calls, void declines, one match

`apply_meta_function` reaches `_meta_apply`, which evaluates
`((quote f) (quote arg) ...)` in the Lisp session for a translator whose
linked `Func` the compiler already holds. A decline is
`result.equal(source)`, a structural comparison per declining candidate.
The driver matches with the prepared matcher and the translator matches
again with `case $shape(...)`. A linked translator is called through its
`Func`; a translator declines by returning void or NULL, tested by
identity; the driver hands the translator the captures its match produced.

## The kernel's own lowerings as the first clients

With both primitives public and the driver cheap, a kernel lowering is a
rule that happens to be linked, and its contributions are placements.
transform.x, cleanup.x, callables.x, and protocol.x build canonical AST by
hand; `.context/dual-macro-compiler-opportunities.md` ranks the sites with
line references: the try and defer templates, the `Func` call construct
and recognize pair, four wrapper-function skeletons, scope cells, and the
lambda shape. Written as macro patterns, quotations, and placements, they
lose the `expr TYPE`, `stmnt`, `at`, `bind`, and `params` spellings every
reader pays for; the 45 `x2c_*` constructors in `lib/meta.x` lose their
last clients; and the seven private placement spellings go.

The kernel that remains is the parser, the binder, the conversion engine
with its positions (declaration, assignment, return, argument, hole,
printf value), the cleanup walk as the `block-exit` scheduler, the macro
substrate, unit assembly as the `unit-support` and `unit-init` scheduler,
and the rule driver. The `_step_tag` switch becomes the family dispatcher
plus the conversion positions. Order by cost: rare constructs first
(managed locals, printf, raise, literals, static locals), hot ones last
(match, lambdas), each under the guard below.

## Feature state becomes declaration-time registration

`Compiler` carries state that one feature reads:

| Field | Uses in src | Owner after migration |
| --- | ---: | --- |
| protocols, protocol_helpers, conforms, adoptions, proto_cache, collect_protocols, import_protocols | 207 | protocol component; kernel query engine |
| lambda_scopes | 17 | lambda component |
| runtime_literals | 17 | literal component |
| needs_exception | 10 | `place(<unit-anchor>)`, or the include as unit support |
| match_types, in_pattern, match_is | 20 | match component |

Delegation is the model for the rest. When the parser records
`delegate Reader reader;` inside `Wrapper`, the component registers a
`member` rule keyed by `Wrapper`, so a miss on any other receiver costs a
probe and no global callback chain exists. That needs the `unit
declaration` family, a registration path from a declaration, which
protocols and class defaults also need. Declaration-time facts the kernel's
query engine reads (conformance, operator members, converters) keep
compiled tables in the kernel, built at registration.

The protocol split follows that line. Declaration parsing, publication,
adoption, conformance, generated owners, and adapters register rules and
place their generated code (about 1,850 lines move); resolution, signature
unification, and operators read the tables (about 900 lines stay). Two
steps: write tables while resolution keeps its Maps built from them,
measure member resolution per call, then decide whether the Maps go.

## Single-file components and a defined bootstrap transition

The foundation is close: a shipped component is one file, listed in
`compiler_prelude_sources()` and the payload, and linked through the
generated `linked-meta.x`. Generate both lists from `src/component-*.x`
and the touch points outside the component file reach zero.

The access report records the remaining hazard: when a shipped
translator's body changed, the old compiler could not use its linked copy
and tried to build a helper for it, and the fix was a hand-disabled
registration for one round. A stale linked copy needs a defined path:
compile the component's source through the ordinary project-meta route
for that build, which the component form allows because it reaches no
compiler internals, or refuse with a message naming
`make bootstrap-refresh`. Never attempt a helper build for the compiler's
own component.

## One binder, and substrate deletions

Every statement has two entries: the token parser in `statements.x` (18
arms) and the constructed-form binder `_bind_form` in `parse.x` (32 arms,
about 900 lines). Both produce the same bound forms through the same
helpers; `_if_statement` and `_bind_if` are the clearest pair. Rules and
placements only ever produce constructed syntax, so the constructed binder
is the one every extension depends on. Prototype the unification on `if`,
`while`, `do`, and `for`, measure a self-translation, and decide on the
number.

The driver changes touch the carrier code where `tpl-call`,
`macro-invoke`, and `"x2c.template"` spell one unexpanded invocation three
ways and `_capture_pattern` and `_capture_row` build the same projections
twice. About 300 lines; consolidate them in the same work.

## Migration catalog

Each row names the recognition family and key, the contribution points,
the kernel service still needed, what the move deletes, and the cost
guard. Rows 1 to 3 are the foundation's next milestone; the rest follow
its extraction order with the dependencies above made explicit.

| Order | Feature | Recognition | Contribution | Needs | Deletes | Guard |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | the two primitives and the driver changes | - | `place`, `enclosing` | - | per-unit registration, Lisp path for linked rules, `equal` declines, double match, the seven private placement spellings as kernel code migrates | empty unit within 1 percent of dev; access workload at or under dev |
| 1 | managed locals | none; an expression macro | `enclosing(<declarator>)`, `place(<after-statement>)` | row 0 | `managed-init` and its five recognizers, about 110 lines | byte-identical C; 137 uses |
| 2 | delegate | unit declaration `delegate`, then member by enclosing type | none | the `unit declaration` family | `DelegateSearch`, `_completion_delegates`, two report macros, `declare_delegate_field` | a miss on other receivers costs a probe |
| 3 | combined review | - | - | the foundation's milestone step 3 | - | self-translation instruction count against dev |
| 4 | printf Var formats | call, callee binding | none | `convert_at` for the printf position | family table, `_lower_printf_vars` | per use at or under today |
| 5 | collection literals and order | literal, head | `place(<unit-support>)`, `place(<unit-init>)` for cached slots | prepared replacements (cache ids are bound state) | literal-order section of transform.x | byte-identical C |
| 6 | raise | statement `raise` | `place(<unit-anchor>)` | never-returns fact | `_raise_node`, detail checks, `needs_exception` | byte-identical C |
| 7 | destructuring | statement `dstrdecl`, `dstrasgn`; function | `place(<before-statement>)` for temporaries | function family | three transform sections, parse pre-pass | byte-identical C |
| 8 | string interpolation | literal `segments` | `place(<unit-support>)` for cached segments | `convert_at` for the hole position | `_string_segments`, `_join_segments`, `runtime_literals` | per use at or under today; 730 uses |
| 9 | runtime static locals | declaration, static storage | `place(<block-exit>)` from the declaration | row 0 | `localinit` and `staticinit` arms | byte-identical C |
| 10 | with | statement `with` | none | a bare-name local expression macro | with-statement section | byte-identical C |
| 11 | class defaults | unit declaration `class` | `place(<unit-support>)`, `place(<unit-init>)` | the `unit declaration` family | `Defaults` in compiler.x; `_class_*` leaves builtins.x | byte-identical C |
| 12 | match | statement `match` | `place(<block-exit>)` for the arm barrier | prepared replacements; static arms as `if` tests | `_match_cases` text in emit.x, `_rewrite_matchcases`, three fields | per use at or under 12.4 M; runtime equal or faster |
| 13 | lambda lowering | function | `place(<function-entry>)` for cells, `place(<unit-support>)` for helpers | binding identities | callables.x lifting, `_cell_declaration`, `lambda_scopes` | per use at or under today |
| 14 | protocols | unit declaration `protocol` | `place(<unit-support>)`, `place(<unit-init>)` | declaration-time tables | 1,850 lines of protocol.x; seven fields; 8 `add_early` sites | member resolution per use unchanged |
| 15 | try, catch, finally | statement `try` | `place(<block-exit>)` on body and arms, plus the landing | Gary's decision | 700 lines of cleanup.x less the walk | per use at or under today |

Notes on the rows that are not routine:

- **Managed locals (1).** The spelling stays. The macro is the one shown
  above; the kernel adds the two operations and deletes the marker and its
  recognizers. Storage and `Cleanup` checks move into the macro as `Type`
  method calls. The two operations have other clients in rows 5 to 15, so
  they are not auto-specific machinery.
- **Delegate (2).** The foundation plan asks for recursive lookup,
  ambiguity, precedence, and completion. All four are inside the
  component's search; the kernel supplies the `member` family and the
  declaration-time registration. Completion needs the rule to answer a
  NULL member with candidate types, as the salvaged component did.
- **match (12).** The emitter writes arm tests as C text and is the
  fastest form the compiler has. A rule must return a prepared
  replacement: a `switch` on the head Symbol, `if` arms for static
  patterns, `Match` runtime calls for dynamic ones, and `block-exit`
  placement for the arm barrier. With 776 sites in the compiler's own
  sources, prepared replacements are the only way the guard holds. The
  spike's user-space component ran 9 to 11 percent faster at runtime than
  the built-in on its tests.
- **Lambda lowering (13).** Capture analysis runs inside identifier
  resolution and stays. Lifting the helper, the context struct, and the
  cell rewriting is structural once binding identities are visible, and
  the `function` family sees them; cells are `function-entry` placements.
  `Func` typing and call conversion are the conversion engine and stay.
- **Static locals and try (9, 15).** Both are `block-exit` placements
  once `defer` is one. Static locals come first because they have no
  landing. `try` adds the landing and is Gary's decision; the spike proved
  byte-identical C for a try component at 0.45 to 0.73 M per `try`.

## How to land each move cleanly

1. **Capability first.** A primitive or driver change lands in
   `bootstrap/` one publication before a component uses it. Row 0 goes
   first, with collection access and `$auto` as its clients, judged by the
   empty-unit and access-workload numbers above.
2. **One feature per change.** The component or macro, the deleted kernel
   arms and report macros, the deleted `Compiler` fields, the deleted
   private placement spellings, and the book paragraph move together. A
   move that leaves the old arm behind is not done.
3. **Proof.** Replay the specimen corpus against stored bytes with the
   recovered harness under `.context/foundation/synthetic/` and the
   earlier `corpus-parity/replay.py`, whose compiler paths are hardcoded
   and must be re-pointed; a difference is a reviewed, accepted change or a
   defect. Run the feature's fixtures through `run.sh check --fixture`.
   Refresh the bootstrap twice before `make stage-diff-0`.
4. **Cost.** Three numbers per change, instructions retired on converged
   compilers with fresh output directories and unique stems so the
   interface cache cannot answer: the empty unit, the feature's synthetic
   workload, and a self-translation. The budget is the arm the rule
   replaces. Record all three in the change.
5. **Report.** Kernel lines removed against component and integration
   lines added, per file, so the total is visible. The foundation plan's
   rule stands: a smaller kernel alone is not simplification.
6. **Delivery.** Through the shared integrator as the current mode
   requires; the two-round refresh is the integrator's.

## Open decisions for Gary

- Whether `try`, `catch`, and `finally` become a component (row 15).
- Whether the token statement parsers are unified into the constructed
  binder, decided by the measured self-translation cost.
- The ceilings: ten recognition families, six placement points, five
  ancestors. A feature that needs another presents it rather than adding
  it.
