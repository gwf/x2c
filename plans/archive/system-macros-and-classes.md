# Classes and system macros

> Status: done
> Implemented on 2026-09-11 in the delivery commit containing this archived
> plan. Classes, system macros, declaration projection, rendering, the book,
> an executable example, and reviewed core adoption are complete.
> Design baseline: 245adc8; execution baseline: 38c3d79.

## Implementation outcome

SourceView now uses class construction with its existing Map initialization.
Reviewed List, Context, Lisp, and container-rendering operations use the system
macros while preserving allocation and cleanup ownership. Independent review
fixed source-private default linkage, source-qualified descriptor identity,
retained-data escaping, late recipe precedence, imported global references,
package-qualified reverse converter naming, and CPP collection order.

Focused verification covers 112 core tests with 1,026 assertions, 75 rendering
and runtime tests with 845 assertions, class and managed-initializer fixtures,
14 guide examples, the executable example, and once-only declaration production
with real header-cache reuse and invalidation. The delivery uses the existing
`agent-pr-check` publication proof; no recurring gate was added.

## Result

Ship one discoverable set of system-wide conveniences: `class`, `$scope`,
`$let`, `$lock`, and `$auto`. Keep their authored definitions together in the
existing built-in macro bundle. Reuse ordinary x2c types, methods, protocols,
allocation, binding, and defer lowering. Document how to use the conveniences
separately from how to author macros.

This includes the full class abstraction, not just separate constructor and
Var-conversion generators. It includes value types, explicit heap pointers,
typedef-derived classes, constructors, early `free`, boxing, readable output,
and user methods that replace defaults without redefinition.

No new generic iterator-storage syntax is planned. Do not replace unrelated
cleanup, lock policies, or lifetime code solely because a scanner found a match.
The older .context discussion files are evidence and conversational history;
this plan owns the current proposal, including the changes from heap-only class
syntax and declaration-prefix cleanup to value classes and RHS `$auto`.

## Repository organization and availability

| Responsibility | Owner |
| --- | --- |
| Shipped macro definitions and `keyword class` | `etc/builtin-macros.xmacro` |
| Nontrivial canonical syntax construction | `etc/builtin-macros.xlisp` |
| General Lisp syntax helpers | `etc/compiler-sdk.xlisp`, when genuinely reusable |
| Compiler-dependent macro operations and installation | `src/macros.x` |
| Named type capture and managed local initialization | `src/parse.x`, `src/expressions.x`, `src/statements.x`, existing binding owners |
| Public declarations, source ownership, default selection | `src/compiler.x`, `src/collect.x`, `src/protocol.x` |
| Cleanup contract | `lib/protocols.x`; adapters in the corresponding runtime modules |
| Var boxing and dispatch | `lib/var.x`, `lib/dispatch.x`, existing tag definitions |
| Source documentation discovery | `tools/x2c_source.py`, `tools/x2c_symbols.py`, existing API/catalog generators |
| User guide | New `docs/src/guide/system-macros.md`, linked from authored `SUMMARY.md` |

`Compiler.install_builtin_macros` already installs an embedded source pack
during shallow and full parsing. The pack contains `$x2c.foreach`, its
`foreach` alias, foreign-function aliases, and callback adapters. Extend that
loader, embedding and dependency path. Do not add an alternate macro registry,
a per-file import requirement, or a hand-written addition to generated `lib/x2c.x`.
Keep heavy compile-time Lisp initialization lazy. Installing a macro does not
eagerly include every runtime module it could call: ordinary runtime declarations
must still be available when an invocation is bound.

Public spellings are the accepted short names. Only `class` gets a bare keyword
alias; do not introduce bare `scope`, `let`, `lock`, or `auto` aliases. Existing
macro collision diagnostics and built-in alias policy remain in force. Imported
user packs keep source-local aliases and normal dependency tracking.

