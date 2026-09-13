# Architecture search follow-ups

> Status: active - repaired Lisp form fallback is approved for local
> implementation and validation. Parallel build translation has a successful
> spike; the no-op depfile shortcut is rejected. Publication remains on hold
> until Gary and the reviewing agent approve the final result.

The search itself is closed. Its confirmed deletions, performance changes,
and bug fixes are on `main`; its library removals were reverted and repaired
in `d7bb8da`. The rejected hypotheses and their evidence are recorded in the
brazzaville workspace under `.context/arch-search/REPORT.md` and need no
plan. The following records the current decisions on its three follow-ups.

## 1. Parallel translation in `x2c build -j N`

`x2c build` never translates units in parallel. `_build_translation_request`
in `src/main.x` builds one-input requests, so the `total > 1` condition that
forks translation workers is never true, while the `--jobs` help text in
`src/cli.x` promises parallel translation. Measured on lib: `translate -j1`
2.53 s against `-j16` 0.58 s, so a cold manifest build spends about 6.8 s in
serial translation that is about 1.6 s parallel.

Design: hand the translation phase one multi-input request so the existing
worker path engages; give each unit its own output directory so units that
share a stem cannot collide; use one slice per unit on the build path so a
unit's recorded prerequisites reflect its own parse rather than what an
earlier unit in the same worker left in the process cache, because build
reuse is decided from those prerequisites. Generated C must be byte-identical
across `-j1` and `-j N`, and failures must propagate as before.

The 2026-09-13 spike at `618c26e` passed worker, failure, same-stem,
per-unit dependency, selective invalidation, dry-run, and 111 CLI probes.
All 77 src/lib units produced identical serial/parallel C/H. Three interleaved
30-unit compiler object builds measured 4.213 s before versus 2.758 s after
at four jobs (34.5% faster), with single-job time unchanged within variation.
The prototype is in `/tmp/x2c-spike-parallel-build`; batch progress reporting
still needs finishing. No publication gate or approval is inferred.

A separate 16-core host sweep measured 6.00/4.12/2.73/1.83/1.36 seconds at
1/2/4/8/16 jobs. A core-aware standalone build/run default is under discussion;
explicit `-j` must keep control, and default translation under external Make
must not multiply workers. CPU affinity/quota and concurrent memory remain
cross-platform considerations. The product default remains one job.

Validation: the probe asserting worker count under `--verbose`, `-j1` versus
`-j4` output identity for src+lib, the CLI boundary probes, then
`tools/gate-state.py ensure agent-pr-check`.

## 2. No-op `x2c build` still preprocesses every object

An up-to-date retained build runs `cc -E` per object to recompute its
fingerprint: measured 1.18 s for a no-op build of the repository against
0.10 s for `make`. The archived plan `archive/native-build-reuse.md`
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

Approved for local implementation on 2026-09-13; final publication approval
is pending. The original prototype fixed a 100,000-deep self-tail loop with
`def`, but produced wrong results after rebinding `quote` inside a body.
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

Implementation includes the runtime, regression tests, internal API metadata,
and authored book description. Regenerate symbols and documentation through
their existing targets. Review the final authored and generated diff, run
`tools/gate-state.py ensure agent-pr-check`, and keep the validated local
result for joint review before publication. No new gate is added.

## Recorded, not planned

- `etc/header-symbols.xlisp` replay adds 74 generated-protocol rows that a
  cold raw walk does not produce, so cached and cold collection disagree
  today. The rows looked inert. Worth a check when the collector is next
  touched.
- `struct VarMethods` in `lib/common.x` is a hand copy of the protocol row
  set; a row added without a field silently loses its dynamic route.

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
check to remove. Final-tree publication validation remains required, and
publication is explicitly withheld until joint approval.
