# Component authoring study

> Status: retired
> Historical authoring study. See [the active plan](../language-components-foundation.md).

> 2026-10-08, branch `gwf/language-components`, compiler at 0e61a65d.
> This records executable authoring probes and the missing connections they
> expose. It does not claim that automatic pattern registration or complete
> feature extraction is implemented. This first study predates the executable
> [second spike](../../experiments/language-components/README.md), which records
> subsequent compiler changes, successful clients, and corrected assumptions.

## What an author can already write

These examples use one macro definition for construction and recognition,
and code literals for replacements. Current probes use List where Code has
not been declared; `typedef List Code` also works in the replacement probes.
Old SDK calls in evidence are identified explicitly, not proposed as the
final authoring interface. Complete probe files and logs are saved under
`.context/language-components/authoring/` in this worktree.

### Registration through a decorator

This author-written part compiles today:

```x2c
macro Expression $sum(Expr $a, Expr $b) => $a + $b;

macro Decorator $rewrite(Unit $function, Expr $shape) {
  @register_probe($function, $shape)
}

$rewrite($sum)
meta List flip(List code) {
  match (code) case $sum(?a, ?b): return $!($b + $a);
  return code;
}
```

The probe's registration helper is also complete:

```x2c
meta List register_probe(List function, List captured) {
  Macro shape = x2c_pattern_value(captured);
  int family = 0;
  match (shape.assoc(<template>))
    case $sum(?a, ?b): family = 1;
  if (family != 1 || x2c_function_name(function) != "flip")
    x2c_diagnostic_fail("registration capture failed", %());
  return %($function);
}
```

The check succeeded and an explicit macro call to `flip` produced 7 from
`3 + 4`. This proves decorator capture, delivery of a macro-valued argument,
classification through a macro metapattern, and preservation of the function.
It does not install a registry or intercept an ordinary plus expression.
The reversal is a recognition probe, not a proposed addition feature.

Three distinctions matter for the final interface:

- An Expr argument holding a Macro arrives as captured constant syntax.
  The existing pattern-value operation can recover that constant value.
  Code needs the corresponding value query, without naming a pattern-lowering
  package merely to read a Macro constant.
- Classification examines the macro template's code. Matching a derived
  Match pattern against a source metapattern failed: the derived pattern
  quotes operators for matching. The source templates classified as plus and
  multiply correctly. These are different representations, not interchangeable
  Lists. Macro should own access to its code and pattern derivation.
- `return %($function)` returns a sequence of declarations for the decorator
  splice. It does not construct an AST node or invent a `seq` representation.

The minimal new registration operation must associate a macro pattern with
an identity-preserving function reference in the current compilation scope.
It owns source/include ordering and derives its dispatch key from the macro.
The decorator above is library syntax around that operation, not a keyword.
Its exact name is not established by this probe.

### Dot calls: construction, matching, and quoted calls

```x2c
macro Expression $dot(
  Expr $receiver, Name $member, Expr @arguments
) => $receiver.$member(@arguments);

meta List direct(List receiver, String member, List arguments) {
  Macro dot = $dot;
  List code = dot(receiver, member, arguments);
  match (code) case dot(?object, ?name, *args): {
    List callee = x2c_method_resolve(x2c_syntax_type(object), name);
    return $!( $callee($object, @args) );
  }
  return code;
}
```

A Payload containing 7, with a `read` method that adds its argument,
produced 9. Generated C calls `Payload_read(p, 2)`. The macro definition
both constructed the code and recognized its receiver, member, and arguments.
No hand-built call AST is necessary.

This is deliberately not presented as full method extraction:
`x2c_method_resolve` currently calls the kernel's whole member algorithm.
Renaming it `Type.method` would hide that algorithm rather than extract it.
A complete dot component must express owner traversal, method/field
precedence, imported candidate choice, protocol selection, receiver adaptation,
and construction of the selected call. Generic compiler operations should
supply visible bindings and signatures, type relationships, conformance facts,
addressability, and ordinary call conversion.