`with` is contextual grammar in `src/statements.x`, not currently an ordinary
macro. Its alias substitutes the source expression on each use and creates no
runtime temporary. Group it with the system conveniences in the book, but do
not change its evaluation behavior or rewrite it as `$let`. Keep private `loop`
in `lib/private-keywords.xmacro`, and keep Logger's synchronized decorator with
Logger's private lock/error policy. This work does not make every private macro
globally available.

## Accepted block conveniences

### `$scope`

No argument creates a retained region. Preserve the specifically agreed shape:

```c
macro Decorator $scope(Block $body) => {
  {
    Scope.retain();
    {
      defer Scope.release();
      $body
    }
  }
}
```

This illustrates one branch of the combined definition. The actual definition
accepts zero or one explicit Scope-pointer expression, using the existing final
sequence-argument facility and a branch in the macro helper. More arguments are
an invocation error, not an additional runtime overload.

With one argument, replace retain/release by `Scope.push(argument)` and
`Scope.pop()`, preserving the same body placement. Evaluate the argument once.
Pop restores the previous destination; it does not release the selected Scope.

```c
$scope() for (int i = 0; i < n; i++) { work(i); }
for (int i = 0; i < n; i++) $scope() { work(i); }
$scope(&destination) { create_in_destination(); }
```

The first form has one region around the loop; the second has one per iteration.
No loop-specific macro or hidden loop is needed. Break, continue, return and
error behavior follows the decorated statement and ordinary defer boundaries.

### `$let` and `$lock`

The tested template shapes are:

```c
macro Decorator $let(Block $body, Expr $place, Expr $value)
  using $address, $previous => {
  {
    $(x2c.syntax.type $place) *$address = &$place;
    $(x2c.syntax.type $place) $previous = *$address;
    defer *$address = $previous;
    *$address = $value;
    $body
  }
}

macro Decorator $lock(Block $body, Expr $mutex) using $held => {
  {
    $(list "Mutex") $held = $mutex;
    $held.lock();
    defer $held.unlock();
    $body
  }
}
```

The `$lock` template deliberately constructs its named type at invocation.
A literal `Mutex` declaration in a template can fail during built-in pack
installation, before runtime typedefs exist. Deferred type syntax preserves
the Mutex contract without eagerly importing its runtime module or accepting
arbitrary objects merely because they have lock/unlock methods. Exercise pack
installation with minimal globals as well as an actual Mutex invocation.

`$let` requires an addressable, assignable place whose storage survives the
body. It restores that captured storage even if another variable used to locate
it changes later. Ordinary typing rejects const assignment and taking a bitfield
address; no new lvalue validator is needed. `$lock` registers unlock only after
lock succeeds, and preserves Mutex's error behavior. Specialized Pool, descriptor
and file-stream locks require their own equivalent operations; do not convert
them all to Mutex or weaken conditional acquisition.

## `$auto`: managed local initialization

```c
Array items = $auto(%[]);
File input = $auto(File.open(path));
Sample sample = $auto(Sample.new());
```

Lower to the original local declaration followed by a deferred call to its
type's cleanup operation in the same enclosing block. Evaluate the initializer
once and register cleanup only after it succeeds. Preserve the local's type,
identity, visibility and ordinary initialization conversions. Do not introduce
a nested block that shortens its lifetime or a hidden handle with different
reassignment semantics.

The contract is the familiar declaration-plus-defer pattern: the deferred call
observes the declared binding at cleanup time. Reassignment does not implicitly
dispose the old object; returning or storing an alias does not cancel cleanup.
Users retain explicit lifetime responsibility, just as with direct defer.
Explain this with one example in the book rather than inventing a move system.

Initial supported position: the complete initializer of an initialized local
declaration that is a compound-statement item. Parentheses and macro expansion
do not alter that position. Static storage, field initializers, assignment,
return expressions, call arguments, for-header declarations, and wrappers
nested inside arithmetic/conditionals are outside that enclosing-block contract.
Use the ordinary AST-position boundary to reject them. This is an explicit
source-position restriction, not an origin check: equivalent constructed AST
is accepted in the same position. Compound declarations must preserve each
initializer and cleanup's source order; do not release an earlier successful
resource only after a later initializer has succeeded.

