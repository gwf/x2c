# How small the compiler kernel can get

> Status: reference
> Analysis updated 2026-10-09 against the recovered foundation branch
> `codex/language-components-foundation` at 8b78c595 (dev 7e946b86 plus one
> commit), whose continuation is owned by
> `plans/language-components-foundation.md` in that worktree. This document
> is architectural input to that plan: the kernel changes its next
> milestone needs, with one new measurement, and a migration catalog. The
> earlier version, written against `gwf/language-components` 5b7a7769, is
> archived there as `plans/archive/compiler-kernel-hypotheses.md`; this
> version supersedes it. No source changes. Gary selects what to execute.

## Answer

The kernel can give up about 8,000 of its 29,000 language lines, and the
foundation's authoring shape is the right one to do it with: a macro
pattern recognizes the construct, a quotation replaces it, `Code` and
`Type` methods answer semantic questions, `$rewrite` classifies the pattern
once, and the compiler's own operation reaches the rule. The foundation
has one shipped component on that shape, collection access, and dev's
owners for everything else.

What the foundation does not yet have is a rule driver that is as cheap as
the kernel arm a rule replaces. One measurement, made for this update on
the foundation's two synthetic workloads plus an empty unit, splits its
cost into a fixed part and a per-use part:

| Fresh translation, instructions retired (median of 3) | dev | foundation | Added |
| --- | ---: | ---: | ---: |
| Empty unit (`#include "x2c.x"`, empty `main`) | 1.96 G | 2.30 G | 0.34 G |
| Native workload, 300 functions | 4.23 G | 4.59 G | 0.35 G |
| Access workload, 5,400 mutations and 240 reads | 10.30 G | 14.71 G | 4.41 G |

So the whole native overhead is a fixed cost of about 0.34 G per
translation unit, paid before any user code is seen, and the access
overhead is about 0.72 M per applicable rewrite on top of it. Both must
fall before a second component is worth shipping: the fixed part scales
with the number of shipped components, and the per-use part scales with
how often the construct appears in the compiler's own sources.

Six architectural changes, in dependency order, make extraction
net-negative in source and neutral in cost: a process-scoped rule table,
dispatch families keyed by type, prepared replacements, direct calls with
void declines, the kernel's own lowerings written in the component form,
and declaration-time registration in place of feature fields on
`Compiler`. The foundation's next milestone (initializer-only `$auto`,
then delegation, then a combined review) should take the first four
before its review step, because that review is where the cost is judged.

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
and the component adds 132. Where the compiler lines went:

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
| Runtime static locals | cleanup.x localinit and staticinit | 320 | 12 |
| class defaults | compiler.x Defaults, builtins.x 229-830 | 780 | 7 |
| Truthiness, getindex, setindex, dynamic operators | transform.x 406-430 and 1508-1720 | 410 | 620 stores |
| match | statements.x 392-600, transform.x, emit.x 1282-1450, cleanup.x | 650 | 776 |
| Lambda lowering | lambdas.x, callables.x, less Func typing | 1,500 | 586 |
| Protocol declarations, conformance, owners, adapters | protocol.x 449-1490 and 1983-2779 | 1,850 | 153 |
| try, catch, finally | cleanup.x | 700 | 377 |

About 7,600 lines, plus the feature fields on `Compiler` and the second
statement entry described below. A rule that costs more per use than the
arm it replaces slows the self-build by the use count; `match` and
interpolation are the hot ones.

## Architectural changes, in dependency order

### 1. A process-scoped rule table

The 0.34 G fixed cost is paid once per translation unit with one shipped
component. The candidates, all per `Compiler`: replaying the component as
a prelude source and installing its fifteen macro definitions, deriving a
`MacroMatcher` for each registration in `_register_rewrite`, binding the
linked meta targets into the Lisp session, and the declaration-ownership
scan of every runtime module's collected rows in
`runtime_function_declarations`. A profile of the empty unit decides the
split; the fix is the same in each case. Shipped rules belong in a table
built once per process from the prelude, as `_process_cache()` already
holds collected interfaces, with per-unit user rules layered over it. A
matcher is derived on first probe of its family, not at registration. The
declaration-ownership inventory of the runtime is computed once per
process. Guard: the empty unit translates within one percent of dev with
every shipped component installed.

