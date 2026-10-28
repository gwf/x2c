> Status: rejected
> Investigated on 2026-10-28 at `282f5bfb8181b73ebfc924d8b77ac00a861a1607`.
> No defect in supported static-helper use was reproduced. The reproduced
> cross-unit calls violate the existing visibility contract; no compiler
> change is included. This conclusion does not reject a future language change.

# Included static meta helper cannot resolve

## Report and current finding

The [derive campaign](../derive-and-test.md#what-the-probe-established) reported
`explicit meta call cannot be resolved: no binding for probe_make` from an
included `meta static` helper at `9aeeef265`. The original failing source
was not retained, so its exact call form cannot be verified.

Current probes distinguish supported provider-owned calls from unsupported
consumer calls. Every supported form below succeeds. A direct consumer call
is rejected as a private function. A consumer macro that keeps the private
helper with `using` reproduces the reported no-binding category, but that
form is also outside the documented contract.

The [meta-function guide](../../docs/src/guide/meta-functions.md#how-a-meta-function-runs)
says static helpers and state remain in the provider. Public meta functions
can call them there. The [macro using rules](../../docs/src/reference/language.md#keeping-a-file-scope-name-with-using)
restrict an internal-linkage name to its own unit; cross-unit applications
keep nonstatic names instead. Fixing the unsupported macro case by exposing
the static helper would change that contract.

## Reproduction evidence

The current inputs are retained under
`plans/reference/probes-2026-10-28/static-meta/`. Commands below run from the
repository root after `make build-safe`:

```sh
p=plans/reference/probes-2026-10-28/static-meta
builds/0/x2c script "$p/matrix.x"
builds/0/x2c run -q "$p/matrix.x" "$p/a.x" "$p/b.x" "$p/bridge.x"
builds/0/x2c script "$p/same.x"
```

Both matrix commands print:

```text
11 13 12 21 23 22
101 102 201
```

The matrix covers two providers with same-spelled private functions and
private state, a transitive include, provider-owned enumerator calls, macros
expanded in their own provider, and public meta functions calling private
helpers. State remains separate between providers. `same.x` prints `13 99`:
a same-unit macro retains its helper despite a caller local of that spelling.

These unsupported calls fail:

```sh
builds/0/x2c script "$p/direct-private.x"
builds/0/x2c script "$p/kept-private.x"
```

The first reports `'hidden' is a static function private to its unit`.
The second reports `explicit meta call cannot be resolved`, with
`no binding for hidden` in the included macro expansion.

## Disposition

The bug report is closed as misclassified under the current contract. The
derive implementation's linked-meta path requires no repair for this item.
A desire to keep private meta helpers in macros applied across units needs
an explicit language design decision; it is not part of this bug repair.

No compiler code, validator, new fixture, or recurring check was added.
These probes retain investigation evidence without adding another gate.
