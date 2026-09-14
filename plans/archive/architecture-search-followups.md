# Architecture search follow-ups

> Status: done - closed on 2026-09-13.
> Lisp form fallback was published in `2619282`; parallel build translation
> and the core-aware build/run default were published in `f8972a9`.
> The no-op depfile shortcut was rejected after reproducing stale-object reuse.

The search itself is closed. Its confirmed deletions, performance changes,
and bug fixes are on `main`; its library removals were reverted and repaired
in `d7bb8da`. The rejected hypotheses and their evidence are recorded in the
brazzaville workspace under `.context/arch-search/REPORT.md` and need no
plan. The following records the current decisions on its three follow-ups.

## 1. Parallel translation in `x2c build -j N`

Before this change, `x2c build` translated units serially.
`_build_translation_request` in `src/main.x` built one-input requests, so the
`total > 1` worker condition was never true despite the `--jobs` help text in
`src/cli.x` promising parallel translation. Measured on lib: `translate -j1`
2.53 s against `-j16` 0.58 s, so a cold manifest build spends about 6.8 s in
serial translation that is about 1.6 s parallel.

The implementation gives the translation phase one multi-input request to
engage the existing worker path, with a separate output directory and one
slice per unit. Same-stem units cannot collide, and recorded prerequisites
reflect each unit's own parse rather than an earlier unit's process cache.
Build reuse still depends on those prerequisites. Serial/parallel generated-C
identity and unchanged failure propagation remain the compatibility boundary.

The 2026-09-13 spike at `618c26e` passed worker, failure, same-stem,
per-unit dependency, selective invalidation, dry-run, and 111 CLI probes.
All 77 src/lib units produced identical serial/parallel C/H. Three interleaved
30-unit compiler object builds measured 4.213 s before versus 2.758 s after
at four jobs (34.5% faster), with single-job time unchanged within variation.
The spike prototype was in `/tmp/x2c-spike-parallel-build`. The delivered
implementation reports completion through the existing Build progress owner
as each worker is collected. Native directory registration stays in input
order, including interleaved package directories, after translation finishes.

A separate 16-core host sweep measured 6.00/4.12/2.73/1.83/1.36 seconds at
1/2/4/8/16 jobs. The standalone build/run default queries online
processors through `sysconf`, falling back to one if detection fails. Explicit
`-j` overrides it; `translate` and automatic builds under Make keep one job.
This portable query does not measure Linux affinity, container quota, or
memory limits; the CLI reference states that scope without adding another
scheduler.

The delivered tree passed 120 focused CLI probes and
`tools/gate-state.py ensure agent-pr-check` before publication. The earlier
spike results above remain labeled by their source revision and workload;
they are not new measurements of the delivered tree.

## 2. No-op `x2c build` still preprocesses every object

An up-to-date retained build runs `cc -E` per object to recompute its
fingerprint: measured 1.18 s for a no-op build of the repository against
0.10 s for `make`. The archived plan `native-build-reuse.md`
overlapped that work with compilation but did not remove it for objects the
state file already covers.

The proposed shortcut is rejected after the 2026-09-13 spike. A new optional
header, a newly shadowing header, or a changed system header omitted by `-MMD`
can change preprocessed C while every previously recorded dependency stays
byte-identical. Falling back to preprocessing only when those dependencies
change would silently reuse stale objects. Three focused Apple Clang probes
reproduced these cases with unchanged options, compiler, and environment.

Retain the current native-preprocessor fingerprint. Further latency work
needs a measured different source of cost; no replacement cache or production
change is proposed here.

## 3. Lisp form fallback

Published on 2026-09-13 in `2619282` after the full publication gate and
176 reference-interpreter comparisons passed. The original prototype fixed a
100,000-deep self-tail loop with `def`, but produced wrong results after
rebinding `quote` inside a body.
Its entry guard had already run. It also checked an invalid quasiquote splice
after later side effects. Those findings supersede the original total-lowering
design and its claim that every lambda compiles.

The repaired design uses `MW_LEVAL` to evaluate one declined subform in the
machine frame's existing `LispEnv`. Rewind releases owned immediate programs
and discards partial words before emitting the evaluator crossing. Capacity
failures still stop preparation of the whole body.

Lowered `quote`, `cond`, and `quasiquote` check their selected binding at the
form's start through the existing `MW_LEXPAND` operation. A mismatch evaluates
only that untouched form. An enclosing operation already selected keeps its
meaning through its own effects; later nested forms check their own bindings.
Macro sites retain their traced dependencies. This makes the old per-lambda
`auto_specials` entry guards and bookkeeping redundant; they are removed.
Immediate constructors and self-tail targets keep their existing runtime checks.

A splice appends nil immediately after its value is evaluated, using the
existing append type/error owner before later forms run. A valid List is
returned unchanged, without copying or allocating cells. Parameter, rest,
program-capacity, and nesting limits remain. Recursion inside an interpreted
subform can still exhaust the native stack; unbounded recursion is not promised.

The repaired spike passed 132 Machine/Func/Lisp/AUTO tests (1,226 assertions),
173 macro/Lisp fixtures, and the existing AUTO benchmark check. It preserves
the 100,000-deep mutating self-tail loop in one frame. Against runtime at
`618c26e`, 21 paired fresh samples measured 3.1% overhead for an eligible hot
call and 6.7% for valid quasiquote splicing. Those narrow measurements do not
establish whole-compiler throughput. Runtime source is net +29 lines; this is
a correctness change, not a source-reduction claim.

Delivery includes the runtime, regression tests, internal API metadata,
authored book description, and symbols and documentation regenerated through
their existing targets. The authored and generated changes were reviewed and
the final tree passed `tools/gate-state.py ensure agent-pr-check` before
publication. No new gate was added.

## Recorded, not planned

- `etc/header-symbols.xlisp` replay adds 74 generated-protocol rows that a
  cold raw walk did not produce at the search revision, so cached and cold
  collection disagreed. A 2026-09-13 follow-up reproduced a cold native
  String compile failure: collection installed the participant signature
  instead of the native alias signature. The installer now uses the same
  alias signature as generation. No semantic effect was established for
  the remaining map differences.
- `struct VarMethods` in `lib/common.x` is a hand copy of the protocol row
  set; a row added without a field silently loses its dynamic route. The
  2026-09-13 review found all 22 names and erased signatures agree. Keep the
  declarations: the ABI layout and associated protocol types encode distinct
  facts, and a shared generator would add machinery for six ABI field lines.

## Plan review

Translation workers, per-unit directories, and dependency recording already
exist; the parallel-build spike routes work through them without a second
scheduler. The native preprocessor remains the authoritative owner of header
selection, so the rejected depfile shortcut introduces no cache or process.

Lisp fallback reuses the current evaluator and machine environments. Existing
form-site dependency checks replace the stale entry-guard owner. Rewind is
needed to release owned child programs and partial words before fallback.
Splice checking uses ordinary List append and its existing error behavior.
The new operation represents exactly one evaluator crossing, not another
interpreter or representation.

The regression cases protect correct results after mutation, exactly-once
side effects, splice error order, live frame values, and discarded-program
ownership. They extend the existing suite; no recurring validation or process
requirement is added. Completed source review found no additional owner or
check to remove. Both implementations passed the existing publication gate;
the rejected shortcut added no production code or process.