### 2. Dispatch families keyed by type

`binary` and `member` carry a key that excludes unrelated code; `access`
is keyed by use alone, so every indexed mutation on an admitted collection
runs the matcher and the translator, and `decl`/`init` sees every
initialized declarator once any postlude rule exists. Native indexing is
already excluded by `_access_source`, so this change is about applicable
sites and about the families still to come, where `call` and `op` would
otherwise tax every expression.

The classifier derives a second key from the hole in the position the
family designates: the base for `access`, the receiver for `member`, the
left operand for `binary`, the declared type for `decl`, the callee
binding for `call`, the head for `literal` and `statement`. A typed hole
such as `Array $base` registers under its named root; an untyped hole
registers under a wildcard and pays for it. Dispatch resolves that
position's type to its named root, which index admission already does,
and probes `families[family][key]`. The families the catalog needs, each
an existing kernel branch:

| Family | Key | Site today | Clients |
| --- | --- | --- | --- |
| binary | operator, then left type | `_binary_expression` | protocol operators later |
| unary | operator, then operand type | `_operator`, `_postfix` | dynamic operators |
| access | use, then base type | `_access_rewrite` | collection access (done) |
| member | receiver type | `CallSite._method` on a miss | delegate |
| call | callee binding | `_call` | printf families |
| literal | head | `_step_tag` literal arms | collection literals, interpolation |
| statement | head | `_step_tag`, `_statement_rewrite` | switch, match, raise, with |
| declaration | declared type | `finish_initializers` | managed locals, static locals |
| function | none | before the cleanup walk | lambda lifting, destructuring pre-pass |
| unit declaration | head, at collection | `collect.x` | protocol, class, delegate |

Ten families, closed by the kernel; authors never name one, and a pattern
the classifier cannot place is a registration error, as now.

### 3. Prepared replacements

The 0.72 M per applicable rewrite is the replacement path: the translator
queries `Code.type` and `Type.protocol_member`, builds a typed quotation,
and the driver binds it with `bind_syntax`, converts it, and normalizes
it, all from scratch each time. The spike measured the same floor on
`match`: 52 M per use against 12 M built in, with the component's output
written by hand at 45 M.

A translator's quotation is a template whose holes arrive as bound and
typed `Code`. Bind the template body once per template and hole-type
signature into a bound skeleton with slots, and instantiate by
substituting the hole values. The pieces exist: `macro-invoke` and the
`"x2c.template"` stage carry an unexpanded invocation, `_adapter_memo`
memoizes per key, and the foundation already folds constant typed
quotations at their producer. New are the memo keyed by hole types and the
substitution into a bound skeleton. A name in a prepared replacement binds
once, in the component's scope, exactly as a kernel-built call does, which
is also what the declaration-ownership repair had to recover by other
means.

### 4. Direct calls, void declines, one match

Three costs on the dispatch path serve nothing. `apply_meta_function`
reaches `_meta_apply`, which evaluates `((quote f) (quote arg) ...)` in
the Lisp session, for a translator whose linked `Func` the compiler
already holds. A decline is `result.equal(source)`, a structural
comparison of the whole expression per declining candidate. The driver
matches the pattern with the prepared matcher, and the translator's first
statement matches it again with `case $shape(...)`.

A linked translator is called through its `Func`; project and library
translators keep the meta path. A translator declines by returning void or
NULL, tested by identity. The driver hands the translator the captures its
match produced, so the translator's `case` is a confirmation on a prepared
plan or, with a decorator-derived signature, unnecessary.

### 5. The kernel's own lowerings in the component form

With changes 1 to 4 a kernel lowering is a rule that happens to be linked.
transform.x, cleanup.x, callables.x, and protocol.x build canonical AST by
hand; `.context/dual-macro-compiler-opportunities.md` ranks the sites with
line references: the try and defer templates, the `Func` call construct
and recognize pair, four wrapper-function skeletons, scope cells, and the
lambda shape. Written as macro patterns and quotations under their
families, they lose the `expr TYPE`, `stmnt`, `at`, `bind`, and `params`
spellings every reader pays for, and the 45 `x2c_*` constructors in
`lib/meta.x` lose their last clients.

