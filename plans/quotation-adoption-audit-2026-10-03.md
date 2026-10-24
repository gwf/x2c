# Remaining quotation adoption

> Status: reference, 2026-10-24.
> The selected typed `_Alignof` follow-up is implemented. Individual
> adoption and TagId generation remain unselected candidates.

## Completed typed alignment

### Typed _Alignof and scalar generator cleanup

The exact probe on `a58771ab5` failed with an ambiguous Type/Expr hole.
The compiler now parses the type operand through its ordinary declaration
parser and retains the existing native-call AST:

```x2c
Type type = $!Type{ double };
Code expression = $!( _Alignof($type) );
```

The generated C contains `_Alignof(double)` for the target C compiler.
It does not substitute the host meta process's alignment. Named typedefs
wait for expansion-site binding, as `sizeof` does; existing native
expression operands remain accepted. The new `macro-quotation-alignof`
fixture checks Type-value holes and direct type captures for scalar,
record, and pointer operands. `macro-type-names-land` checks typedef lookup.

`lib/native-scalar-types.x` now uses meta functions and templates. The four
old Lisp helper replacements landed through `b6f4f7bff`, `7ed248f46`, and
`5d886389c`. The remaining `_scalar_alignment` helper is now deleted:
`$native.scalar.access` writes `_Alignof($type)` beside `sizeof($type)`.

The scalar table, C spellings, keys, order, load/store operations, and
wide-value ownership are unchanged. Existing native-scalar fixtures cover
access through records and pointers. Publication uses the normal combined
gate; this change adds no recurring validation requirement.

## Remaining work

There is no further selected implementation in this plan.

### Individual quotation adoption

Treat structural declaration rebuilds and retained autodiff operations as
individual candidates. Select only a demonstrated simplification that
preserves binding, canonical Lists, staging, timing, and ownership.
Historical site counts are not a current census or a blanket rewrite request.

### Candidate: generate TagId from its rows

Lower priority and not selected. Compare current `lib/var/var.x` and
`lib/var-tags.x` before proposing work. Preserve every numeric ID and name,
including `_invalid_ = -1` and `_tag_count_`, without adding meta dependencies
for ordinary Var users. Existing assertions already check their agreement.

## Delivered work and evidence

The [adoption audit](archive/quotation-adoption-audit-2026-10-03.md) retains
earlier measurements, accepted and declined conversions, and the dropped
shared ErrorSlot proposal. Current construction guidance is
[choosing how to build syntax](../agents/lowering-with-macros.md#choosing-how-to-build-syntax).

## Plan review

The implementation reuses ordinary declaration binding and native-call
resolution. It adds no AST form, validator, or dedicated diagnostic and
deletes the scalar alignment syntax builder. The positive fixture covers
the selected language behavior; no negative fixture or recurring gate was
added. Optional adoption still needs a concrete simplification.
