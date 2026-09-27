# Native-meta transport and syntax stages research

This note is read-only research except for this isolated workspace artifact.
Findings below are verified by reading current owners; no compiled feature
prototype is claimed here.

## Current contracts

- `src/stage.x:1-15` owns compile-time argument evaluation, the native-meta
  group, helper requests, returned code, and compile-time-only reachability.
  `src/meta-project.x:366-444` builds the helper before translation and selects
  its per-unit table. `etc/meta-helper.x` is its protocol loop.
- `Compiler.meta_argument` (`src/stage.x:152-192`) accepts constants,
  captured syntax, and nested explicit meta calls. A List parameter retains
  captured syntax; Type and Source parameters receive descriptions. This is
  not a general operation for obtaining a value for an unapplied macro.
- `src/macros.x:4152-4167` recognizes Unit/Statement-like macro calls in a
  meta-body expression and stores `(expr ("List") (tpl-call STORED
  (args ...)))`. A local macro carries its definition; a nonlocal macro
  carries its name. Expression macros still expand normally. This means an
  arithmetic Expression template cannot currently be passed as an unapplied
  template value simply by using an existing invocation expression.
- `src/stage.x:681-700` lowers tpl-call to `x2c_template_call` with value
  arguments. `etc/meta-helper.x:106-107` returns the ordinary List
  `("x2c.template" STORED VALUES)`. The compiler recursively resolves those
  Lists (`src/macros.x:2329-2338`) into its deferred invocation.
- `src/macros.x:3013-3029` resolves the definition, lifts Expr scalar
  arguments, constructs typed capture rows, and returns
  `(macro-invoke STORED (args ROWS...) m-invoke)`. This is a structural
  invocation, not expanded body syntax. `src/macros.x:3995-4012` expands
  deferred invocations and binds the result in the current AST position.
- `docs/src/guide/meta-functions.md:985-1019` documents constructor results
  as deferred code rather than expanded declarations. It does not justify
  preventing structural inspection of the invocation or of a separately
  exposed unapplied body.
- `plans/native-meta-execution.md:489` explicitly records an open proposal to
  make project-meta template results opaque. It has not established opacity
  as a necessary semantic contract. The user has now rejected that assumed
  requirement; the new plan should remove or supersede it explicitly.
- `lib/datum.x:1-14,52-109,169-206` owns ordinary List/Array/Map/scalar value
  transport. Atoms and Symbols preserve their distinction. Numeric families,
  token values, and special tag-shaped ordinary Lists have tagged spellings.
  Non-null pointer results are rejected; cyclic or aliased mutable
  collections are also rejected. Proper Lists are recursively transported.
  There is already a concrete data-only route for a transparent template.
- `etc/meta-helper.x:135-176` marks compiler-state queries unavailable. There
  are no nested callback requests in the helper protocol; do not promise
  that a helper can resolve unknown program names or types without changes.
- `docs/src/reference/language.md:1872-1894` states canonical AST Lists are
  public structural data, binding records visible but numeric IDs opaque,
  source provenance separate, and no authentication of producer origin.
  `agents/replacing-manual-ast-walks-with-match.md:1-29` makes ordinary syntax
  binding the owner of meaning, with Match as structural recognition and
  replacement owner.

## Recommendation

Represent an unapplied syntax template as a transparent List descriptor
containing its grammar result category, parameter descriptors, canonical body,
local-binder relationships, definition/capture environment and provenance
reference. This descriptor is a macro value, not a new representation of
ordinary program syntax: the body remains the same canonical AST grammar.
Fields are inspectable and can be constructed by ordinary meta code. Origin
must not authenticate who may use a structurally legal template.

Extend the existing macro-definition constructor rather than duplicating it.
Its fresh-local metadata already records which definition identities become
one fresh binding each expansion (`src/macros.x:3634-3691`). Preserve that
relationship for construction; recognition maps those same local binder
slots to candidate binders. The helper can compare the resulting structural
binding map without performing ordinary name lookup or type checking.