Add a small `Cleanup(T)` protocol with `void T.cleanup(T)` and ordinary adapters:

| Type family | Adapter action |
| --- | --- |
| Block, Array, Map, Buffer, Mutex | Existing `free` |
| File, Context | Existing `close`; discard any result as defer did |
| Scope, Lisp | Existing `destroy` |
| Generated heap classes | Their selected `free` |
| Other runtime/user types | Explicit compatible adoption/adapter |

Follow typedef/protocol ancestry and explicit method precedence. Audit typed
container families through their existing generated operations. Add the other
already-supported one-resource cleanup adapters needed by verified migrations,
such as MachineBuilder. Do not infer cleanup by method spelling: `Pool.free`
takes an additional allocation argument. Var itself is not an owning cleanup
type merely because it may contain an object. No wildcard dispatcher frees
arbitrary Var payloads or native pointers.

Implement `$auto` as a macro producing an ordinary constructible managed-
initializer AST form. The declaration binder consumes that form, binds the
initializer and declared type normally, resolves Cleanup, and appends an
ordinary defer. The exact internal tag is an implementation detail. There is
no runtime `$auto` helper and no cleanup at expression exit. Fix the observed
declaration-binding loss through the shared binding owner if that path is
reused; do not bolt on a second name table for this macro.

## Class syntax and representation

Accepted grammar is name first, without an equals sign:

```c
class Int int;
class IntPointer int *;
class VarPointer Var *;
class Values Array;
class Point { int x; int y; };
class HeapPoint struct { int x; int y; } *;
class Sample struct { int count; Var value; Array history; } *;
```

`class Name { fields };` is always available and abbreviates the corresponding
value `struct` definition. Curly braces are deliberate. The full RHS accepts
ordinary type/declarator structure, including qualifiers and explicit pointer
shape. A value representation does not force stack storage. Do not add
inheritance fields, runtime prototype objects, or an implicit heap allocation
to `class Values Array;`: it follows the existing Array type chain.

`class Name;` is accepted as a forward declaration. Proposed completion rule:
reserve a class type identity without guessing value versus pointer shape;
its visible definition supplies that shape before layout or generated operations
are needed. Collect all participating definitions before emitting the necessary
C struct/typedef forwards. An unused unresolved forward need not emit an
invented representation. A required but unresolved layout uses ordinary
incomplete-type handling. Confirm forward-provider/import behavior in the
declaration projection probe rather than quietly defaulting every forward to
a pointer.

The general new macro target must capture a name and complete type definition,
not only a struct body. Reserve the name before binding fields, then complete
its representation from the RHS, whose pointer suffix may follow the body.
Retain named binding identities while the shape is incomplete. Reuse ordinary
field parsing, canonical aggregate nodes and declarator handling; do not parse
fields as a separate class mini-language. A value aggregate cannot contain
itself by value; existing layout/type rules still apply. Self-referential heap
fields can name the reserved class identity.

### Constructor and free selection

Select an explicit `new` before generating its default. Explicit constructors
may have a different parameter list. They suppress the generated initializer
call and its required-init obligation. Other independently applicable defaults
remain available.

For a class naming an existing class/type with a constructor, forward to the
nearest parent's constructor with its existing arguments and result converted
through the ordinary typedef relation. Preserve parent cleanup. Array is the
example: it aliases Block, but its explicit no-argument new specializes
`Block.new(sizeof(Var))`. Do not replace that with a zeroed Block allocation.
Existing receiver ancestry works for `.free()`; a probe showed type-qualified
`Child.new()` needs a generated forwarding declaration. Variadic parent
constructors require a real existing forwarding facility or an explicit child
constructor; do not synthesize an invalid C varargs forwarding function.

For newly defined value and explicit heap representations:

| Shape | Generated new |
| --- | --- |
| Native scalar value | Accept and return that scalar value |
| Pointer to an eligible value, such as int or Var | Accept the pointee value; allocate sizeof pointee; initialize; return pointer |
| Flat aggregate of accepted value fields | Positional field arguments in declaration order; return aggregate or allocate/copy it according to representation |
| Aggregate containing a non-value field or non-flat layout | No arguments; zero initialization; call required init; return after success |

Accepted positional field types include native numeric scalars/enums, Symbol,
Var/Atom, String, List, and their typedef aliases. Array, Map, Iter and heap
class handles select the required-init branch; do not equate pointer shape
with semantic value. Nested aggregates and arrays are non-flat. Inspect all
captured fields, not only named-field reflection, so anonymous members do not
vanish from the classification. Preserve field qualifiers and modifiers.
Named numeric bitfields can project to their scalar parameter type; unnamed
padding takes no argument. Existing legality rules govern initialization.

Heap example:

```c
Sample Sample.new(void) {
  Sample sample = Scope.calloc(1, sizeof(*sample));
  sample.init();
  return sample;
}
void Sample.free(Sample sample) => Scope.free(sample);
```

For a value aggregate, zero a local value and call `void T.init(T *)` through
ordinary address-receiver semantics before returning it. For a heap class the
contract is `void T.init(T)`. Init may allocate subobjects but receives the
already-created main object. Missing or incompatible required init fails
through ordinary call/protocol checking even if new is unused. Failed init
does not return an object; no automatic transactional rollback of arbitrary
user side effects is promised. Enclosing Scope/defer semantics still apply.

Prefer aggregate initialization followed by Scope.memdup for flat heap records;
it preserves const fields without writing through const members. Non-flat const
members that cannot be initialized by init require an explicit legal constructor,
not qualifier erasure. Var pointees are shallow copies of Var slots, not deep
copies of their payload objects. Pointers to runtime containers do not authorize
copying or inventing the container's internal storage.

Every generated Scope-allocating constructor gets a replaceable early `free`.
Pointer-defined heap classes have the Scope allocation contract; a custom new
that changes that contract must also provide compatible cleanup. No constructor-
body analysis attempts to infer allocations. Derived classes preserve parent
free, including backing allocations. Value construction adds no heap free.
Do not infer recursive ownership of fields, register free as a Scope finalizer,
or require destructor hooks: Gary means optional early release, with ordinary
Scope reclamation otherwise.

### Defaults, boxing and printing

Maintain default candidates separately from ordinary method definitions, using
canonical constructible semantic rows. Any macro or Lisp producer may construct
the same rows; there is no generated/authored authenticity flag. Resolve after
all segments of the owning source are collected, before protocols/bodies:

1. An ordinary local declaration wins.
2. Applicable existing ancestor methods retain ordinary precedence.
3. Generate only the remaining applicable defaults.

Only winning bodies are bound and emitted. Two ordinary definitions still
conflict. A consumer cannot replace a provider's exported class defaults from
an unrelated importing module. Imported headers and cached/live declarations
must agree on the selected signatures.

Generate forward/reverse Var conversion and protocol participation using the
existing representation owners. Scalar and derived aliases reuse their existing
representation where appropriate. A new heap class boxes its object identity.
A larger value aggregate boxes a Scope-owned copy and unboxes by value; never
store a pointer to a local temporary. Qualifiers, size and alignment use ordinary
type facts. This work does not promise deep copying, pool promotion, or new
ordering semantics beyond the chosen existing contracts.

Gary approved generating compatible field-based equal/hash methods for copied
value classes with supported value fields, with explicit methods required for
opaque layouts. Current Var fallback behavior compares boxes by identity, so
leaving these defaults out would make two conversions of the same Point unequal
map keys. Heap-class identity behavior remains unchanged. Verify two independent
boxes used for map insertion and lookup, and preserve the invariant that equal
values have equal hashes. The methods participate in ordinary default selection;
explicit overrides must retain a compatible equality/hash contract.

