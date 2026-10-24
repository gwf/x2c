# Remaining language-reference explanations

> Status: active, narrowed 2026-10-24 against `7e9fd0178`.
> Repair batches and their decisions are delivered. Only the selected
> writing remains here; its missing coverage must be identified precisely.

## Writing and supported features

Finish the three accepted explanations by extending their existing owners:

| Explanation | Reuse | Remaining action |
| --- | --- | --- |
| Canonical source forms and their legal positions | The source construction and position contract in [the language reference](../docs/src/reference/language.md) | Identify missing forms and examples; add a compact catalog where useful without duplicating semantic owners. |
| Rewrite order, decline, and visibility | [Generating code](../docs/src/guide/generating-code.md) and the rule selection/decline contract in `lib/meta.x` | Check the accepted examples against the existing explanation and fill only missing ordering or visibility cases. |
| Compile-time Lisp truthiness, binding, and host limits | The Lisp binding, inherited-name, `set_global`, and `eval` sections in [the language reference](../docs/src/reference/language.md) | Identify missing truthiness and implementation-limit explanations; do not rewrite already documented binding behavior. |

Maintain factual supported-feature and platform descriptions as ordinary
documentation. Do not create an additional ABI promise or portability campaign.
Current source and existing book sections were inspected; this narrowing does
not claim all three writing goals are complete or that examples were rerun.

## Delivered work and evidence

The [remediation history](archive/review-remediation-2026-10-11.md) preserves
repair batches, superseded decisions, and module follow-ups. The
[repository review closeout](archive/repository-review-2026-10-12.md#closeout)
records later repairs. The [finding evidence](reference/review-remediation-evidence-2026-10-11.md)
and [language ledger](reference/review-remediation-language-ledger-2026-10-11.md)
remain dated records, not new task lists. Unselected questions live in
[review follow-ups](reference/review-followups-2026-10-24.md).

## Plan review

Reuse the book's semantic owners and existing examples. Change explanations,
not language behavior. No new representation, validator, diagnostic, negative
fixture, or recurring gate is proposed. Future authored examples use the
existing documentation checks; delivery follows root guidance.
