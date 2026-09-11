> Status: active
> Approved for implementation and delivery on 2026-09-10.
> Baseline: 2d29fe9. Existing failures remain open until verified.

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

1. Symbolic aggregate initializer condition expansion: 12 values produced
   1,657,820 C bytes in 6.04 seconds; literal dimensions produced 510 bytes.
2. Warm native build fingerprints run serially before job scheduling.
3. Editor queries repeat analysis; reuse revision-specific semantic facts.
4. Pool release retains transient peak backing: 54,618,112 bytes after a
   200,000-allocation burst, with only 2,048 bytes active. This is not a leak.
5. Relocatable Torch application distribution through existing bundle owners.

After closeout, prepare an evidence-backed proposal for item 1. Do not start
that optimization as part of this plan.

## Plan review

Canonical ASTs, initializer conversion/dependency queues, existing cleanup,
Scope/Context ownership, the Torch shim/generator and Lisp sessions establish
the reused contracts. The local-static guard/storage owner is necessary for
concurrency, retry and qualified object initialization. The autograd bridge
is necessary at the native boundary. Neither adds an ownership or exception
system. Boundary rejection protects unsafe callback entry, initialization
deadlock, foreign-state mismatch and invalid generated access. Retire stale
checklist entries instead of creating process to satisfy them.
