# Questions retained from completed reviews

> Status: reference, 2026-10-24.
> Source and history checked at `7e9fd0178`. These are candidates and
> coverage gaps, not newly reproduced defects or selected implementation.

## Component boundaries

The [foundation campaign](../archive/language-components-foundation.md) is
complete. Its three remaining questions have these narrower dispositions:

- Quoted `with`: `with-lexical.x` covers a macro body. The `$!{}` form was
  checked by an uncommitted October 12 probe. Reproduce the exact form when
  this coverage matters; absence of a fixture is not a demonstrated defect.
- Components using meta builders: the old constructor API was removed.
  Identify a current Code/Type operation and component caller before
  reopening the linked-copy question. The old failure alone selects no work.
- A prelude rule lost during collection: the historical silent-loss
  observation needs a current reproduction before a repair is proposed.

## Repository review

The [October 12 review](../archive/repository-review-2026-10-12.md) records
delivered repairs and a historical cleanup census. Remaining candidates:

- Typed List readers still use `list_payload()` in `lib/typed-list.x`.
  Their documented behavior turns a foreign Var tag into nil. Revisit the
  intended policy before changing it; this is not an established defect.
- `lib/func/errors.x` and `lib/lisp/lisp.x` still define
  `$error.apply.arity` with different arguments and real callers. Trace
  their owners before selecting consolidation. Other census rows were not
  exhaustively adjudicated and require current source inspection.
- The review's October 12 build-cost measurements remain evidence for
  those revisions. They do not establish current cost or cause. A new
  investigation needs comparable current and baseline workloads; this
  cleanup ran no benchmark and adds no recurring performance requirement.

The source-form, rewrite, and Lisp explanations belong to the
[writing plan](../review-remediation-2026-10-11.md). Typed quotation work
belongs to the [quotation plan](../quotation-adoption-audit-2026-10-03.md).

## SDK and native types

The [SDK campaign](../archive/macro-sdk-and-system-macros.md) delivered
located failure/error diagnostics. Location-aware warnings and enum
consumers remain unselected ideas; require a concrete caller first.

The [meta follow-ups](../archive/meta-followups.md) preserve native-layout
limits and measured alternatives. `src/symtab/types.x` still maps both
`off_t` and `time_t` to `long`. A target-specific use case must establish
the required behavior before changing this mapping or aggregate support.
The withdrawn packing proposal is not revived.

## Evidence limits

This record separates remaining questions from completed campaigns. It
does not certify runtime correctness, repeat the old performance study,
or authorize broader compiler architecture, public semantics, or new gates.
