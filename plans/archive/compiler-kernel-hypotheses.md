# How small the compiler kernel can get

> Status: retired
> Historical hypothesis catalogue. Its LOC and speed projections are unvalidated.
> Execution is owned solely by ../language-components-foundation.md.
> Analysis written 2026-10-09 against `dev` 7e946b86 and the component
> branch `gwf/language-components` at 5b7a7769. It anticipates the
> architectural changes the component plan in
> [historical experiments](language-components-experiments.md) needs before feature
> extraction can make the compiler smaller, faster, and simpler at once,
> and catalogs each migration against those changes. No source changes.
> Gary selects what to execute.

## Answer

The kernel can give up about 8,000 of its 29,000 language lines. The
authoring shape on the branch is the right one: a macro pattern recognizes
the construct, a quotation replaces it, `Code` and `Type` methods answer
semantic questions, registration classifies the pattern once, and the
compiler's own operation reaches the rule. What stands between that shape
and a smaller compiler is that the kernel still treats a rule as a foreign
call. It evaluates the translator through the Lisp session, matches the
pattern twice, binds and types the replacement from scratch, and detects a
decline by deep equality. The first production candidate shows the result:

| Collection access candidate, against a56da260 | Value |
| --- | ---: |
| Kernel lines removed (transform.x) | 60 |
| Component lines added | 132 |
| Other compiler lines added | 197 |
| Native workload translation time | 1.08x |
| Access-heavy workload translation time | 1.45x |

Five architectural changes turn that into net-negative source and neutral
cost. In dependency order: dispatch families keyed by type, prepared
replacements, direct calls with void declines, the kernel's own lowerings
written in the component form, and feature state moved into facts and
registries. One build change, single-file shipped components, removes the
remaining friction. The catalog at the end places every feature on those
changes.

## Where the work stands

At 5b7a7769 the branch has:

- `$rewrite` in `lib/rewrite.x`: a decorator that registers the decorated
  `meta` function with a macro and optional hole patterns.
- `Code.register_rewrite` in `src/meta-sdk.x`: the classifier. It derives
  one of these families from the macro's pattern: `binary` by operator,
  `member` by receiver type, `access` by use (`read`, an assignment
  operator, `prefix`, `postfix`), `node` for `switch`, and `decl`/`init`
  for post-initialization statements.
- `Compiler._rewrite` in `src/macros.x`: per candidate, a prepared
  `MacroMatcher`, a meta call, a deep-equality decline test, then
  `bind_syntax`, `convert_expression`, and `normalize` of the result.
- Dispatch sites: `Resolve._binary_expression`, `CallSite._method` on a
  lookup miss, `_access_rewrite` in the transform, `_statement_rewrite`
  for `switch`, and the declaration finisher.
- `Code.type`, `Code.value`, `Type.is_named`, `Type.numeric`,
  `Type.is_text`, `Type.protocol_member`; pure Type algorithms moved to
  `lib/type.x` (617 lines).
- `src/component-access.x` (132 lines), linked into the compiler.
- `$auto` and `delegate` still on the superseded `claim` and `member`
  hooks, slated for removal once their replacements exist.
- Node hooks, `lib/meta-patterns.x`, and the public effect builders
  removed (325 net production lines).

A claim-free `$auto` prototype that intercepts the initializer before
expansion was rejected by its own report: forwarding macros expand the
inner `$auto` first. The branch's measurements, fixture state (five known
failures shared with the baseline), and generated-C condition are recorded
in `experiments/language-components/builtin/README.md`. This worktree holds
the earlier salvage proofs under `.context/language-components/`.

## The kernel today

| Bucket | Files | Lines |
| --- | --- | ---: |
| Driver and tooling | main, cli, build, project, install, toolchain, report, script, editor, deps, cache, frontend, utils, meta-project, meta-group, meta-helper-client, stage, sourceview, format, diagnostics, preprocess | 11,700 |
| Macro and meta substrate | macros, meta-native, meta-sdk, linked-meta, builtins, lambdas, callables, expressions-reports | 10,700 |
| Language core | parse, expressions, statements, symbols, compiler, type, ast, grammar, collect, generate, emit, literals, initializers, transform, cleanup, regions | 26,500 |
| Protocols | protocol, operator-ledger, type-ledger, adapter-memo | 2,900 |