This is the lever that makes total source fall rather than shift. The
kernel that remains is the parser, the binder, the conversion engine with
its positions (declaration, assignment, return, argument, hole, printf
value), the cleanup walk, the macro substrate, unit assembly, and the rule
driver. The `_step_tag` switch becomes the family dispatcher plus those
conversion positions. Order by cost: rare constructs first (printf, raise,
literals, static locals), hot ones last (match, lambdas), each under the
guard below.

### 6. Declaration-time registration in place of feature fields

`Compiler` carries state that one feature reads:

| Field | Uses in src | Owner after migration |
| --- | ---: | --- |
| protocols, protocol_helpers, conforms, adoptions, proto_cache, collect_protocols, import_protocols | 207 | protocol component; kernel query engine |
| lambda_scopes | 17 | lambda component |
| runtime_literals | 17 | literal component |
| needs_exception | 10 | raise and try, as an anchor effect |
| match_types, in_pattern, match_is | 20 | match component |

The foundation dropped the salvaged fact store, so the mechanism here is
the one it kept: type-keyed rule registration. Delegation is the model.
When the parser records `delegate Reader reader;` inside `Wrapper`, the
component registers a `member` rule keyed by `Wrapper`, so a miss on any
other receiver costs a probe and no global callback chain exists. That
needs one addition the foundation lacks: a registration path from a
declaration, the `unit declaration` family, which protocols and class
defaults also need. Declaration-time facts that the kernel's query engine
reads (conformance, operator members, converters) keep compiled tables in
the kernel, built at registration.

The protocol split follows that line. Declaration parsing, publication,
adoption, conformance, generated owners, and adapters register rules and
write tables (about 1,850 lines move); resolution, signature unification,
and operators read them (about 900 lines stay). Two steps: write tables
while resolution keeps its Maps built from them, measure member resolution
per call, then decide whether the Maps go.

### 7. Single-file components and a defined bootstrap transition

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

### 8. One binder, and substrate deletions

Every statement has two entries: the token parser in `statements.x` (18
arms) and the constructed-form binder `_bind_form` in `parse.x` (32 arms,
about 900 lines). Both produce the same bound forms through the same
helpers; `_if_statement` and `_bind_if` are the clearest pair. Rules only
ever produce constructed syntax, so the constructed binder is the one
every extension depends on. Prototype the unification on `if`, `while`,
`do`, and `for`, measure a self-translation, and decide on the number.

Changes 3 and 4 touch the carrier code where `tpl-call`, `macro-invoke`,
and `"x2c.template"` spell one unexpanded invocation three ways and
`_capture_pattern` and `_capture_row` build the same projections twice.
About 300 lines; consolidate them in the same work.

## Migration catalog

Each row names the family and key, the kernel service the component needs,
what the move deletes, and the cost guard. Rows 1 to 3 are the
foundation's next milestone; the rest follow its extraction order with
the dependencies above made explicit.

