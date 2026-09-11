> Status: active
> Approved for implementation and delivery on 2026-09-10.
> Baseline: 2d29fe9. Existing failures remain open until verified.

## Current outcome

Implementation and final publication repairs are delivered to main at
1dbf258 (2026-09-11), following 1316e0a, f9f8589 and 2b7a63c. The final
agent-pr-check passed: 773 unit tests / 18,507 assertions, 623 compiler
fixtures / 1,443 artifacts, 459 required raw-symbol translations, bootstrap
and self-host comparisons, and the documentation audit. Pages deployment
[34605316778](https://github.com/gwf/x2c/actions/runs/34605316778) succeeded
at that exact revision. Live Torch guide search, chapter navigation,
example, language reference and generated compiler API routes were verified.

Three earlier publication failures remain in the evidence: function bodies
preceded late private includes/macros; the reduced Scope probe lacked two
shutdown stubs; and the generated API source line needed regeneration.
All were repaired through their existing owners before the passing gate.
Source-position macro behavior and generated function equivalence were
checked after the compiler placement repair. Initialization also passed 56
focused runtime tests (307 assertions) and 20 repeated initialization runs.
All five Torch extensions passed focused macOS and Linux acceptance. Linux
ran in local x86_64 Docker emulation and establishes correctness only.
Its retained source snapshot predates the final compiler placement repair;
the emitted package function bodies were subsequently checked for equivalence.

Retirement review's supplemental diagnostics are recorded: phase/startup
costs, error interning, corrected sequence lifetimes, all four interop sizes,
and a counter-free MNIST timing correction with 50 warmup batches.

The final benchmark session retained 160 timing process logs across 16
configurations, five fresh-process pairs each, with counters off and no
recorded host sleep. A separate instrumented session retained 17 paired
memory profiles and lifetime attribution. The matched Adam control passes;
stock Adam's explicit tabular loss differs by 0.223%, exceeding the original
0.1% tolerance. That failed verdict remains the accepted limitation.

Onboarding remains open. Original inputs could not be recovered; the fresh
evaluation and affected reruns leave six of 30 required trials failing.
Two source comments were clarified, but current owners already address the
remaining failures. No aggregate score or repeated attempts erase them.
See [the active evaluation plan](agent-onboarding-accuracy.md).

Raw acceptance evidence is retained outside disposable worktrees at
`/Users/gary/Documents/x2c-evidence/closeout-20260910/`, including failed and
interrupted earlier sessions. The three completed reference/site plans are
archived, as are the [Torch extensions](archive/x2c-torch-later.md) and
[Torch comparison](archive/x2c-torch-comparison.md). Every original unit-test
status item has a delivered resolution or explicit retirement in
`unittest/STATUS.md`. This umbrella and onboarding remain active because
onboarding acceptance still fails.

# Close outstanding work

## Decisions and boundary

Complete the existing plans and unittest status items, including all five
Torch extensions and general first-use local static initialization. Deliver
coherent validated batches to main. New research findings are a separate
backlog, not authorization to implement them.

- Linux acceptance uses local Docker with an isolated x86_64 container.
- Onboarding uses a fresh frozen evaluation if the original inputs cannot
  be recovered; no historical before/after claim follows from the new runs.
- Torch compares a Python Adam control matching libtorch operation order
  separately from stock PyTorch. The control must meet existing tolerances;
  stock Adam's recorded numerical divergence is an accepted limitation.
- Static storage does not extend referent Scope/Context ownership.
- No new recurring workflow, gate, or host toolchain installation.

## Implementation and acceptance

### Inventory

Correct onboarding's stale delivery status (352d4d8 already shipped).
Archive shareable examples with delivery/deployment at 2d29fe9, and archive
the completed declaration-discovery and source-package reference evidence.
Reconcile every unittest outstanding entry against current owners. Retire
obsolete names and inappropriate helper/injection suggestions explicitly.

### Initialization

Preserve file initializer macro chronology and inline tag identity through
the existing emitter's native capture machinery: an ordered forwarding
macro expands original inputs in source order before reconstructing visible
file-scope types and a source-position runtime helper. Existing dependency
queues call the helper. Keep opaque macro calls whole; do not extract types
hidden by native macros or add a C macro evaluator. The native prototype
combining counters, runtime macro input, redefinition and tag reuse passes.

General runtime-valued local statics initialize once at first declaration
execution. Native constant initialization remains unchanged. Competing
callers wait; initializer code runs outside the coordination lock. Errors
reset the guard and propagate, allowing retry without undoing external
effects. Detect recursive and cross-thread cycles through ordinary Error.
Thread-local objects have per-thread initialization.

Use aligned native storage, construct a complete automatic temporary and
publish only after success. Preserve qualifiers, const members, arrays,
address identity and sizeof through typed lvalues. Failed attempts reset the
guard while retaining the reserved address for retry. Process/thread cleanup
reclaims all reserved storage, including never-completed objects, not referents.
Reuse cleanup-region restrictions for jumps bypassing initialization.

Prove counters, macro redefinition/runtime input, nominal tag reuse, opaque
stringification/pasting, arrays, const fields, over-alignment, addresses,
concurrency, cycles, retry, thread-local independence and unchanged ownership.

Complete real String behavior gaps in existing suites. Finish bounded
literal/readability cleanup while retaining deliberate explicit-construction
tests. Trace ownership before removing scopes. Retire logger/diagnostics
helper unification; preserve distinct payloads. Record unforced Map OOM
coverage honestly without adding an injection framework.

### Torch

1. Add explicit Python Adam state-dict import/export, preserving archive
   save/load and tensor Checkpoint semantics. Restore parameter groups,
   ordering, options, steps, moments and AMSGrad. Resume in both directions
   and compare restored state and next update.
2. Reuse string devices and generated Tensor.to_device for MPS. Add module
   transfer, device queries, availability/synchronization; copy to CPU before
   native host reads. Train/evaluate float32 MNIST with integer labels,
   checkpoint/reload, and report unsupported generated operations.
3. Pin Linux libtorch 2.10.0 and checksum using shared dependency machinery.
   Select platform linker/runtime settings. In Docker prove every applicable
   verification target, examples and an external consumer. Record emulation;
   do not represent Docker timing as native platform performance.
4. Add Tensor.custom, saved-tensor context operations and callback-safe
   backward. Multiple inputs, one output, first-order CPU/MPS gradients.
   Graphs retain native tensors and borrow Funcs/captured referents. Use
   caller-thread autograd execution with restored TLS settings, callback
   scopes and contained Error; reject nested backward, unsupported higher
   order/in-place behavior and unsafe callback entry. Verify gradients,
   thread identity, errors, cleanup and graph lifetime.
5. Add TorchLisp.install using existing session ownership and ordinary
   tensor/module/optimizer bindings. Compose fit-line training in Lisp with
   persistent data/model and explicit native temporary release. Verify
   native-handle stability and session destruction; report wrapper growth.
   No GC, second lifetime system or unbounded no-grad guards.

Implement interchange/MPS first, Linux next, then custom autograd and Lisp.
Update package README, book and runnable examples with each capability.

### Fresh evidence

Run complete Torch correctness/checkpoint, environment, timing and memory
sessions with matched-control and stock comparisons labeled separately.
Keep historical results intact and raw artifacts outside disposable trees.

Attempt bounded recovery of onboarding inputs. Otherwise freeze five new
scenarios: semantic choices, truth tests, canonical ownership, source-backed
investigation and answer-only completion. Run each three times per installed
agent with fixed settings and five-minute planning-only limits. Keep all
failures/usage; repair demonstrated defects and rerun only affected cases.
Every required case passes before completion; aggregates do not hide failures.

## Delivery

Review and fix each authored diff, integrate current origin/main, inspect
generated outputs, run git diff --check and ensure the existing publication
gate on the final tree. Code uses agent-pr-check; documentation-only uses
doc-check. Push explicitly to main. Deploy/verify affected site/book routes.
Archive each plan with its outcome, commit and evidence. Failed acceptance
stays active; do not equate a running or partial check with completion.

## Separate research backlog

1. Symbolic aggregate initializer condition expansion: scalar positional
   initialization was repaired separately in b39546c (2026-09-11). The
   twelve-value acceptance case now generates 16,703 C bytes, with linear
   growth through 64 values.
2. Warm native build fingerprints run serially before job scheduling.
3. Editor queries repeat analysis; reuse revision-specific semantic facts.
4. Pool release retains transient peak backing: 54,618,112 bytes after a
   200,000-allocation burst, with only 2,048 bytes active. This is not a leak.
5. Relocatable Torch application distribution through existing bundle owners.

The [aggregate initializer completion record](archive/aggregate-initializer-growth.md)
records item 1's separately authorized implementation, compatibility boundary,
publication, and retained evidence. The other four opportunities remain
future work. Onboarding acceptance remains independent and is not resolved
by that compiler repair.

## Plan review

Canonical ASTs, initializer conversion/dependency queues, existing cleanup,
Scope/Context ownership, the Torch shim/generator and Lisp sessions establish
the reused contracts. The local-static guard/storage owner is necessary for
concurrency, retry and qualified object initialization. The autograd bridge
is necessary at the native boundary. Neither adds an ownership or exception
system. Boundary rejection protects unsafe callback entry, initialization
deadlock, foreign-state mismatch and invalid generated access. Retire stale
checklist entries instead of creating process to satisfy them.
