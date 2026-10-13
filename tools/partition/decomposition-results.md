# Responsibility workflow validation

The reviewed source and call graph are bound to `dbdafacb`. Responsibilities
were described from every public body, source sections, resolved caller
identities, and representative caller bodies. This is not an exhaustive review
of every caller or a native extraction/build proof.

| File | Described public operations | Responsibility labels | Private components, including initialization and recorded callbacks |
|---|---:|---:|---:|
| compiler.x | 86 | 20 | 73 |
| macros.x | 75 | 11 | 28 |
| collect.x | 32 | 10 | 8 |

Seven directly spelled callback references supplement the direct-call graph.
Examples include `_new -> _drop_compiler`, `_real_paths ->
_real_paths_shutdown`, `_ship_rewrite -> _shipped_shutdown`, and
`_process_cache -> _cache_shutdown`. They are recorded as source evidence,
not guessed from missing callers. Private types, diagnostics macros, and
file-local state are separately recorded as unresolved ownership constraints.

## What the examples propose

Compiler's operation labels describe finer responsibilities than its eight-group
reference. Private components join collection, parsing, script handling, token
navigation, and binding facts. Another chain joins declaration production,
default selection, and portable syntax. These labels remain module members;
the tool does not promote their helpers to split them.

Other distinctions are deliberately reviewable: pointer boxing, diagnostic
routing, segment transfer, and compiler lifetime may belong in a broader
state/lifecycle responsibility. Completion may belong with parsing; generated
identities with pending code; pattern-value recovery with capture declarations.
Their different bodies explain the separate operation labels, but do not prove
that each deserves a file. The UI can combine them with a concrete reason.

The current compiler manifest has 14 tentative containers for authored functions
plus unresolved synthetic initialization. There are 23 public crossing pairs
and 24 call sites, with no static crossing. The eight-group reference independently
reproduces 20 pairs and 21 call sites without static crossings. Neither crossing
count ranks semantic coherence. The reference excludes synthetic initialization.

Macros retains all eleven responsibilities within a shared translation unit.
After recorded callbacks, its largest component has 323 functions. Collect
retains ten responsibilities around a 151-function private component; its
synthetic initialization remains unresolved. No eight-way or balanced split is
requested. Exact keep-together paths explain these conflicts.

Every node is assigned exactly once, including helpers and initialization.
Unassigned nodes remain explicitly unresolved instead of becoming helper-only
extraction proposals. Unknown private declaration consumers conservatively
leave the affected scope unresolved; accepting a completed arrangement is
blocked until those decisions are recorded. Graph preview remains available.

## Reproduce

Run `node tools/partition/prepare-responsibilities.cjs`, followed by
`node tools/partition/tests/compare-decompositions.cjs`. The first command
reproduces versioned manifests from source evidence, not the reference fixture.
The second checks coverage, callback constraints, conflict paths, classification,
and the independent compiler reference. `check-responsibilities.cjs` covers
small fixtures for conflicts, public crossings, module decisions, imports,
partial scopes, helper attachments, and unresolved dependencies.
