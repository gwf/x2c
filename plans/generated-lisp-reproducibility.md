# Reproducible generated Lisp names

> Status: active - repaired and verified on the local stabilization candidate;
> delivery to `dev` remains. The original naming drift did not reproduce at
> reviewed `0bdc8398`.

## Observed issue

Generating the three checked-in Lisp artifacts in a fresh source-only home
changes generated local names relative to the built workspace. A second
pass is stable. Token comparisons show only bijective name substitutions:
57 names in init, 486 in builtins, and 99 in binding support. Behavior has
not been shown to differ. The consequence is noisy artifact diffs and a
limit on what warm-tree byte-reproducibility checks establish.

Reproduction: archive 231550b0 into a fresh directory, load
`tools/gen-lisp-init.py` as a Python module, set its ROOT to that directory,
and call its three generate operations using the original workspace's
`builds/0/x2c`. Compare each output with the archived artifact, then repeat.
The complete archive includes src and include; missing source is not the
explanation. The exact influence of available interfaces remains to isolate.

## September 23 verification

The post-merge review generated all three artifacts byte-identically twice
from a fresh source-only home at `0bdc8398`. That result closes the original
name-drift observation for that tree, not for every later compiler revision.
On local stabilization candidate `7815096c`, a `git archive` source-only home
using its rebuilt stage-0 compiler rewrote `etc/init.xlisp` on the first pass.
The next `builtin-macros` generation failed reading that init with
`(malformed ... (line 127) (column 70))`; the generated init contains new
`C.source-function` and Func-adaptation forms. Generation from local F4
commit `30c206f2` also rewrote init and failed on the next attempt. This is
a current generated-artifact/lowering transition, not evidence that
nondeterministic name allocation returned.
The refreshed bootstrap at local bridge `88d1bd86` (integrated as `6de15600`)
includes the C3 native bindings needed by the generated Lisp forms. On that
bridge, fresh source-only homes generated all three Lisp artifacts with both
the bootstrap and stage-0 compilers; each second pass was byte-identical. This
resolves the malformed-form failure on the bridge. The existing
`unittest/probes/run-lisp-init.py` probe passed twice on the final local
candidate, with byte-identical second-pass artifacts. Delivery to `dev`
remains the completion boundary.

## Earlier proposal and current acceptance

Investigate the naming counter in `src/comptime.x` and generation entry
points in `tools/gen-lisp-init.py`. Prefer a deterministic naming scope per
artifact using existing lowering machinery, if it preserves uniqueness across
functions, nested helpers, and imported definitions. This is a direction to
validate, not a settled counter-reset design. The reviewed tree did not need
that reset; the malformed generated form came from stale bootstrap bindings.
Do not rename emitted Lisp text.

Fresh-source, warm-interface, and stage-2 generation should produce identical
bytes while preserving public names, semantics, and helper uniqueness. Use
focused comparisons and the existing publication gate; add no recurring gate.

## Plan review

The lowerer already owns lexical/helper identity. Reuse that owner rather
than introducing an output rewriter or another evaluator. Determine the scope
of counter uniqueness before changing it. No new public validation or
additional diagnostic is proposed. Implementation awaits the bounded design
and reproduction above; this entry records follow-up work only.