A second probe passed `p.read(2)` through an ordinary Expr capture. Its dot
pattern did not match: the compiler had already replaced the dot call with
the resolved function call. Automatic dispatch must precede that replacement.
`src/expressions.x` also probes member resolution while parsing dot syntax,
before arguments, to establish binding identity. Moving only the later call
handler would leave part of dot interpretation in the kernel.

Delegation belongs in the same lookup process, using relationships attached
to the receiver's fields. Only those fields are candidates. The survey does
not justify a global missing-member callback chain or assume that every future
method is known when a type is declared.

### Indexed reads, writes, and updates

These source patterns use ordinary x2c forms:

```x2c
macro Expression $at(Expr $base, Expr $key) => $base[$key];
macro Expression $put(Expr $base, Expr $key, Expr $value) =>
  $base[$key] = $value;
macro Expression $add_at(Expr $base, Expr $key, Expr $rhs) =>
  $base[$key] += $rhs;
macro Expression $after_at(Expr $base, Expr $key) => $base[$key]++;
```

The tested Array-specific replacement bodies are ordinary quoted code:

```x2c
meta Code read_array(Code base, Code key) {
  return $!Var{ $base.getindex($key) };
}
meta Code write_array(Code base, Code key, Code value) {
  return $!Var{ $base.setindex($key, $value) };
}
meta Code add_array(Code base, Code key, Code rhs) {
  return $!Var{ Array_updateindex($base, $key, <+>, $rhs) };
}
meta Code after_array(Code base, Code key) {
  return $!Var{ Array_postfixindex($base, $key, <++>) };
}
```

The read/write program printed `4 8 8`: original value, assignment result,
and stored value. Update then postfix printed `9 9 10`: new value, old
value, and stored value. A counted base, key, and right-hand-side expression
were each evaluated once. These tests use explicit macro wrappers to call
the bodies; automatic source-pattern dispatch is not implemented.

Direct Var updates also work as quoted calls to the existing runtime helpers:

```x2c
meta Code add_var(Code target, Code rhs) {
  return $!Var{ x2c_var_update_volatile($target, <+>, $rhs) };
}
```

The reference parameter supplies address adaptation through ordinary x2c
calling rules. Manually inserting `&` is incorrect for this helper. Runtime
Var update already owns conversion-before-store and failure behavior; the
component must reuse it rather than synthesize another read/compute/write
implementation. The probe verifies normal results and evaluation counts;
failure behavior here is source-derived from the existing runtime owner.

Native-array source captures matched the getter, compound-update, and postfix
patterns. Array captures did not: Array index syntax had already become
`getindex`. This is the same phase problem as dot calls. An indexed target
must remain identifiable until its parent read, assignment, or update is
known. Structural dispatch can derive the outer operator and indexed target
from `$put`, `$add_at`, and `$after_at`; authors should not separately list
those keys. Native indexing, immutable String indexing, and custom nominal
getters impose different applicability rules. A getter alone does not imply
that a setter or updater exists.

### Cleanup from a captured declaration

A complete current-language transformation needs neither Lisp nor a claim:

```x2c
macro Declaration $local(Type $type, Name $name, Expr $value) {
  $type $name = $value;
}
meta List with_cleanup(List declaration) {
  match (declaration) case $local(?type, ?name, ?value): {
    Type declared = type;
    return $!{ $declared $name = $value; defer $name.cleanup(); };
  }
  return declaration;
}
macro Stmt $managed(Decl $declaration) {
  @with_cleanup($declaration)
}
```

Usage in the executable probe:

```x2c
$managed(Array items = []);
items.push(7);
```

The local remains accessible afterward. A second local with a cleanup method
printed `cleanup: 9` after its value changed from 3 to 9. This proves that
parsed declaration matching and quoted code can express the core algorithm.

It does not preserve the existing `T name = $auto(value)` spelling by itself.
That spelling captures only the initializer; the transformation requires the
whole declaration. The missing contract is context access or declaration
recognition before expansion erases that marker. Replacing `$auto` with
`$managed` without a decision would change the task. Storage restrictions,
Cleanup participation, and multiple-declarator behavior also remain part of
an eventual complete auto extraction.