Movable parts of the core and protocols, by section in the current files:

| Feature | Where | Lines | Uses in src and lib |
| --- | --- | ---: | ---: |
| printf Var formats | transform.x 1208-1453, expressions.x 3206-3335 | 380 | 260 |
| Collection literals and order | transform.x 613-760, expressions.x 2887-3013 | 290 | many |
| String interpolation | literals.x 826-900, transform.x 759-825 | 200 | 730 |
| Destructuring | transform.x 826-1060, parse.x 1075-1135 | 330 | few |
| raise | transform.x 531-545 and 1066-1160, statements.x | 200 | 416 |
| Runtime static locals | cleanup.x localinit and staticinit | 320 | 12 |
| class defaults | compiler.x Defaults, builtins.x 229-830 | 780 | 7 |
| Truthiness, getindex, setindex, dynamic operators | transform.x 406-430 and 1508-1720 | 470 | 620 stores |
| match | statements.x 392-600, transform.x, emit.x 1282-1450, cleanup.x | 650 | 776 |
| Lambda lowering | lambdas.x, callables.x, less Func typing | 1,500 | 586 |
| Protocol declarations, conformance, owners, adapters | protocol.x 449-1490 and 1983-2779 | 1,850 | 153 |
| try, catch, finally | cleanup.x | 700 | 377 |

About 7,700 lines, plus the feature fields on `Compiler` and the second
statement entry described below. The use counts are the compiler's own
exposure: a rule that costs more per use than the arm it replaces slows the
self-build by that count. `match` and interpolation are the hot ones.

## Architectural changes, in dependency order

### 1. Dispatch families keyed by type or binding

The classifier derives a family and a key, but only `binary` and `member`
have a key that excludes unrelated code. `access` is keyed by use alone, so
every indexed store in a unit runs the matcher and the translator, and the
translator declines by testing `_collection_family`. `decl`/`init` sees
every initialized declarator. That is the native overhead and most of the
access overhead.

The change: the classifier also derives a type key from the hole in the
position the family designates. For `access` it is the base, for `member`
the receiver, for `binary` the left operand, for `decl` the declared type,
for `call` the callee binding, for `literal` and `statement` the head. A
typed hole, `Array $base`, registers under its named root; an untyped hole
registers under a wildcard and pays for it. At dispatch the kernel
resolves that position's type to its named root, through typedef aliases
and one pointer layer, which index admission already does, and probes
`families[family][key]`. Native indexing, native arithmetic, and
unrelated declarations never run a matcher.

The families the extraction order needs, each an existing kernel branch:

| Family | Key | Site today | Clients |
| --- | --- | --- | --- |
| binary | operator, then left type | `Resolve._binary_expression` | protocol operators later |
| unary | operator, then operand type | `_operator`, `_postfix` | dynamic operators |
| access | use, then base type | `_access_rewrite` | collection access (done) |
| member | receiver type | `CallSite._method` on a miss | delegate |
| call | callee binding | `_call` | printf families |
| literal | head | `_step_tag` literal arms | collection literals, interpolation |
| statement | head | `_step_tag`, `_statement_rewrite` | switch, match, raise, with |
| declaration | declared type | declaration finisher | managed locals, static locals |
| function | none | before the cleanup walk | lambda lifting, destructuring pre-pass |
| unit declaration | head, at collection | `collect.x` | protocol, class, delegate |

Ten families. The family set is closed by the kernel; authors never name
one. A pattern the classifier cannot place is a registration error, as now.

### 2. Prepared replacements

A translator's replacement is bound and typed from scratch on every use:
`bind_syntax`, then `convert_expression`, then `normalize`. The spike
measured the floor directly: a `match` component at 52 M instructions per
use against 12 M built in, and the same output written by hand at 45 M. The
access profile agrees: after the matcher was prepared once, binding and
lowering remained the dominant cost.

