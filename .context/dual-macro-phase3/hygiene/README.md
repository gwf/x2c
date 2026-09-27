# Phase 3: actual macro bodies, compiler identities and ordinary freshening

## Result and replay

The retained `audit.x` and `contextual.x` probes pass in the managed isolated
checkout `/Users/gary/.codex/worktrees/dual-macro-match-probe/x2c`. That checkout
contains the phase-2 parser3 patch and contextual runtime relation patch, with
baseline `1b23aaa7e103461c3b219b9e10546aeb35384b60`. This phase adds source probes
and helper functions only; there is no incremental compiler/runtime patch.
No production-root changes, fetch, commit, gate, push or merge occurred.

Replay there:

```
builds/0/x2c run --build-dir /tmp/x2c-dual-hygiene-audit .context/hygiene/audit.x
builds/0/x2c run --build-dir /tmp/x2c-dual-hygiene-context .context/hygiene/contextual.x
```

Final retained logs: `audit.log`, `contextual.log`. `helper.xmacro` extracts the
new fresh-row pattern derivation and origin projection. Each complete probe
embeds the phase-2 shared helper to avoid an external generated-header build
input; `phase2-helper-reference.x` records that prerequisite.

## What is now actual, rather than supplied model metadata

`hygiene_pattern` obtains the body through `Macro_pattern(t, names)`, where t is
the actual descriptor produced by the parsed source macro getter. It iterates
t's actual `fresh` rows and replaces each introduced declaration/reference
placeholder with `(binding ?identity_slot ?)`. Thus every occurrence shares one
identity capture and labels are ignored. The declaration positions and nested
scope graph remain the original parsed body. There is no hardcoded ownership
map, second name resolver or replacement program AST.

`hygiene_view` ignores known `at`/`src` metadata wrappers in both body and bound
candidate; it preserves literal values. The ordinary compiler already produced
candidate binding IDs and their reference graph. Match compares the resulting
structure, including explicit declaration types and rigid definition-site free
IDs. Expr derived type fields use the phase-2 pattern projection.

## Executed cases

`audit.x` asserts all of these:

- The source macro `$audited` declares `saved`, calls definition-site `audit`,
  and returns `saved`. Its derived body recognizes code declaring `subtotal`
  with the same reference graph. Using `observed` instead in the call rejects.
- Source macro `$nested` introduces shadowed outer/inner locals. A candidate
  using `outer`/`inner` matches. Referring to `outer` at the inner call rejects.
  A caller-local `external` shadows the global with the same label; matching
  its reference against the definition-site global rejects.
- Transparent pending construction returns the existing `"x2c.template"`
  marker inside a result List and uses an existing Statement spread. Existing
  `_sdk_template_call` creates typed capture rows; ordinary
  `expand_macro_invocation_node` allocates descriptor fresh rows and binds the
  generated code. Caller `saved=999` is preserved, generated saved holds42,
  audit sees42 and the function returns42.
- A useful source transformation recognizes an actual return using `$returned`
  and constructs `$audited` from its captured value. The resulting function
  evaluates `price+1`, audits42 and returns42. Generated C contains one fresh
  local and ordinary references to it.
- A declaration and a reference captured by DIFFERENT holes in `$cross` are
  reconstructed together. The declaration's owned binding is derived by
  matching the actual bound Decl production. A closed descriptor body is
  formed by applying the original shared body, replacing that exact owned
  binding throughout with a fresh placeholder, and adding an ordinary fresh
  row. The existing fresh owner allocates `_x2c_macro_carried_0`, and both
  declaration and later return refer to it; execution returns9.
- The same closed descriptor for declaration+audit is inserted twice. Ordinary
  expansion allocates two independent identities/names and keeps each copied
  reference attached to its copied declaration. Generated C has:
  `int carried=999; int _x2c_macro_carried_1=9; audit(_x2c_macro_carried_1);`
  `int _x2c_macro_carried_2=9; audit(_x2c_macro_carried_2); return carried;`.
  Execution returns999, observes9 and counts two audits.
- Two independent insertions of a fixed introduced saved declaration likewise
  allocate distinct names and preserve caller saved999.

`contextual.x` uses actual parsed `$repeated` and `$nested` descriptors. An
existing private literal-cache intrinsic exports compiler-bound source blocks
as a runtime List. There is one test-local Lisp expression for that transport
(`_x2c.literal.list`); the pattern derivation, comparison and execution are x2c.
The first captured nested block is compared with a wrong-shadow block and a
later renamed correct block. The contextual callback recognizes occurrences
using the actual nested descriptor and its fresh-derived identity captures;
it compares the logical initializer hole values. Actual Match rejects the
first candidate and retries the second. Assertions check at least two policy
calls, at least one rejection, one middle block captured, and clean teardown.
The callback invokes ordinary Match for candidate structure; it does not
implement another search algorithm.

