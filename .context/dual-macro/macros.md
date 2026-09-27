# Macro producer research (read-only source trace)

## Current behavior, verified in source

- `src/macros.x:739-754` recognizes named global and named local definitions.
  Anonymous definition grammar does not exist. `:3398-3437` requires a result
  kind and name. The user's braced Expression example is proposed syntax:
  current Expression definitions require `=> EXPR;`, and braces are explicitly
  rejected (`:3515-3540`). Preserve existing syntax in initial examples.
- Definitions are ordinary canonical Lists, not opaque values. `_definition`
  (`:3370-3390`) stores `macrodef` with name, kind, target, targetp, parameters,
  fresh, captures, pattern, template, origin, file and flags. Import/publication
  machinery retains these Lists. Native `meta` template call lowering caches a
  local definition as a literal Var (`src/stage.x:683-695`). Global calls pass
  a string name and look it up (`src/macros.x:3013-3038`). This is existing
  transport capability, not evidence that source has first-class unapplied
  templates.
- Signature holes become `(macro-param (binder ?NAME|*NAME) (kind KIND)
  (sequence 0|1))` (`src/macros.x:3090-3130`). Duplicate parameter names are
  rejected. Sequence parameters must be last (`:3475-3480`). Kind is inferred
  from the first syntactic role and subsequent roles checked for compatibility
  (`:3138-3199`); kind-only-used-by-Lisp requires annotation (`:3668-3679`).
  Expr, Name and Literal can supply expression roles; Statement is canonicalized
  to block; Decl may supply field/block/unit; Function/NamedType may supply unit
  (`:3058-3082`). A typed hole is a grammar-category contract, not an Expr's
  semantic C type restriction.
- Parsing each hole occurrence yields `(macro-bind INTERNAL-PROJECTION)`;
  the definition-finalization walk eliminates these shells and macro-expr
  shells (`:3610-3626`). Projection is source/value/expression/splice, with
  return/declarator for Function decorator targets and construction requirements
  for Unit targets. `_capture_pattern` (`:2832-2887`) exposes only projections
  used by the body plus author binder for Lisp. `_capture_row` (`:2965-3011`)
  derives projections from captured source syntax. A Name value becomes
  `(expr () (ident NAME))` when used as an expression. Type substitution is
  list-splicing. Sequence rows contain ordered source/value Lists.
- The existing definition's `pattern` matches *invocation argument capture
  rows*, NOT expanded output syntax (`:2889-2912`, `:4101-4123`). Construction
  performs exactly one `template.replace(replacement_bindings)` then ordinary
  `Compiler.bind_syntax` (`:4121-4136`). Neither reversing that row match nor
  renaming `$x` to `?x` defines recognition of body output.
- Body-local declaration identities are allocated in lexical declaration order
  (`:2769-2781`), with tag namespace distinction. Local binders use ordinal
  `?__macro_local_N` or `?__macro_tag_N` (`:2741-2748`). The template conversion
  rewrites *all* occurrences of each identity to the same binder
  (`:2750-2767`, `:3641-3668`); source spelling is retained as a label in fresh
  rows (`:3680-3693`). Expansion allocates one identity per fresh row and uses
  it in declaration and every reference (`:4071-4091`). Already-existing
  lexical identity machinery therefore supplies the alpha-normalization input;
  do not rediscover bindings using a name-only walker.
- Tags only referenced by a template keep public spelling; declared/defined
  tags acquire template-local identity (`:2795-2812`, `:3643-3652`). Member Name
  holes project to spelling, not semantic binding (`:3917-3961`). This role
  distinction is essential: alpha-renaming a local cannot rename `.field`.
- Local macros retain preceding parameter/local definition-site identities:
  references record `captures` (`src/expressions.x:1377-1385`). At expansion,
  `local-macro-capture` prevents a same-spelled visible inner declaration from
  replacing the identity (`:1388-1403`); a private emitted alias solves native
  shadowing. In contrast ordinary stale local identities may resolve to a
  currently visible local. Unknown producer-issued identities are rejected
  (`:1341-1366`). Ordinary `Sym.reference` may create forward identities;
  `Sym.reference_global` explicitly keeps macro global references out of local
  scopes (`src/compiler.x:3002-3026`). Free identities cannot be collapsed by
  ordinal alpha-normalization.
- Captured argument syntax retains call-site identity. Source capture wrappers
  `(src (source FILE BEGIN END) SYNTAX)` are separate from semantic projections
  (`src/macros.x:3780-3820`). `_source_unwrap` removes them; provenance operations
  use captured Var identity, never structural equality (`:2529-2531`). A new
  recognition result must not claim source text merely because its shape equals
  a source capture.
- Nested macro invocations in template parsing defer as canonical
  `(macro-invoke STORED (args CAPTURE-ROWS) m-invoke)` (`:3964-3979`): STORED is
  quoted complete definition where available, local-macro marker or global
  name. `_invoke_definition` returns that node when macro_holes is active
  (`:4145-4157`). `bind_syntax` expands invocation when normally bound
  (`src/parse.x:2470-2473`), preserving source-order semantics and transactional
  rollback. Matching this invocation structure differs from matching expansion.