The change: a translator's quotation is a template whose holes arrive as
already bound and typed `Code`. Bind the template body once per template
and hole type signature into a bound skeleton with slots, and instantiate
by substituting the hole values. The pieces exist: `macro-invoke` and the
`"x2c.template"` stage carry an unexpanded invocation, `_adapter_memo`
memoizes per key, and `Macro.typed` folds constant typed quotations. What
is new is the memo keyed by hole types and the substitution of bound
values into a bound skeleton.

Prepared replacements also settle the generated-C condition the access
candidate could not meet. A name in a replacement binds once, in the
component's scope, exactly as a kernel-constructed call does, so no helper
prototype appears that the kernel did not emit.

### 3. Direct calls, void declines, one match

Three costs on the dispatch path serve nothing:

- `apply_meta_function` calls `_meta_apply`, which evaluates
  `((quote f) (quote arg) ...)` in the Lisp session, for a translator that
  `builtin_targets` already holds as a `Func`.
- A decline is `result.equal(source)`, a structural comparison of the
  whole expression, once per declining candidate.
- The dispatcher matches the pattern with `MacroMatcher`, and the
  translator's first statement matches it again with `case $shape(...)`.

The change: a linked translator is called through its `Func`; a project or
library translator keeps the meta path. A translator declines by returning
void or NULL, tested by identity. The dispatcher hands the translator the
captures its match produced, so the translator's `case` is a cheap
confirmation on a prepared plan or, with a decorator-derived signature,
unnecessary. Expected: a declined linked rule costs a probe and a call; an
applicable one costs change 2 alone.

### 4. The kernel's own lowerings in the component form

Once changes 1 to 3 hold, a kernel lowering is a rule that happens to be
linked. transform.x, cleanup.x, callables.x, and protocol.x build canonical
AST by hand today; `.context/dual-macro-compiler-opportunities.md` ranks
the sites with line references: the try and defer templates, the `Func`
call construct and recognize pair, four wrapper-function skeletons, scope
cells, and the lambda shape. Written as macro patterns and quotations under
their families, they lose the `expr TYPE`, `stmnt`, `at`, `bind`, and
`params` spellings that every reader of those files pays for, and the
kernel no longer needs the 45 `x2c_*` constructors in `lib/meta.x`, which
the plan already slates for deletion.

This is the lever that makes "most things improve" true rather than
hopeful. The kernel that remains is the parser, the binder, the conversion
engine with its positions (declaration, assignment, return, argument, hole,
printf value), the cleanup walk on region rows, the macro substrate, unit
assembly, and the rule driver. The `_step_tag` switch becomes the family
dispatcher plus those conversion positions. Do it in cost order: rare
constructs first (printf, raise, literals, static locals), hot ones last
(match, lambdas), each with the guard below.

### 5. Feature state becomes facts and registries

`Compiler` carries state that one feature reads:

| Field | Uses in src | Owner after migration |
| --- | ---: | --- |
| protocols, protocol_helpers, conforms, adoptions, proto_cache, collect_protocols, import_protocols | 207 | protocol component facts; kernel query engine |
| lambda_scopes | 17 | lambda component |
| runtime_literals | 17 | literal component |
| needs_exception | 10 | raise and try, as an anchor effect |
| match_types, in_pattern, match_is | 20 | match component |

`Sym.record_fact` is the store for declaration-time facts: a field
delegates, a type conforms, a class has defaults, an operator maps to a
member. It is scoped and replays through interfaces. Hot queries keep
compiled tables in the kernel: member resolution, conversion rules,
operator rows. Delegation shows the pattern: the parser records the fact
when it sees `delegate Reader reader;`, and that recording registers a
`member` rule keyed by the enclosing type, so a miss on any other receiver
costs a probe. No global callback chain, which is the boundary the plan
already asks for.