## Failures corrected during the prototype

- Non-spread Statement helper insertion was the wrong staging shape. Returning
  a List of pending markers and using existing spread fixed it.
- The first nested recognition attempt retained template `at m-origin` wrappers
  while removing candidate origin wrappers. Projecting both sides fixed it.
- Writing `$prefix;` after a Decl hole created an actual empty statement in the
  body. `$prefix return...` describes the intended declaration then return.
- `List.search_replace` reached an unavailable compile-time callable on that
  pipeline. A direct generic identity substitution and ordinary descriptor
  field reconstruction avoids that dependency. This rejects that call route,
  not structural substitution or the shared-body architecture.
- A public prototype for the private literal-cache function was rejected by the
  reserved-name rule. The existing Lisp intrinsic works without compiler edits.

## Precise limitations

Fixed LOCAL OBJECT declarations, nested block scopes, definition-site function
and object references, one Expr hole, and one captured scalar Decl are exercised.
The source fresh rows establish local slots; complete public names/tags/labels,
aggregate members, multiple declarators, lambda capture regions and every scope
production are not covered. The captured-Decl rebasing adapter handles one
ordinary initialized or uninitialized scalar binding, not arbitrary declaration
regions; extending it must reuse ordinary producer-owned binding facts rather
than inventing a resolver.

The contextual callback uses a source template to describe the owned structure
of each repeated region. It is not a universal alpha relation for arbitrary
captured program forms. General private-hole declaration discovery and arbitrary
scope-boundary interfaces still need compiler producer metadata. Cross-hole
copying with a unique owned declaration is shown; ambiguous references to one
region copied twice still require explicit occurrence correspondence or failure.

Injectivity for arbitrary user-constructed candidate ASTs is not implemented
here; compiler-bound candidates used in the tests provide distinct declared
identities. General dynamic source Match adapters need the contextual policy
wired into their normal invocation path. These probes test it directly with
existing plans/machine and actual producer-derived data.

No full fixture suite, performance measurement, cross-domain persistence or
all-category self-hosting was attempted. Successful bounded cases do not imply
those results. Future production code should consolidate helper projection and
closed-descriptor construction into the shared existing owners, preserve ordinary
binding/typing, and remove prototype fallback sentinels/debug accommodations.

## Source-case capture adapter, additionally connected

`capture-helper.x` contains the capture worker's actual logical capture adapter
plus the hygiene additions. `source-case.x` includes that full helper and tests
ordinary source `case selected(?value, ?observer)` against compiler-produced
captured blocks. The selected descriptor is the actual parsed `$audited` or
`$nested`, not a separately authored pattern. Final replay uses the same
isolated checkout with the capture worker's incremental compiler patch applied:

```
builds/0/x2c run --build-dir /tmp/x2c-dual-hygiene-adapter \
  .context/hygiene/capture-adapter.x
/tmp/x2c-dual-hygiene-adapter/run
```

Both final executions pass, including a direct native exit-zero verification.
`source-case.log` records translation/build/run output.

The actual capture layout includes derived fixed local identity slots; the
existing logical publication adapter exports only formal hole captures in their
formal order. Every local identity pattern has `(!and ?slot ?slot)`: first
capture followed immediately by an ordinary repeated equality checkpoint.
The optional machine relation reads other already-captured fixed-local slots
and rejects identity aliasing there. This rejection enters the existing Match
failure/retry continuation, rather than post-checking a committed result.
A canonical candidate constructed by replacing the inner declared identity
and all its references with the outer identity fails recognition, establishing
injectivity without checking or authenticating its producer.

The source-case probe asserts that the exported observer's `(binding ID LABEL)`
List is identical to the record in the original code. Binding records and free
IDs are retained directly. Symmetric origin-wrapper projection is used; a
captured region containing those wrappers does not yet retain every original
wrapper. Full original-source association is a separate capture-interface item
and must not be claimed from this prototype.

Attempted origin-preserving alternative: `wrapper-pattern-fails.x` lowers
optional `at`/`src` forms into Match alternatives. The audit case prepares; the
nested case reaches existing `code-capacity` because nested alternatives repeat
child code. No Match fence was expanded. This rejects that concrete lowering,
not origin-preserving recognition generally. An engine-level source projection
or producer-owned correspondence interface remains a viable alternative. The
final helper routes nonprepared plans through existing `execute_capture` error
semantics before executing a machine, avoiding the rejected plan's null program.

This adapter's fixed-slot policy does not yet supply a universal repeated-hole
alpha comparator; the actual parsed nested-region callback in `contextual.x`
proves that relation separately inside the same Match engine. Combining the
policies and general capture-private ownership is remaining integration work.
Internal slot naming must also be separated from user-selected case labels in
a production interface; the prototype's generated labels are unique within its
bounded fixtures only.