## Interception locations derived from the survey

These are proposed internal names for semantic operations, not public hook
categories. The author supplies a quoted pattern through a decorator. Pattern
classification selects the applicable operation and its narrower key, such as
binary plus. The compiler reaches that operation through ordinary processing.

| Internal operation | Required placement and facts | Continuation |
| --- | --- | --- |
| Binary operation | Typed operands, before protocol or built-in lowering erases the operator; `Resolve._binary_expression` in `src/expressions.x` | Resolve the replacement through ordinary expression processing. |
| Member call | Preserve the receiver, member name, and call structure; account for method identity currently established by `_parse_postfix_dot` before argument parsing | Ordinary call binding, argument conversion, and result handling. The complete replacement cannot merely wrap `_method`. |
| Indexed access | Preserve receiver and index until enclosing read, store, or update use is known; `_parse_postfix_index` currently resolves immediately | Select the getter, setter, or update behavior for that use, then ordinary call processing. |
| Declaration initializer and completion | Installed binding and declared type at `_initialized`; complete initializer at declaration completion | Bind quoted declaration and cleanup statements in source order, retaining binding identity. |
| Statement completion | Complete subject and body at `_switch_statement`, before control-flow lowering | Ordinary statement binding and lowering of the replacement. |

Each operation also needs the equivalent route for quoted or constructed code.
A token-parser-only interception would give different behavior to the same
code produced by a macro. These locations are candidates established by source
inspection; automatic dispatch at them has not been implemented or measured.

Member calls and managed declarations need particular care. A complete
member-call pattern arrives after the current parser has already selected a
method identity. The design must move or split that work without changing
binding. A completed declaration arrives after ordinary initializer macros
have expanded. Merely installing a callback there cannot recover an erased
`$auto` use.

For auto, preserving selected existing macro invocations until declaration
completion is one candidate. It is not yet a demonstrated solution: current
macro patterns describe template expansion, so invocation preservation and
nested pattern derivation must be established together. A declaration-context
interception during initializer processing is another candidate. Neither
requires a public claim tag. Comma declarations must preserve initialization
order, visibility of preceding locals, and reverse cleanup order.

The successful rewrite must have an explicit continuation. Immediately trying
the same successful rule again on its own replacement can loop. Ordering,
replacement processing, and rules that intentionally compose remain design
questions, not incidental implementation choices.

### Compound updates can be derived semantically

The extension author should not need a separate `+=` rule merely to reuse a
binary `+` rule. The compiler can recognize the update, retain the target once,
and combine the binary operation with the target's storage semantics. This is
a semantic derivation, not textual substitution of `x = x + y`.

A focused current-compiler probe in `/tmp/x2c-dispatch-study/compound.x`
compared two Vars initialized from `(uchar) 10`. After adding one, `updated +=
1` reported `u8 11`, while `assigned = assigned + 1` reported `i32 11`.
An indexed target containing a counter function called that function once
with compound assignment and twice with the expanded assignment. Both runs
completed successfully. These observations reject only the naive expansion.

Existing `Compiler.protocol_update_helper` in `src/protocol.x` already generates
quoted helpers that store a binary member's result and return the old or new
value. `Var.update` additionally preserves the original stored type and commits
only after successful conversion. Collection updates retain their own rules;
for example, Map numeric `+=` can initialize an absent key. Derivation must
reuse those storage rules rather than assume every update is an ordinary
getter followed by an ordinary setter.

The remaining authoring test is whether binary and access patterns supply all
required facts for this common update operation without requiring additional
handlers for each compound spelling. No new update API is justified yet.

## Proposed kernel boundaries

These recommendations incorporate Gary's permission to retain justified kernel
operations and revise semantics deliberately. They are not implementation
approval or claims of a completed extension API.

### Ordinary member calls with component delegation

