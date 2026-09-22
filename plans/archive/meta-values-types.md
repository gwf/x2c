# Meta values, types, and native records

> Status: rejected
> The local implementation was rejected on 2026-09-21 before publication.
> Session-owned records and a hardcoded timespec bridge did not meet the
> requested generic storage and execution lifetime. The historical proposal
> below is preserved as evidence, not implementation guidance or approval.
> See [the recovery plan](meta-recovery.md).

## Result

Extend contextual `meta` from function definitions to three connected forms:

```x2c
meta static const double pi = 3.1415;
meta typedef unsigned long Count;
meta struct Point { double x; double y; };
meta Point;
```

A meta static has separate source-equivalent compile-time and emitted runtime
instances. A complete adopted struct can execute inside meta code with C value,
field, copy, and address behavior while using evaluator-owned storage. A curated
compiler-baked native record can cross a trusted native meta function boundary.

The exact top-level `meta TYPE;` form is adoption. This deliberately reserves
the otherwise ambiguous `typedef int meta; meta Point;` form; the current corpus
contains no such use. `meta` remains an ordinary identifier elsewhere.

## Settled representation

- Meta globals require `static` and an initializer. Their compile-time cells
  belong to the translation unit. Any function reaching them is non-foldable.
- Scalar aliases reuse their existing `Var` representation.
- Arbitrary source structs use one generic typed record representation with
  stable field cells. Struct assignment and by-value calls/returns copy fields;
  pointers and field addresses retain identity.
- Generic records live for the evaluator session initially. They do not expose
  native `sizeof`, `_Alignof`, byte offsets, pointer arithmetic, or ABI calls.
- Classes reuse and validate their existing `protocol Var` contract.
- Native layout belongs to generated C compiled into the compiler. No x2c ABI
  calculator is introduced. Only a matching compiler-baked descriptor may pass
  a record or pointer to native code.

## Ordered implementation

1. Extend top-level contextual lookahead and bound declaration metadata. Add
   per-unit scalar meta-global cells, initializer evaluation, marked-global
   lowering, scalar/alias adoption, diagnostics, fixtures, docs, and bootstrap.
2. Add the generic evaluator record and schema registry. Lower supported
   declarations, initialization, field places, copying, addresses, parameters,
   returns, and value-record classes. Reject unsupported aggregate/layout forms.
3. Accept a bodyless meta function declaration only when a trusted native
   target with a representable signature is compiled into the compiler. Install
   its existing generated `Func` adapter into the macro-Lisp session. Do not
   automatically fold ordinary calls.
4. Add a compiler-baked `struct timespec` descriptor and `clock_gettime` native
   binding as the first pointer/in-out proof. Access fields through compiled C
   accessors; compare host-owned size/alignment and reject generic/native type
   mismatches.

Teach and bootstrap syntax before migrating declarations. Land dependencies in
order, rebase later work, and validate the exact final tree.

## Validation

- Contextual parsing and the deliberate ambiguous-form rule; no current-corpus
  regression for identifiers named `meta` outside marker forms.
- Source-ordered initialization, typed conversion, address mutation, failure
  rollback, unit isolation, runtime/compile-time separation, and non-folding.
- Struct initialization, zero fill, field reads/writes, nested value copies,
  pointer identity, by-value calls/returns, and escaped evaluator lifetime.
- Negative cases for incomplete types, unions, bitfields, flexible arrays,
  volatile/atomic fields, packed/aligned types, and unsafe native crossings.
- Native prototype presence/signature checks and ordinary-call non-folding.
- `timespec` field access and `clock_gettime` mutation on supported macOS and
  Linux targets, with C-owned `sizeof` and `_Alignof` evidence.
- Completed authored-diff review, generated-artifact review, `git diff --check`,
  and `tools/gate-state.py ensure agent-pr-check` on the final rebased tree.

## Plan review

The parser and resolver remain the owners of declaration, type, and field
correctness; new consumers use bound identities and declared types. The C
compiler remains the native ABI owner. The implementation reuses the per-unit
Lisp session, global reachability tracking, Scope-owned cells, field metadata,
class Var protocol, and generated Func adapters. The only new persistent
mechanisms are a marked-global cell table, one generic record representation,
and generated native-record descriptors, each owning state no current producer
has. Fixtures protect public phase separation, C copy/address identity,
evaluator lifetime, non-folding, protocol agreement, and unsafe ABI crossing.

## Follow-up architecture

The canonical [meta-capable protocol opportunity](../meta-authoring-and-coverage.md#meta-capable-protocol-opportunity)
records how protocol witnesses can unify representation, lifetime, selected
operations, associated-type adapters, and REPL discovery. The trusted native
registry and compiler-owned `timespec` carrier implemented here are bootstrap
evidence for that future work, not a public `Meta(T)` protocol or a second
general type/protocol system.