- Existing staged calls to Unit/block-item macros are `(expr ("List")
  (tpl-call STORED (args ARGUMENT-EXPRESSIONS)))` (`src/macros.x:4184-4198`).
  `src/stage.x:683-695` lowers them to `x2c_template_call`; that helper creates
  a deferred `macro-invoke`, not eagerly expanded syntax (`macros.x:3013-3038`).
  This existing route should be reused and extended, not described as already
  supporting arbitrary unapplied or Expression templates.

## Existing regression examples (not executed by this worker)

- `unittest/compiler-fixtures/macro-expression.x` uses one `$value` twice;
  checked-in `.ast` records the same `(binding 2 "value")` twice beneath `op +`.
- `macro-template-lexical-shadow.x` uses same-spelled typedef, enum, tag and
  value declarations in nested scopes and two expansions; expected output is
  `28 28`. This is unusually valuable compatibility coverage.
- `macro-local-lambda-capture.x` captures lambda parameter `base`, shadows it
  inside a block, expects `13 24`.
- `macro-match-binder-literals.x` ensures literal atoms named like internal
  projection binders remain literal. A recognition compiler must not blindly
  interpret every binder-shaped atom in body syntax as a metavariable.
- `meta-macro-body-call.x` demonstrates arbitrary meta computation embedded in
  a macro body. Its computation need not be invertible.

## Proposed minimal shared semantics

Keep the body canonical AST and retain existing hole descriptors and fresh
local map. Expose a structurally inspectable template List with metadata rather
than emitting a second pattern AST language. One *derived* recognition pattern
may compile this body to existing Match operators, but its authoritative source
is the body plus hole/identity-role metadata.

Construction replaces typed metavariable slots, freshens introduced local
identities once each, then binds through ordinary compiler ownership.
Recognition normalizes declaration-local identities in the candidate using
bindings already produced by ordinary compiler binding, aligns introduced
identities by declaration role/scope, and captures typed hole projections.
Definition-site free identities remain fixed semantic references. Hole-origin
references preserve call-site identities. Member/tag public names retain their
own role. The same metavariable occurring twice enforces equality after the
chosen normalization; it must not be conflated with an introduced program
variable occurring twice.

For example, `$twice(Expr $v) => $v + $v` has one metavariable slot; matching
`price + price` captures price, while `price + tax` fails. `$sum(Expr $a,
Expr $b) => $a + $b` has two independent slots. A statement template
`{ int temporary = $v; use(temporary); }` instead contains one local binder
slot and one metavariable. Recognition of `{ int renamed = price;
use(renamed); }` aligns local identity to local slot and captures price;
`use(other)` must fail even when its spelling resembles temporary.

Do not erase every `(expr TYPE ...)` field without an explicit stage contract:
parsed template nodes commonly hold macro-expr while candidates may be fully
bound/typed; exact List equality will otherwise fail for useful source syntax.
Recommend a syntax view that abstracts only compiler-derived type/source
metadata while preserving explicit types and binding relationships. A phase
label should distinguish deferred invocation structure from expanded syntax;
no automatic effectful expansion during match.

Projection reconstruction should derive source/value/expression/splice from a
single captured grammar value, not let independently captured projections
silently disagree. Runtime captures from recognized syntax should carry no
invented source provenance. Sequence recognition must specify ordered element
capture and deterministic partition; initial support can reuse final splice
restriction unless a compelling example needs multiple variable-width splices.

Remaining design choice: recognition of a fixed external identifier uses exact
semantic identity (recommended default) or an explicit call-site/unqualified
lookup projection. Names alone cannot identify free references in bound trees;
if matching prebinding syntax, ordinary compiler context must resolve such
references before semantic comparison.

## Cross-review of parent proposal

1. Literal binder-looking atoms must stay literal: canonical literal contexts
   quote Match payloads. Pattern compilation must recognize registered template
   slots by role/metadata, not recursively reinterpret all atoms.
2. A Name hole has declaration identity, expression identifier and member label
   projections; member labels cannot participate in local alpha-renaming. A Type
   hole occupies a List splice, not a nested scalar position.
3. Captured subtrees can reference declarations outside their own root. Alpha
   comparison of repeated holes must preserve this external binding interface.
   Example: `{ int outer; { int inner; use(outer); } }` and the same shape with
   `use(inner)` differ despite each captured identifier being the first reference
   in its capture. Captures need reference-to-enclosing-slot rebasing, not fresh
   local ordinal numbering for every capture.
4. Excluding type wrappers means ignoring inferred `expr TYPE` metadata only;
   explicit cast, declaration and parameter type syntax remains structural.
   Bound stages can also lower protocol dispatch and other syntax, so a clean
   parsed-vs-bound stage matrix is required. Bound syntax may have lost original
   surface structure; do not promise arbitrary lossless inverse lowering.
5. Free semantic IDs are compiler-session-local. Cached macro import definitions
   are already rebound via global reference spelling
   (`src/macros.x:1391-1414`). A transport plan must identify corresponding
   session context/rebasing rather than persisting raw binding integers as
   globally meaningful identities. This does not require opaque results.
6. Existing freshening owner is macro expansion before `bind_syntax`; moving it
   into the binder is a deliberate consolidation requiring compatibility probes,
   not an established capability. `Sym.define_macro` marks captured identities
   at `src/compiler.x:2808-2818`.