Consider a `Wrapper` with `delegate Reader reader;` and the expression
`wrapper.read(2)`. The delegation policy selects `wrapper.reader.read(2)` when
ordinary lookup finds no direct `read`. Two viable delegate paths produce an
ambiguity, not an arbitrary first match. This example retains the current
source spelling while replacing the salvaged registration mechanism.

The recommended boundary keeps ordinary member lookup, binding identity,
receiver adaptation, and call argument conversion in the kernel. The component
owns which fields delegate, path search, and delegation-specific diagnostics.
Declaration processing records eligibility for the receiver type. A failed
ordinary lookup checks that eligibility before invoking delegation; unrelated
receiver types do not execute delegation code. The component builds the
selected member call with quotations and returns it to ordinary call resolution.

The kernel case is concrete: `_parse_postfix_dot` establishes method identity
before argument parsing, while `CallSite._bound` and `_finish` share conversion
and call handling. Extracting that complete interpretation now would require
exposing or rearranging those operations merely to reproduce existing calls.
A type-scoped delegation contribution can exercise useful extensibility
without doing so. This retains a real language policy in the kernel; it is not
being described as complete dot-method extraction.

The remaining proof must show the actual field-declaration pattern, receiver
eligibility registration, quoted path construction, and integration with
source-ordered imports. Do not pre-enumerate all possible forwarded names:
visible imported methods can depend on the call site. The old global member
callback interface is not the proposed answer. No public candidate record or
new dispatch API is justified until this authored example establishes its need.

### Common update mechanics with component operation selection

Compare `values[index()] += amount()` with `values[index()]++`. A common
operation retains the target, invokes the selected arithmetic/access behavior,
and returns the stored or previous value as appropriate. The component should
not have to reinvent target capture for every compound operator spelling.

Keep target evaluation and ordinary assignment conversion in the kernel
initially. Keep arithmetic selection and type-specific indexed storage policy
with their existing language/runtime owners. Existing protocol helper
construction and Var/collection update functions are reuse candidates, not
new helper APIs to clone. This boundary earns its place if several authored
operator and access patterns can share it without separate update handlers.

There are two coherent Var policies to compare:

| Policy | Example starting with a Var holding u8 | Consequence |
| --- | --- | --- |
| Preserve the stored numeric type | `v += 1` stores u8; `v = v + 1` can store i32 | Keeps current update conversion and failure behavior; requires an explicit storage policy. |
| Adopt the arithmetic result type | Both forms can store i32 | Makes value typing more uniform; changes subsequent dynamic dispatch and conversion-failure behavior. |

Neither policy changes the requirement to evaluate an update target once.
Recommendation: do not change numeric semantics solely to remove a dispatch
obstacle. First demonstrate whether the common update operation can use the
existing storage policy cheaply. If it cannot, present the complete alternative
with overflow, conversion failure, postfix results, and absent Map keys included.
A cleaner language rule is a valid reason to change semantics; compatibility
alone is no longer a reason to reject it.

### Statement rewrites and managed declarations

A string switch supplies a contrasting case: the component needs the complete
subject and body and can return quoted ordinary control flow. Keep binding,
label ownership, cleanup, and emission in the kernel. There is currently no
source evidence requiring string-switch policy itself to remain there.

Auto still requires an authored example that preserves initializer-only
`$auto` recognition until declaration context is available. Do not settle that
question by adding claim tags or by silently changing the user's spelling.
If maintaining that spelling needs disproportionate expansion machinery,
compare a declaration-level spelling with Gary and show the actual code.

### Recommended comparison before compiler implementation

Use three complete included components: delegated calls, indexed access with
compound updates, and string switch. Together they exercise symbol lookup,
target/storage behavior, and statement structure. Retain the binary and auto
probes as checks that the resulting design has not excluded those uses.

For each component, finish the authored macro patterns, decorator, methods,
quoted replacement, and user program before fixing new public API names.
Then demonstrate the registration classification, exact interception, and
ordinary continuation. Current probes establish only pieces of this chain.
The next deliverable is this complete comparison, not a production dispatcher.

## Sequences and grouped declarations

