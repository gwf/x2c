> Status: active
> Reported by the derive probes on 2026-10-28 at `9aeeef265`.
> Current reproduction and diagnosis remain open; this record does not
> authorize implementation.

# Deferred method template loses its name

## Reported behavior

The [derive campaign](derive-and-test.md#what-the-probe-established) reports
that returning a method definition from a meta function through a deferred
named template, `$derive.method(type, name, body)`, produces `int(P v){`
in generated C. The dotted declarator loses its method name.

The generated C must retain the method's name and remain callable through
its ordinary method spelling. The derive implementation avoids the affected
form by writing dotted declarators directly in Unit macros.

## Evidence and next action

The report comes from the original probe investigation on `dev` `9aeeef265`.
The campaign retains related successful probes in
`plans/reference/probes-2026-10-28/derive/`; those files are not claimed to
reproduce this failing template form. No standalone failing reproducer is
currently attached to this record, and the defect was not reverified while
recording this follow-up.

1. Recover or reconstruct the failing deferred-template input and save a
   minimal reproducer with its exact compiler revision and generated C.
2. Compare the deferred form with a direct Unit macro on the same compiler.
3. Trace where the declarator loses its name before selecting a repair.

A repair should preserve ordinary dotted-method naming and binding. Verify
that the minimal deferred form emits valid C and can be called. Do not
substitute new public syntax or origin restrictions for the missing name.

## Plan review

This is a defect record, not a chosen repair. It adds no compiler machinery,
validator, fixture, or recurring check. Diagnosis must identify the owner
that loses the existing method identity before implementation is selected.
