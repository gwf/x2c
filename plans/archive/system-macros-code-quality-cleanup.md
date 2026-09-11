# Classes and system macros: implementation cleanup

> Status: done
> Implemented 2026-09-11; delivered by the commit containing this archive.
> Reviewed baseline: dce252e. Documentation item delivered in 6dbd126.
> Code cleanup preserves existing behavior and adds no recurring checks.

## Result and scope

Make the recently added implementation more direct and idiomatic, removing
repeated conversions, searches, temporary collections, and reconstruction.
Code quality is the primary goal. Do not require a speed claim to justify a
clearer expression, or claim an end-to-end speedup from a source-level finding.

The confirmed cleanup items are in code introduced by the classes/system
macros delivery. The bounded surface is src/parse.x, src/compiler.x,
src/macros.x, and etc/builtin-macros.xlisp, plus their generated artifacts.
The guide opening in docs/src/guide/system-macros.md also needs to explain
why to use a class before presenting its syntax and detailed rules.
Adjacent existing code was inspected for reuse; one older candidate is recorded
below rather than silently expanding this into a repository-wide rewrite.

Further adoption of classes and system macros in src/ and lib/ is being
investigated in a separate task. It is not a dependency of this cleanup.

## Implementation results

All nine code items are implemented in the four planned source owners.
The storage alternatives use one structural match; managed and recipe rows
share output accumulators; forwarding and import rebinding skip empty work;
compiler state restoration uses $let; class helpers reuse field selections
and compute bitfield normalization only when needed.

Focused validation passed managed/class/declaration fixtures, the defer suite
(17 tests, 64 assertions), protocol boundary probes, and header-cache probes.
The header-cache probe initially exposed stale generated symbol metadata after
the Lisp input changed; documented symbol refresh resolved it. No generated
files were edited manually. Final publication uses the existing full gate.

## Agreed behavior to preserve

- Parsed and macro-constructed declarations use the same lowering owner.
  Bindings and declared types are already installed before managed lowering.
- Only a complete local initializer admits management; parentheses and typed
  expression wrappers preserve that position, while operators do not.
- Each successful acquisition is followed immediately by its cleanup
  registration, before the next initializer. Cleanup observes the binding at
  exit and unwinds in reverse order, including errors and returns.
- Automatic storage and explicit Cleanup adoption remain required. Ordinary
  method lookup accepts a direct cleanup method without adoption, so the
  conformance check is not redundant. Existing automatic-binding metadata is
  not a replacement for checking actual storage specifiers.
- Declaration recipes run once and all ordinary declarations become visible
  before defaults are selected. Discarded defaults do not bind bodies.
  Forwarding dependency rounds, private linkage, import hygiene, source
  context, and header-cache ownership remain unchanged.
- Class construction, boxing, equality, hashing, field order, formatting,
  error cleanup, and cycle handling retain their current contracts.

## Planned changes

### Managed declarations

1. Replace the three base.list().contains calls in finish_managed_declaration
   with one structural match:

   ```x2c
   match (base)
     case %(* (!or static extern threaded) *):
       c.report_error(
         <parse>, "managed initializer requires automatic local storage",
         c.token, NULL);
   ```

   A scratch probe compiled this pattern and compared it with the current
   expression on ten representative storage lists; all results agreed.

2. Replace recursive result construction and index-based slicing with one
   output accumulator and a forward walk over declarators. Preserve contiguous
   ordinary declaration runs; append each managed initialization and defer
   directly. Use a narrow managed-presence scan to return the original tree
   when unchanged, with no output allocation. Changed rows can then use one
   emission walk and a reusable ordinary-run buffer. This deliberately trades
   a second linear walk on changed input for simpler reconstruction and avoids
   repeated linked-list slicing. Keep macro-hole handling and the existing
   narrow initializer recognizer. Do not split ordinary declarations blindly:
   their aggregate bodies and grouping must remain intact. Do not replace
   explicit flattening with nested seq nodes that merely shift work into
   additional transform passes.

### Declaration projection and imports

3. Make _produce_declaration_rows append recursively into its caller's output
   Array instead of allocating an Array/List at every recursion level and
   immediately copying that List into its parent. Preserve depth-first source
   order and the lexical extent of macro-stack/privacy restoration.
4. Enter the forwarding loop only while forwards remain. Currently its do
   loop rebuilds every source's rows even when the pending Map is empty.
   Keep the existing dependency rounds and no-progress diagnostic; add no
   alternate work queue or derived state.
5. Replace the repeated save/assign/defer-restore blocks in recipe production,
   default selection, and forwarding with scoped $let operations. Match their
   current nesting and exception boundaries exactly. This is an idiomatic
   cleanup, not a claimed optimization.