Unapplied template, deferred invocation, expanded syntax, and bound/typed
syntax are different values/stages. Do not expand automatically just to
match. Provide explicit stage selection and distinguish:

1. A template pattern compiled from its structural body: match canonical
   program syntax at the documented matching stage.
2. An invocation pattern: match template identity or structural template
   description plus its argument rows, even before body expansion.
3. Explicit expansion: requires current compiler position/context and uses
   ordinary macro expansion and `Compiler.bind_syntax` machinery.

`("x2c.template" STORED VALUES)` can remain an ordinary invocation envelope
or consolidate with canonical macro-invoke once typed argument rows can be
built without compiler calls. It must not masquerade as the expanded body.
Expose a template body directly through its descriptor, allowing helper
inspection even when expansion requires compiler context. Remove the need
for separate opaque handle behavior.

Matching bound syntax supports alpha-equivalence with local binder maps and
exact free binding identity. Matching unbound name syntax can support
structural spelling only or a requested lexical normalization pass; a helper
must not infer definition-site/free identity from strings. Prefer compiler
normalization at capture/definition boundaries using existing semantic
binding facts, then run structural comparison in ordinary library machinery.
Keep the normalized view alongside canonical body or derive it transiently;
do not feed a private normalized grammar to ordinary compiler binding.

Free binding references transported as existing binding Lists remain opaque
numeric identities but are inspectable structural references. Comparing their
numbers is valid only in the same originating compiler/session domain.
Do not promise globally portable IDs or persistence across symbol resets.
Existing `_rebind_import_definition` (`src/macros.x:1405-1415`) remaps global
references across resets by looking up names in the current global scope;
this is an existing rebinding boundary, not evidence that spelling alone
identifies distinct lexical locals.

## Anonymous template viability

Named and anonymous templates should produce the same descriptor. Anonymous
syntax needs no native Func closure; lexical syntax captures can be immutable
Lists inside the descriptor. A local syntax binding reference is captured as
its identity, not its spelling, and a captured tree preserves reference
relationships. This fits current datum transport. Native C pointers and
runtime closures should not be silently admitted: the helper lives in a
separate process, and compiler addresses are concretely rejected today.

Distinguish syntax closure capture from arbitrary runtime value capture.
A meta function may capture transportable computed data into holes; a program
runtime value is represented by syntax referring to its program binding,
not by evaluating that runtime value during compilation. Lexical references
remain usable only while their compiler domain/context remains valid.
List ownership can use existing Scope/Error snapshot/copy conventions rather
than inventing a template-specific allocator or lifetime service.

Composition should substitute a child descriptor/body into a typed syntax
hole and remap child local binder slots once per child insertion. Do not
flatten child free binding identities into parent locals. A meta function may
pass a transparent descriptor to another meta function without applying it;
no ordinary binding should occur merely because the value was transported.

Anonymous surface syntax is useful for inline transforms, but semantically
not required for the first implementation: an explicit named-template
reference operation plus ordinary descriptor-passing can exercise all core
construction/recognition machinery. This is a sequencing option, not a
proposal to omit the user's requested anonymous-template specification.

## Stage examples and must-fail cases

Using schematic proposed descriptors (field spelling not final syntax):

```
(template (kind expression)
  (parameters (left expr) (right expr))
  (body (expr () (op + (hole left) (hole right))))
  (locals ()) (captures ()))
```

The body node above illustrates hole slots; production should reuse existing
canonical macro replacement binders rather than literally add a second AST
language. `left/right` are parameter identities, not lexical declarations.
Applying it to canonical `a` and `b` yields canonical `(expr ... (op + A B))`.
Recognition returns `(left A) (right B)` for `price + tax`. It must fail for
`price - tax` irrespective of operand identities.

A deferred invocation stores this template plus `(left A) (right B)`;
recognition as an invocation can recover those argument rows. Recognition as
expanded arithmetic requires explicit expansion. An arbitrary compile-time
Lisp callback that computes the expansion has no reverse operation; its
invocation is matchable structurally, its output only as independently
specified structural syntax. A structural body containing a computation slot
cannot claim that slot is invertible.