`str` and `repr` are independently replaceable. Heap str uses pointer identity.
Repr enumerates fields in declaration order using each printable value/type's
readable output, with an address fallback for opaque fields. Reuse current
descriptor repr/write_repr dispatch so nested container output honors overrides.
Do not dereference unknown pointers. Literal-like output with addresses is not
a serialization or object-graph reconstruction guarantee.

Finishing recommendation for value representations: scalar/derived value types
retain their parent's printing; a new aggregate value's default str delegates
to its generated repr. Values have no stable heap identity to print. This
completes the later value-class extension without returning a temporary address
or allocating a box merely to obtain an address for str. Heap pointer printing
remains exactly as selected by Gary. Document this recommendation for review.

Cycle policy is accepted: a repeated identity on the active expansion path
prints its pointer form. Noncyclic repeated references print fully. Use one
thread-local, defer-restored active rendering path shared by generated class
printers and existing Array/Map/List traversal; a class-only guard would miss
a self-containing Array. Add the guard at the actual recursive printer owner
so direct and Var-dispatched calls do not double-enter the same object. Reuse
Buffer streaming; avoid building a generic reflected heap graph. Restore state
on error, nesting, and a subsequent independent rendering call. User custom
printers that recurse directly outside these operations retain responsibility
for their own recursion.

### Public declaration discovery and existing limits

Class output needs a declaration projection that includes its type, method
signatures, defaults, and protocol adoptions. Current decorator collection keeps
the unchanged target, and ordinary Unit shallow expansion can execute again
during full parsing. Neither behavior is sufficient for the new declaration
facility. Do not simply teach the shallow scanner to recognize the word class
or execute user Lisp twice to obtain the public surface.

Plan a canonical declaration bundle containing the named type, candidate
declarations/body recipes, locations and dependencies. It belongs to the
existing owning-source declaration data, and the full binder consumes that
same result. Macro/field/Lisp effects in producing that declaration run once
per compilation path, while generic binding/emission runs in its normal phase.
Snapshots preserve equivalent declaration data and dependency invalidation;
there is no process-global expansion cache or source-template eligibility test.
Equivalent literal-constructed bundles must work exactly like macro output.
Existing unrelated Unit macros/prototypes are not migrated by this change.

Before production edits depend on this facility, build a provider/consumer
spike with a stateful compile-time producer, a nested macro, a late custom new,
and a forward/self-reference. Verify declaration, naming, dependency and
diagnostic parity across snapshot, live and cpp-symbols paths. This tests a
necessary architecture boundary, not an additional recurring gate. If the
bundle cannot reuse source declaration ownership without a second AST lifecycle,
revise this part of the plan before extending the implementation.

Existing Var object registration has 32 custom rows and freezes at worker
startup. Keep current encoding and registration timing in the initial design;
do not pretend a class macro removes those runtime limits. Use the existing
explicit tagged descriptor path and a deterministic, round-tripping compact
Symbol derived from the canonical owning source and full qualified class name.
Root-relative source paths preserve reproducibility across checkouts; source
identity keeps identically named private classes separate. Preserve the full
name for output and collision diagnostics; collisions must not merge types
silently. Reuse an existing hash
and Symbol encoder rather than adding another hash implementation. This tag
selection is a proposed finishing detail, not a promise of an unlimited registry.
Check registration success through the existing error owner, including exhaustion.
Audit the actual registration count before migrating core types. Expanding the
Var encoding/capacity is a separate consequential change if that audit requires
it; do not hide it in class lowering or silently disable class boxing.

## Implementation sequence

1. Establish the canonical named-declaration projection and managed-initializer
   lowering in existing owners. Prove binding preservation, source visibility,
   once-only declaration production and snapshot/live parity. Stage bootstrap
   support before any compiler source begins using the new syntax.
2. Extend the shipped macro bundle with `$scope`, `$let`, `$lock`, and `$auto`.
   Add Cleanup and explicit runtime adapters. Keep helper operations generic
   and expose only the SDK contracts another macro can use; no name-special
   cases for these five spellings.