| Order | Feature | Family and key | Needs | Deletes | Guard |
| --- | --- | --- | --- | --- | --- |
| 0 | changes 1 to 4 | - | - | per-unit registration, Lisp path for linked rules, `equal` declines, double match | empty unit within 1 percent of dev; access workload at or under dev |
| 1 | managed locals | declaration, declared type | Gary's spelling decision below | `_managed_initializer`, `_require_cleanup`, `_cleanup_statement` in parse.x | byte-identical C; 137 uses |
| 2 | delegate | unit declaration `delegate`, then member by enclosing type | change 6 | `DelegateSearch` and `_completion_delegates` in expressions.x, two report macros, `declare_delegate_field` | a miss on other receivers costs a probe |
| 3 | combined review | - | the foundation's milestone step 3 | - | self-translation instruction count against dev |
| 4 | printf Var formats | call, callee binding | `convert_at` for the printf position | family table, `_lower_printf_vars` | per use at or under today |
| 5 | collection literals and order | literal, head | change 3 (cache ids are bound state) | literal-order section of transform.x | byte-identical C |
| 6 | raise | statement `raise` | `needs_exception` as an anchor effect; never-returns fact | `_raise_node`, detail checks, the field | byte-identical C |
| 7 | destructuring | statement `dstrdecl`, `dstrasgn`; function | function family | three transform sections, parse pre-pass | byte-identical C |
| 8 | string interpolation | literal `segments` | `convert_at` for the hole position; `runtime_literals` as component state | `_string_segments`, `_join_segments`, the field | per use at or under today; 730 uses |
| 9 | runtime static locals | declaration, static storage; region rows | a region interface in the cleanup walk (the spike's, not carried) | `localinit`, `staticinit` arms | byte-identical C |
| 10 | with | statement `with` | a bare-name local expression macro | with-statement section | byte-identical C |
| 11 | class defaults | unit declaration `class` | change 6 | `Defaults` in compiler.x; `_class_*` leaves builtins.x | byte-identical C |
| 12 | match | statement `match`; region rows | changes 3 and 5; static arms as `if` tests | `_match_cases` text in emit.x, `_rewrite_matchcases`, three fields | per use at or under 12.4 M; runtime equal or faster |
| 13 | lambda lowering | function | binding identities; unit support effect | callables.x lifting; `lambda_scopes` | per use at or under today |
| 14 | protocols | unit declaration `protocol`; tables | change 6 complete | 1,850 lines of protocol.x; seven fields | member resolution per use unchanged |
| 15 | try, catch, finally | statement `try`; region rows | Gary's decision; the region interface | 700 lines of cleanup.x | per use at or under today |

Notes on the rows that are not routine:

- **Managed locals (1).** The initializer-only spelling needs the
  enclosing declaration, and the prototype that intercepted the
  initializer before expansion failed on forwarding. Three answers: a
  declaration-level spelling such as `$auto(T x = v)`, which is a
  `declaration` rule with no new machinery; preserving the pending
  invocation to declaration completion at the expansion owner, with
  forwarding frames, which is a kernel change to measure; or keeping the
  current kernel owner, which the foundation plan allows when extraction
  makes the whole worse. The first is the smallest. The foundation's
  `$after_initialization` postlude already carries the cleanup half.
- **Delegate (2).** The foundation plan asks for recursive lookup,
  ambiguity, precedence, and completion. All four are inside the
  component's search; the kernel supplies the `member` family and the
  declaration-time registration. Completion needs the rule to answer a
  NULL member with candidate types, as the salvaged component did.
- **match (12).** The emitter writes arm tests as C text and is the
  fastest form the compiler has. A rule must return a prepared
  replacement: a `switch` on the head Symbol, `if` arms for static
  patterns, `Match` runtime calls for dynamic ones, and region rows for
  the arm barrier. With 776 sites in the compiler's own sources, change 3
  is the only way the guard holds. The spike's user-space component ran 9
  to 11 percent faster at runtime than the built-in on its tests.
- **Lambda lowering (13).** Capture analysis runs inside identifier
  resolution and stays. Lifting the helper, the context struct, and the
  cell rewriting is structural once binding identities are visible, and
  the `function` family sees them. `Func` typing and call conversion are
  the conversion engine and stay.
- **Static locals and try (9, 15).** Both need the cleanup walk to accept
  region rows from a rule. The spike proved that interface with
  byte-identical C; the foundation dropped it with the try component. It
  returns when the first of these two rows is taken, not before.

## How to land each move cleanly

1. **Capability first.** A driver change lands in `bootstrap/` one
   publication before a component uses it. Changes 1 to 4 go first, with
   collection access as their client, and are judged by the empty-unit and
   access-workload numbers above.
2. **One feature per change.** The component file, the deleted kernel
   arms and report macros, the deleted `Compiler` fields, and the book
   paragraph move together. A move that leaves the old arm behind is not
   done.
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

- The managed-local spelling (row 1).
- Whether the kernel's own lowerings adopt the component form (change 5),
  the largest and most rewarding change here.
- Whether `try`, `catch`, and `finally` become a component (row 15), which
  also decides whether the region interface returns.
- Whether the token statement parsers are unified into the constructed
  binder (change 8), decided by the measured self-translation cost.
- The family ceiling: ten are listed; a feature that needs an eleventh
  should be presented, not added.
