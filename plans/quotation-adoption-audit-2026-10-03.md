# Remaining quotation adoption

> Status: active, narrowed 2026-10-24 against `7e9fd0178`.
> Earlier adoption and scalar-generator helper migration are delivered.
> The selected typed `_Alignof` follow-up needs a fresh exact probe.

## Remaining work

### Typed _Alignof and scalar generator cleanup

The selected behavior is a Type hole in `_Alignof`:

```x2c
Type type = $!Type{ double };
Code expression = $!( _Alignof($type) );
```

The result must emit `_Alignof(double)` for the target C compiler, not
substitute the host meta process's alignment. Re-probe this exact form
before implementing: `macro-type-names-land.x` covers a spelled typedef,
not a Type-value hole, and this review ran no new quotation probe.

`lib/native-scalar-types.x` now uses meta functions and templates. The four
old Lisp helper replacements landed through `b6f4f7bff`, `7ed248f46`, and
`5d886389c`; do not repeat them. `_scalar_alignment` still constructs
canonical alignment syntax manually. If the probe confirms the gap, pair
the smallest quotation repair with that caller. If it already works,
restrict implementation to useful caller simplification.

Preserve the scalar table, exact C spellings, List keys, sort order, target
size/alignment, load/store behavior, and wide-value ownership. Verify target
alignment and scalar access with existing relevant checks when implementing.

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

Use ordinary quotation and type owners, and reuse the existing scalar table.
No parallel syntax-builder API, validator, dedicated diagnostic, negative
fixture, or recurring gate is proposed. The initial probe determines whether
any compiler change remains necessary.