3. Add class capture, representation completion, parent constructor forwarding,
   default selection, required init, explicit free and Var conversions. Complete
   the compatible tag registration path before broad adoption. Add shared
   rendering-path support and both printers, including value-copy boxing.
4. Adopt the features at verified core sites and create one executable example
   covering the class representations and the macros together. Preserve custom
   construction, cleanup and conditional locking policies. Make the authored
   book changes and the exact language/macro-visible reference additions.
   Update source documentation discovery for class declarations and verify its
   consumers against the compiler's selected public declarations.
5. Review and fix the complete authored diff for reuse, unnecessary machinery,
   compatibility, and idiomatic x2c; then run the existing publication proof
   when implementation/delivery is authorized. Review generated deltas too.

The order expresses dependencies, not a requirement for five PRs or five broad
gate runs. Do not migrate source into syntax the bootstrap cannot yet consume.
Use existing regeneration targets for bootstrap, lib/x2c.x and generated docs.

## Corpus and migration boundary

| Feature | Evidence and suitable first adoption |
| --- | --- |
| `$scope()` | Unified loop/body probes passed; retain/release sites across core, examples, tests and packages are distinct lifetime cases |
| `$scope(pointer)` | About 11 unconditional handwritten core push/defer-pop pairs; exclude conditional and cross-operation scope protocols |
| `$let` | About 15 direct save/set/restore sites plus four variants; List.write_str is a clear first example |
| `$lock` | No plain Mutex caller pairs in the core survey; about 15 specialized pairs need owner-specific review; Logger already has 21 synchronized uses |
| `$auto` | 44 adjacent declaration/receiver-cleanup candidates: 35 Array, four Block, two Context, one each File/Buffer/MachineBuilder; includes some compound declarations |
| `class` | 41 scalar Scope-allocation sites across 36 struct tags and 10 simple Var converters, overlapping candidate sets rather than verified migrations |

For class, start with simple fixed-layout objects whose construction, cleanup
and registration contracts match. Buffer needs its padding argument and two
backing Blocks; Context has rollback and destination state; Func allocates
variable-size payloads; Pool may allocate into a selected Scope. Preserve their
custom operations even if their type declaration can use class. Do not claim
36 full constructor replacements or impose class on caller-owned Iter storage.

## Book and discoverability

Add **Classes and System Macros** before **Compile-time Macros** in the authored
Language Guide TOC. A new chapter is recommended after considering expansion:
the existing macro chapter is about 607 lines and teaches authoring, whereas
these facilities need a coherent usage guide. The new chapter should contain:

1. An availability table: shipped `$` macros, the class/foreach keyword aliases,
   contextual `with`, and explicitly imported project-specific macros.
2. Value, pointer and inherited class examples; positional versus init-based
   construction; custom overrides; early free; boxing copies; str/repr.
3. Both `$scope` forms and both loop placements, with the actual expansions.
4. `$let`, `$lock`, and RHS `$auto`, including evaluation and cleanup lifetime.
5. One complete resource-using example and the boundaries of automatic behavior.

Update existing chapters with focused links/examples rather than duplicating
their contracts: memory for retain/push/early-free; exceptions for cleanup on
transfer; protocols for Cleanup and class participation; idioms for replacing
boilerplate; macros for how the shipped definitions use ordinary facilities.
Keep precise grammar, positions, default selection, visibility and constructible
AST contracts in reference/language.md. Update the language tour or add one
example to examples/manifest.txt. Generated module/API pages stay generator-owned.
Teach `tools/x2c_source.py` to recognize class declaration spans and attach their
documentation, without copying class type checking or default selection into
the text scanner. `tools/x2c_symbols.py` continues to obtain authoritative type
facts from `etc/header-symbols.xlisp`. Audit `gen-api-reference.py`,
`gen-module-catalog.py`, and other scanner consumers for the new declaration
shape; extend the existing scanner tests where their output changes. Generated
methods and custom overrides must appear once with the selected signatures.
Verify the new TOC link, cross-links and example compilation through existing
documentation tooling when implemented. No site redesign is part of this plan.