The protocol split follows the same line. Declaration parsing,
publication, adoption, conformance, generated owners, and adapters write
facts and register rules (about 1,850 lines move). Resolution, signature
unification, and operators read them (about 900 lines stay). Do it in two
steps: first write facts while resolution keeps its compiled Maps built
from them at install, then measure member resolution per call, then decide
whether the Maps go or stay as the kernel's index.

### 6. Single-file shipped components and a defined bootstrap transition

A shipped component touches three places outside its file: an `#include`
in `builtins.x`, a `$builtin.row` in `builtin_targets`, and the
registration text installed by `install_builtin_macros`. Generate the first
two from `src/component-*.x` and embed each component's own registration
lines with that text, so a component moves from an include, to `lib/`, to
`src/` without an edit.

The access report also records a bootstrap hazard: when a shipped
translator's body changed, the old compiler could not use its linked copy
and tried to build a helper for it, and the fix was to disable the
registration by hand for one round. The architecture needs a defined path
for a stale linked copy: either compile the component's source through the
ordinary project-meta route for that build, which the thin API makes
possible because a component reaches no compiler internals, or refuse with
a message naming `make bootstrap-refresh`. Never attempt a helper build for
the compiler's own component. The two-round refresh stays the publication
path.

### 7. One binder, and substrate deletions

Every statement has two entries: the token parser in `statements.x` (18
arms) and the constructed-form binder `_bind_form` in `parse.x` (32 arms,
about 900 lines). Both produce the same bound forms through the same
helpers; `_if_statement` and `_bind_if` are the clearest pair. Components
only ever produce constructed syntax, so the constructed binder is the one
every rule depends on. Prototype the unification on `if`, `while`, `do`,
and `for`, measure a self-translation, and decide on the number.

Changes 2 and 3 touch the carrier code where `tpl-call`, `macro-invoke`,
and `"x2c.template"` spell one unexpanded invocation three ways and
`_capture_pattern` and `_capture_row` build the same projections twice.
About 300 lines; consolidate them in the same work rather than after.

## Migration catalog

Each row names the family and key, the kernel service the component needs,
what the move deletes, and the cost guard. Order follows the component
plan with the dependencies above made explicit.

| Order | Feature | Family and key | Needs | Deletes | Guard |
| --- | --- | --- | --- | --- | --- |
| 0 | changes 1 to 3 | - | - | Lisp path for linked rules, `equal` declines, double match | native workload 1.00x; access workload at or under a56da260 |
| 1 | collection access | access, base type | change 1 | the remaining `_access_rewrite` type tests | as row 0 |
| 2 | delegate | unit declaration `delegate`, then member by enclosing type | change 5 | `claim` and `member` hooks, `_hooked`, `_member_hooks`, hook parsing | miss on other receivers costs a probe |
| 3 | managed locals | declaration, declared type | Gary's spelling decision below | `claim` node, `finish_claims` | byte-identical C |
| 4 | printf Var formats | call, callee binding | `convert_at` for the printf position | family table, `_lower_printf_vars` | per use at or under today |
| 5 | collection literals and order | literal, head | change 2 (cache ids are bound state) | literal-order section of transform.x | byte-identical C |
| 6 | raise | statement `raise` | `needs_exception` as an anchor effect; never-returns fact | `_raise_node`, detail checks, the field | byte-identical C |
| 7 | destructuring | statement `dstrdecl`, `dstrasgn`; function | function family | three transform sections, parse pre-pass | byte-identical C |
| 8 | string interpolation | literal `segments` | `convert_at` for the hole position; `runtime_literals` as a fact | `_string_segments`, `_join_segments`, the field | per use at or under today (730 uses) |
| 9 | runtime static locals | declaration, static storage; region rows | region form, present | `localinit`, `staticinit` arms | byte-identical C |
| 10 | with | statement `with` | a bare-name local expression macro | with-statement section | byte-identical C |
| 11 | class defaults | unit declaration `class` | change 5 | `Defaults` in compiler.x; `_class_*` leaves builtins.x | byte-identical C |
| 12 | match | statement `match`; region rows | changes 2 and 4; static arms as `if` tests | `_match_cases` text in emit.x, `_rewrite_matchcases`, three fields | per use at or under 12.4 M; runtime equal or faster |
| 13 | lambda lowering | function | binding identities; unit support effect | callables.x lifting; `lambda_scopes` | per use at or under today |
| 14 | protocols | unit declaration `protocol`; facts | change 5 complete | 1,850 lines of protocol.x; seven fields | member resolution per use unchanged |
| 15 | try, catch, finally | statement `try`; region rows | Gary's decision | 700 lines of cleanup.x | per use at or under today |