If a template contains a definition-site free function reference `helper`,
its bound identity must match that exact external function; a candidate
shadowed local variable also spelled `helper` must fail. A template-introduced
local function or variable can match a candidate local with another spelling
only after its declaration/reference map is consistent. Capture projections
should retain candidate syntax/bindings and source associations, not convert
all captured identifiers back to strings for reconstruction.

## Focused validation and unresolved decisions

Use the existing datum tests to demonstrate transparent descriptor
serialization with repeated references, typed numeric fields and tag-shaped
Lists; add focused feature fixtures only as implementation work. Current
source confirms the route but this note does not claim a new runtime probe.
Test helper passing a descriptor through two meta functions unchanged; test
construction after its return in compiler context; test ordinary Match
inspection inside the helper before return. Test name collision and import
rebind cases separately from helper serialization.

Decide exactly which captured AST stage is available to helper Match. Current
macro-visible capture contract says parsed/typed syntax, but template bodies
contain unresolved constructs and binding-time forms. Some typed shapes
already incorporate conversions/lowering, so alpha-normalizing IDs alone is
not a universal way to recover source arithmetic. The specification must name
what is ignored, what is structural, and which operations have already run.

Decide whether descriptor carrying live free binding references is explicitly
unit/session-local, or whether a portable export form is needed. Portable
export requires qualified declaration identities and explicit rebinding;
it is not needed to demonstrate same-unit meta composition.

Decide whether context-requiring expansion is exposed only at insertion or
through a compiler-side operation before sending output back to the helper.
The latter entails helper/compiler callback architecture or a staged request
value; no evidence here warrants adding either to achieve transparent body
inspection.

Source diagnostics/provenance are not recovered by structural equality.
Preserve source association separately; matching/reconstruction may preserve
origin when captured nodes survive, but newly constructed descriptor Lists
must not claim source text merely because they equal existing nodes.

## Executed isolated evidence

After the root researcher completed `make build-safe`, I built and ran two
isolated x2c programs with current `builds/0/x2c`:

- `/tmp/x2c-dual-template-transport.x`: direct datum roundtrip of a transparent
  List descriptor with a body, repeated local-slot references, external
  binding row, and a nested tag-shaped List. Output:
  `descriptor roundtrip: structural equality; local/free references retained`.
  Exit 0. The slots/ID 912 are inert data in this probe, never compiler-bound.
- `/tmp/x2c-dual-template-helper.x`: native-meta `descriptor -> relay -> inspect`
  functions pass and inspect the descriptor body/relationships; the outer
  explicit `$pipeline()` returns the verified integer. Output:
  `helper descriptor inspection: 1`. Exit 0. This demonstrates actual helper
  computation and pure inspection, while direct datum probe demonstrates wire
  roundtrip separately; it does not claim a new first-class macro feature.

Authored probe sources are copied to this directory as
`transport-datum-probe.x` and `transport-helper-probe.x`. They are workspace
research artifacts, not shipped source or added recurring checks. Logs:
`debug/dual-macro-transport.log`, `debug/dual-macro-helper-transport.log`.

One failed probe used nested explicit `$inspect($relay($descriptor()))` in a
program initializer. It fails at parse time with `syntax cannot be constructed
at this position`: the current List-returning explicit call is consumed as
syntax before the proposed ordinary first-class value route exists. Changing
the meta pipeline to ordinary calls inside one meta body succeeds. This
failure rejects that attempted surface use only; it does not reject List
transport, helper inspection, or first-class template implementation.

Additional source-confirmed pitfall: `_helper_result` recursively converts any
matching `("x2c.template" STORED VALUES)` subtree into invocation syntax. A
new template descriptor containing such invocation data needs stage-aware
result handling to preserve inspectable deferred invocations until requested
expansion/insertion. Generic recursive eager marker interpretation must not
turn a body inspection or descriptor relay into an application.