Sequence handling is a cross-cutting authoring requirement, not an auto-specific
exception. Distinguish matching one binding within a declaration group from
matching several adjacent statements. Both need sequence capture and splicing;
only the former inherits declaration specifiers and per-declarator type shape.

For example, `int *p = first(), n = second();` shares the base `int`, but its
two bindings have different types. A component matching one initialized binding
should not decode that grouping or copy the base type onto each name. The
compiler already owns declarator interpretation and binding order. A proposed
kernel sequence facility would present each binding with its effective type
and identity, apply the eligible pattern, and splice zero or more replacement
items at that position. It must retain shared type definitions: splitting an
anonymous aggregate declaration by duplicating its type definition is incorrect.
Do not implement this by unconditionally flattening all source declarations.

For two managed bindings, cleanup must be registered after each successful
initializer and before the next initializer. If the second initializer fails,
the first binding already has cleanup. Earlier bindings remain visible to
later initializers. This ordering is part of the sequence operation, not
boilerplate for every component to reinvent.

Current facilities include sequence holes, remaining-sequence binders, and
splicing. Macro expansion does not categorically forbid recursion:
`Expansion.check` rejects identical active applications, limits nesting to 64,
and counts up to 10000 non-leaf source expansions. This source inspection does
not prove a recursive declaration macro works. Recursive authoring and recursive
execution also need not be identical: a regular repeated-item pattern could
be processed iteratively, in one pass, by the existing declaration traversal.

Recommended next probe: use the same single-binding pattern with one, two, and
mixed managed/unmanaged declarators, including differing declarator types and
an earlier binding referenced by a later initializer. Also test a shared inline
type definition and failure of a later initializer. Separately demonstrate
head/tail or repeated-item matching over statement sequences. Derive any new
sequence operation from those examples; do not add a raw-list traversal API or
require every component to recurse over declaration internals.

## Requirements derived from the compared examples

1. Code methods expose semantic type, captured constant values, binding
   information, and source location as clients require. Macro owns its
   template code and pattern derivation. Type shares existing structural
   operations; compiler-state lookups retain their current owner.
2. A registration operation receives a pattern and a function reference.
   Metapattern classification derives operation/context keys once. It must
   not execute arbitrary handlers against unrelated syntax.
3. Expression dispatch occurs with sufficient child typing and preserved
   source structure. It cannot be one universal fully-typed late pass.
   Assignment targets remain targets until the enclosing operation is known.
4. Complete dot extraction would require primitive symbol/type/conformance
   queries. Retaining ordinary dot resolution is now an explicit alternative;
   wrapping that resolver must not be reported as extraction.
5. Keeping initializer-only auto requires a precise declaration-context
   contract. This is separate from constructing its cleanup code, which
   already works through ordinary language facilities.
6. Integrated typed patterns need a real specification. Current macro pattern
   derivation replaces expression types with wildcards. A typed quotation
   containing binder Atoms constructs Symbol literals, not pattern captures.
   Both facts were reproduced. Existing macro patterns plus semantic guards
   work; they do not prove the requested integrated typed-pattern facility.

## What is not established

Automatic interception, complete dot-method extraction, the final typed-pattern
spelling, overlap precedence, and replacement reprocessing are not implemented
or proved. No dispatch performance claim follows from these probes. The
registration classifier was exercised for plus and multiply only; a complete
set of dispatch families remains to be derived from these source contexts.
The next design work should resolve typed-pattern semantics and early source
recognition together, then use these same cases to test that contract.

## Plan review

The parser and macro system already own structural matching and code
construction. The working probes reuse both rather than create a second
AST language. Runtime update helpers own conversion and storage semantics;
ordinary calls own reference adaptation. Code/Type queries must expose these
facts without repeating their algorithms.

The survey supplies no reason for constructor wrappers, a new hook keyword,
or caller-managed pattern cursors. It does establish missing registration
storage and source-context boundaries. Their eventual implementations are
not justified until the unresolved typed-pattern and placement contracts
are concrete. No new validation gate or shipped negative fixture is proposed.