## Verification and current evidence

Existing /tmp probes established the ordinary lowerings, not the new grammar:
scope-unified.x and blocks.x exercised loop placement, cleanup on return/error,
single evaluation and lock release; construction.x exercised zero/init, boxing
and failed-init behavior; init-contract variants proved missing/incorrect init
rejection; const-fields.x proved aggregate-copy initialization; parent-constructor.x
proved explicit forwarding with inherited cleanup; int-pointer.x proved scalar
allocation/free; str-repr.x proved separate printing with nested objects and
opaque-field addresses. The declaration-prefix cleanup probe failed to retain a
usable type for a following method call. Neither cycle-safe generic printing,
value-aggregate boxing, class default selection nor `$auto` binding is already
implemented by those probes.

Add focused cases to the existing macro/compiler/runtime suites for:

- All accepted class forms, forward/self-reference, aliases, positional order,
  zero-before-init, exactly-one init, parent forwarding, late independent
  overrides, qualifiers, value-copy boxing and early versus Scope release.
- Missing required init, incompatible protocol method, duplicate explicit
  definitions and invalid managed-initializer positions through their ordinary
  semantic boundaries. Do not invent exhaustive recursive AST validators.
- Nested and direct/boxed repr, Array/class cycles, repeated acyclic references,
  error restoration and concurrent independent rendering.
- `$scope` whole-loop/body placements, push restoration, `$let` address/value
  evaluation and error restoration, failed lock acquisition, `$auto` successful
  versus raising acquisition and reverse cleanup order.
- Built-in installation before runtime type declarations, then invocations
  after ordinary imports; source documentation discovery for class forms.
- Provider/consumer defaults and source-private boundaries; nested/Lisp-created
  declaration bundles; source segments; dependency/header-cache invalidation;
  default, live and cpp-symbols parity, using existing harness paths.

Run focused checks while they answer a current question. At implementation
publication, integrate origin/main, review the final tree, run git diff --check,
and use `tools/gate-state.py ensure agent-pr-check`. Do not add a recurring
gate or separately repeat its broad components. Implementation and normal
delivery are authorized; changing host toolchains is not.

## Plan review

Ordinary parsing/binding owns names, types, aliases, qualifiers, layout and
source positions. Protocol resolution owns member compatibility and ancestry;
Scope owns allocation/reclamation; defer owns exit/error cleanup. New consumers
reuse those facts. The class classifier distinguishes the deliberate semantic
value families before reducing typedefs to native representations, and examines
the complete captured layout once. It does not infer pointer ownership.

Reuse the installed built-in pack, canonical aggregate/declaration/function AST,
existing source-declaration storage, protocol defaults/descriptors, generated
container printers and ordinary early-free APIs. The necessary new mechanisms
are a named type declaration/projection consumed once, deferred default candidates,
initializer-to-enclosing-defer lowering, and a shared active printing path. Each
serves an accepted behavior that existing shallow capture, expression expansion
or unguarded recursion cannot implement. There is no alternate parser/backend,
global expansion-result cache, origin-authentication flag, wildcard finalizer
registry, or automatic field-ownership traversal.

The result stays idiomatic: explicit types and methods, ordinary constructors,
small template macros, a normal cleanup protocol, and canonical Lisp construction
only where declaration structure requires it. Generated declarations are not
privileged because they came from the system pack.

Deliberate diagnostics protect the accepted contracts: required init; compatible
protocol overrides; legal managed initializer position; valid named-type layout;
valid invocation arity; and existing tag registration failure/collision rules.
Prefer the existing error at each producer/boundary. Negative cases verify those
public contracts and prevent missing cleanup, wrong signatures or merged runtime
types; they are not additional validation passes. Cycle handling prevents
unbounded recursion in the promised recursive representation. No new recurring
test, planning, build or publication requirement is proposed.