Notes on the rows that are not routine:

- **Managed locals (3).** The initializer-only spelling `T x = $auto(v)`
  needs the enclosing declaration, and the prototype that intercepts before
  expansion failed on forwarding. Three answers exist: a declaration-level
  spelling such as `$auto(T x = v)`, which is a `declaration` rule with no
  new machinery; preserving the pending invocation to declaration
  completion at the expansion owner, with forwarding frames, which is a
  kernel change to measure; or keeping the `claim` marker as kernel
  internal. The first is the smallest. It is Gary's call and the plan says
  to show the code before deciding.
- **match (12).** The emitter writes arm tests as C text and is the fastest
  form the compiler has. A rule must return a prepared replacement: a
  `switch` on the head Symbol, `if` arms for static patterns, `Match`
  runtime calls for dynamic ones, and region rows for the arm barrier. With
  776 sites in the compiler's own sources, change 2 is the only way the
  guard holds. The spike's user-space component ran 9 to 11 percent faster
  at runtime than the built-in on its tests, so the generated program does
  not lose. The known built-in defect (a `defer` in an arm that reads an
  arm binder) disappears if arm binders become ordinary declarations.
- **Lambda lowering (13).** Capture analysis runs inside identifier
  resolution and stays. Lifting the helper, the context struct, and the
  cell rewriting is structural once binding identities are visible, and the
  `function` family sees them. `Func` typing and call conversion are the
  conversion engine and stay.
- **try (15).** The region form already lets a rule return the rows; the
  spike proved byte-identical C with a 244-line component at 0.45 to
  0.73 M per `try`, under one percent of a self-translation. Nothing above
  depends on it.

## How to land each move cleanly

1. **Capability first.** The driver change a component needs lands in
   `bootstrap/` one publication before the component uses it. Changes 1
   to 3 therefore go first, alone, with collection access as their client.
2. **One feature per change.** The component file, the deleted kernel
   arms and report macros, the deleted `Compiler` fields, and the book
   paragraph move in the same change. A move that leaves the old arm
   behind is not done.
3. **Proof.** Replay the 225-specimen corpus with
   `.context/language-components/corpus-parity/replay.py` against stored
   bytes; a difference is a reviewed, accepted change or a defect. Run the
   feature's fixtures through `run.sh check --fixture`. Refresh the
   bootstrap twice before `make stage-diff-0`.
4. **Cost.** Measure the two synthetic workloads with
   `.context/language-components/builtin-access/measure.py` and a
   self-translation instruction count on converged compilers, before and
   after. The budget is the arm the rule replaces. Record both numbers in
   the change. Attribute the current native overhead before change 1 is
   judged: the candidates are per-site matcher work and per-process
   registration, and a profile of the native workload decides.
5. **Report.** Kernel lines removed against component and integration
   lines added, per file, so the total is visible.
6. **Delivery.** Through the shared integrator as the current mode
   requires; the two-round refresh is the integrator's.

## Open decisions for Gary

- The managed-local spelling (row 3).
- Whether the kernel's own lowerings adopt the component form (change 4),
  which is the largest and most rewarding change here.
- Whether `try`, `catch`, and `finally` become a component (row 15).
- Whether the token statement parsers are unified into the constructed
  binder (change 7), decided by the measured self-translation cost.
- The family ceiling: ten are listed above; a feature that needs an
  eleventh should be presented, not added.
