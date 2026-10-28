> Status: active
> Reported by the derive probes on 2026-10-28 at `9aeeef265`.
> Current reproduction and diagnosis remain open; this record does not
> authorize implementation.

# Included static meta helper cannot resolve

## Reported behavior

The [derive campaign](derive-and-test.md#what-the-probe-established) reports
that a `meta static` helper reached only through an include fails with:

```text
explicit meta call cannot be resolved: no binding for probe_make
```

The report contrasts this with a nonstatic meta helper in an included module,
which works when the module is an explicit `run` input or is built by
`script`. Shipped library helpers use linked meta, so derive does not depend
on repairing the static-helper case.

## Evidence and next action

The report comes from the original probe investigation on `dev` `9aeeef265`.
The campaign retains related successful probes in
`plans/reference/probes-2026-10-28/derive/`; those files are not claimed to
reproduce this include-only failure. No standalone failing reproducer is
currently attached to this record, and the defect was not reverified while
recording this follow-up.

1. Recover or reconstruct the include-only helper and its caller. Record the
   exact source files, invocation, and compiler revision.
2. Compare static and nonstatic helpers under `run` and `script`, including
   the ordinary helper-unit build behavior.
3. Trace the explicit meta-call binding and confirm the owning visibility
   contract before selecting a repair.

A repair should allow the supported static-helper use without exporting the
helper or changing the language's call-site macro binding rules. Keep native
helper construction and symbol visibility with their current owners.

## Plan review

This is a defect record, not a chosen repair. It adds no compiler machinery,
validator, fixture, or recurring check. Diagnosis must distinguish missing
binding from missing helper compilation and resolve the owning contract
before implementation is selected.
