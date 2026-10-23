# auto declarations and complete initializers

> Status: done
> Implemented on 2026-10-23 in `060b131e1` and `d0f5e8dda`.
> All 25 focused auto/managed fixtures and the defer suite pass.
> Publication validation and delivery follow the root workflow.

## Behavior

Support these block-local forms:

```x2c
auto Buffer buffer = acquire(); // Clean buffer's value at exit.
auto buffer = acquire();        // Infer Buffer; same variable cleanup.
Buffer buffer = auto acquire(); // Save and clean the acquired value.
```

Declaration cleanup lowers to the ordinary declaration followed by
`defer buffer.cleanup()`. Complete-initializer cleanup uses the existing
`$auto` expansion: initialize the declared variable, save its initialized
value in a fresh const local, and defer that saved value's cleanup. Preserve
ordinary initialization conversions, binding identity, source order, and
existing defer exit behavior. Reassignment does not release a previous value.

Call cleanup through existing `Cleanup` participation, including typedef
ancestry. Types without participation emit no cleanup, including ordinary
scalars and pooled String/List values. Do not infer ownership from pointer
representation. Keep `$auto` available through the same acquisition helper
and apply the same no-op rule there.

Reject declaration `auto` combined with initializer `auto` or `$auto` on
any declarator in that declaration group, including macro-forwarded forms.
Keep the existing duplicate-acquisition checks. Explicitly typed groups may
have multiple declarators; each successful initialization registers its
cleanup before the next initializer runs.

Use the existing managed-initializer placement boundary: initialized object
declarations that are block items. Require an initializer; lazy handles start
with an explicit NULL. General expressions, assignments, call arguments,
returns, fields, parameters, for-header declarations, and static, external,
threaded, or file-scope managed declarations are outside this version.
Imported C declarations retain their existing collection behavior.

## Type inference

Support `auto name = expression`, optionally qualified, for one plain name
with an initializer. Explicitly typed forms retain ordinary declarators.
This is local C23-style inference, not full C23 declaration support.

Deduce the resolved initializer's value type: apply ordinary array/function
decay and remove outer value qualifiers, then apply declaration qualifiers.
Preserve pointee qualifiers and typedef identity so Cleanup adoption survives.
Do not apply integer promotions. A void result or an initializer that needs
a destination type cannot supply an inferred object type. Reject use of the
declared name in its own inferred initializer; do not deduce from an outer
binding of the same spelling.

Gary selected a type-representation extension on 2026-10-23 for typedefs
that hide outer qualifiers. The internal `(unqual TYPE...)` projection keeps
the typedef identity for methods and Cleanup, normalizes to its value type
without outer qualifiers, and emits an unevaluated native `__typeof__` value
type. Qualifiers outside the projection and pointee qualifiers remain.

Finish inference as an ordinary explicit-type declaration before destination
conversion. Source parsing and constructed declarations share this operation.
Preserve the declaration's binding identity and update its ordinary symbol
type and binding facts through `Sym.bind_identity`.

## Implementation

1. In `src/parse/declarations.x` and `src/parse/declarators.x`, recognize
   omitted-type declarations and complete-initializer `auto`. Parse the latter
   as the existing `$auto` call over the complete assignment initializer;
   do not add `auto` to general expression parsing. Use the same canonical
   declaration and macro forms for source and constructed syntax.
2. Add the shared inference completion at declaration binding. Keep template
   operands deferred until expansion, where their types become known. Leave
   ordinary initializer conversion and emission in their current owners.
3. Reuse `Compiler.finish_initializers` and its after-initialization rewrite
   point in `src/parse/placement.x` to place declaration cleanup after each
   initialized declarator. Reuse `src/builtins.x` for acquisition cleanup and
   Cleanup selection. Consume declaration `auto` before native emission.
   Check the two cleanup modes together at declaration completion, before
   binding either release. Reuse the existing placement checks and
   managed-binding facts; add no ownership analysis or runtime machinery.
4. Update the managed-initializer reference, idioms, and relevant syntax
   specification. Add focused cases to the existing managed/defer fixtures.
   Review and fix the completed authored diff before publication validation.

## Validation and delivery

Use the existing fixture runner to cover variable versus acquired cleanup
after reassignment and struct mutation, lazy NULL handles, inferred heap and
scalar types, typedef Cleanup inheritance, qualifiers and decay, no-op pooled
values, macro-constructed declarations, multiple-declarator order, and failure
of a later initializer. Check normal and Error exits through existing defer.

Add negative cases for combined modes (including forwarded `$auto`), invalid
inference, and the excluded placement forms. Reuse current placement fixtures
and revise the old missing-Cleanup expectation to assert no-op behavior.
Inspect generated C for the inferred type, saved versus live cleanup target,
and absence of added allocation or runtime cleanup infrastructure.

Gary authorized implementation after selecting this plan. Deliver one coherent
change under the root AGENTS.md workflow, including the applicable performance
checkpoint and `tools/gate-state.py ensure agent-pr-check`. The existing gate owns
bootstrap regeneration and publication proof; add no recurring checks.

## Plan review

The expression resolver establishes initializer types; ordinary binding owns
identity and declaration facts. Placement already establishes complete local
initializers and splits declarators in source order. Defer already owns exit
cleanup. Consumers reuse these facts rather than validate them again.

Reuse the existing acquisition macro, placement, protocol lookup, binding,
conversion, and defer paths. Shared inference completion handles omitted
types; the approved unqualified-value projection separates typedef identity
from its outer qualifications. No new runtime representation, Scope, dynamic
capture records, cache, or general expression lowering is needed.

The new checks and negative fixtures protect deliberate public boundaries:
combined modes must fail instead of scheduling two releases; inferred forms
must have one initialized plain name and a usable object type; self-reference
must not bind an outer name; managed declarations require initialization and
the supported block position. Existing placement and duplicate-acquisition
diagnostics remain their owners. Remove the missing-Cleanup rejection because
the selected contract permits no-op types. No broader validator is proposed.

## Completed source review

Declaration cleanup reuses placement and ordinary defer; initializer cleanup
reuses `$auto`. Both preserve normal initialization hooks and conversion.
Inference uses ordinary binding facts and the existing native-alias map for
anonymous types. The approved type projection preserves nominal cleanup
identity while normalizing qualifications. No runtime state was added.

Review probes exposed hidden typedef qualifications, anonymous native names,
array typedef decay, and initialization-hook ordering. Focused fixtures now
cover those cases, acquired versus live cleanup, lazy Scope creation, macros,
no-op values, and excluded syntax. The defer suite covers cleanup after a later
initializer raises.

The full fixture run also exposed a native array-decay rejection after hidden
qualifiers became visible to type resolution. The existing
`typedef-index-elements` fixture passes on the baseline. The native crossing
check now keeps array decay out of its sibling-pointer typedef rule.