6. In _rebind_import_definition, return the original definition when the
   collected replacement Map is empty. The existing substitution helper
   traverses and allocates temporary Arrays even in that case. Keep the
   existing two-pass discovery/substitution for nonempty replacements so all
   references to a selected binding identity change consistently. Limit the
   shortcut to this new caller; do not broaden an older helper's contract.

### Class expansion helpers

7. Compute the final field once outside the map in x2c._class.field-statements.
   Calling recursive last for each field currently adds quadratic list
   traversal during expansion. Preserve field order and comma placement.
8. In x2c._class.field-on, compute the normalized scalar type only in the
   bitfield-cast branch. Ordinary fields currently discard that filtered List.
   Preserve bitfield casts and const-member construction behavior.
9. Pass the already filtered named fields from x2c._class.defaults to
   x2c._class.new; remove the duplicate filter there. Keep the original full
   field list for layout eligibility, including unnamed fields.

### Explain why to use a class

10. Lead the classes section with the benefit: class packages a named type
    with the ordinary operations needed to construct it, use it through Var
    and generic containers, compare and hash it, and inspect its values.
    Explain that applicable defaults follow the chosen representation and
    explicit methods replace defaults. Pointer classes also receive Scope
    allocation and early-release/cleanup operations. Follow with one compact
    example showing construction, generic-container use, and readable output
    before the representation catalog. Keep detailed eligibility rules in
    their existing sections, with an upfront distinction between field-based
    value equality and pointer identity. Do not imply every class generates
    every operation, generates init, or recursively destroys owned fields.
    Review the opening as a standalone answer to why a user would choose
    class over writing the type and its supporting operations themselves.
    Include an explicit method inventory immediately after that opening:
    new, free, cleanup, var, the reverse Var converter, equal, hash, str,
    repr, write_str, and write_repr. Explain which representations generate
    each default, which inherit operations, and how explicit methods replace
    them. Neither the current guide nor reference supplies this complete
    inventory. In particular, init is required in some cases but not generated.

## Boundaries and deferred observations

The older _resolve_typedef_markers in src/generate.x repeatedly creates type
name Lists inside membership searches. History confirms this predates the
delivery. A direct membership operation may help, but the promotion algorithm
also preserves visibility dependencies. Leave this out of the current cleanup
until a focused prototype establishes a worthwhile, compatible simplification.

Do not change type reconstruction to a binding-facts lookup merely because
both representations exist; qualifier and alias equivalence has not been
established for every accepted constructed declaration. Keep that as an
unproven candidate rather than adding another accessor or representation.

Retain rendering-path scans, copied-value descriptor guards, deferred buffer
release, frozen-syntax escaping, and lazy import initialization. These protect
distinct identity, lifetime, error, and once-only evaluation requirements.
The older List width-dependent trial rendering is outside this cleanup.

## Implementation, verification, and delivery

After implementation is requested, make this one coherent cleanup. Use
temporary before/after probes for declaration grouping and generated output;
keep unmodified declarations allocation-free in the lowering and verify that
generated runtime operations do not grow merely to shorten compiler source.

Use existing focused coverage: managed declaration/defer tests (including a
failed later acquisition and constructed bindings), managed rejection
fixtures, class layout/runtime/cycle/lifetime fixtures, private-class and
forwarding probes, macro-import-projection, and the header-cache once-only,
default-precedence, retained-data, warm-cache, and symbol-mode checks.
Compare class output before/after to preserve formatting and field casts.
Use a wide-record scratch probe to confirm the repeated tail lookup disappears;
do not add a benchmark suite or promise an unmeasured overall speedup.

Review and fix the completed authored diff before publication validation.
Regenerate symbols, bootstrap, and API documentation only through repository
targets; review those deltas. Integrate current main, run git diff --check,
and use tools/gate-state.py ensure agent-pr-check on the final tree. Once
authorized and validated, deliver directly to main under the existing rules
and archive this plan with the result. No new recurring gate is proposed.

## Plan review

Existing binding owners establish names and types; existing placement and
protocol rules establish what managed declarations may mean. The plan keeps
their deliberate checks and changes how that meaning is expressed and emitted.
Projection phase order and header-cache ownership are retained, not inferred
away from passing tests.

The changes delete redundant filters, tail searches, intermediate collections,
empty work passes, and manual temporary-state restoration. A managed-output
emitter owns real declaration/defer sequencing; the recipe emitter reuses its
existing traversal with a shared accumulator. Neither introduces a generic
visitor, cache, validator, or alternate AST representation. Literal templates,
structural match, ordinary loops, and $let express the existing rules directly.

No new validator, dedicated diagnostic, negative fixture, or recurring process
requirement is proposed. Existing storage, Cleanup, forwarding, privacy, and
import diagnostics preserve deliberate public behavior.
