> Status: done
> Completed locally on 2026-09-20 with tokenization, lowering-map, and parser
> scratch fixes, retained-result checks, and 100,000-input sessions.
> See tools/repl-spike/long-session.md for the assessment; no publication.

# Persistent REPL ownership assessment

Establish whether the existing submission API can support long sessions with
understood memory growth and preserved behavior. Work remains local on the
spike branch. Compile-time execution coverage belongs to the other task;
redefinition, production integration, and a general collector are out of scope.

## Completion criteria

- Attribute the remaining fixed-input growth to concrete allocation owners,
  distinguishing temporary containers, canonical values, and persistent state.
- Reclaim proven temporary storage through existing free/scope operations.
  Preserve old results until unit close, published definitions, captured values,
  diagnostics, and the existing rollback/side-effect contract.
- Run fixed, growing, failed, incomplete, and mixed workloads at increasing
  lengths. Check state and old results after later submissions; compare native
  results where the supported subset permits it. Record memory/time limits,
  slopes, and observed limits rather than claiming bounded storage from RSS.
- Finish with an assessment of integration readiness and remaining ownership
  choices. A residual lifetime problem is a documented result, not permission
  to redesign runtime ownership or silently shorten the result lifetime.

## Work

1. Trace parser, lowerer, and evaluator allocations using source and focused
   phase probes. Existing benchmark at b50c712d retains about 104 allocations
   per fixed update; transaction-only retention is zero.
2. Apply connected, evidence-backed temporary-container fixes. Avoid blanket
   submission scopes: compiler maps, returned values, and closures may escape.
   Keep canonical owners and ordinary semantic operations authoritative.
3. Extend optional spike checks with durable-result, recovery, long mixed
   workload and definition-growth cases. No recurring gate is added.
4. Review and fix the complete authored diff; run the existing spike checks
   and relevant compiler/runtime checks. Record results, limits, and recommended
   integration work; commit locally and archive this plan.

Routine measurements, fixes, and validation proceed without another approval.
Return to Gary for changes to semantics, caller lifetime obligations, or a
new general memory-management design. Local delivery does not run publication
or move the review base to another task's provisional work.

## Plan review

Canonical pools establish List/String lifetime, not the lifetime of mutable
objects or boxed values embedded in them. Scope allocation ownership is
established at creation, and maps borrow their entries. Explicit frees require
proving no container identity escapes; ordinary parsing and lowering remain
the semantic owners. Reuse existing allocation statistics, Scope/free APIs,
transactions, and optional spike harnesses. No new representation, evaluator,
cache, validator, or dedicated diagnostic is planned. Lifetime tests protect
against use-after-free, lost state, and rollback corruption; measurement code
stays in the optional spike tools or temporary probe directory.

## Completed assessment

Fixed-input retention falls from 104 to 42 allocations per submission.
Repeated lowering of an existing AST is allocation-flat; replacing its Lisp
callable retains six allocations per replacement. Fixed and mixed sessions
complete 100,000 inputs with correct state, at 355.7 and 326.6 MiB peak RSS.
Generic lexical maps and canonical/callable owners still retain storage; no
claim of bounded memory or full object-by-object attribution is made.
Production readiness needs explicit result/callable lifetime and transaction
scaling decisions. The existing unit-close result lifetime remains unchanged.

The authored diff was reviewed and corrected before final checks. All 747
fixtures, 19 terminal checks, native parity, retained-result/recovery checks,
and a generated compiler/runtime/client AddressSanitizer build pass. The
optional stress harness also covers 10,000 growing definitions, failures,
incomplete input, and independent lowering/evaluator controls. No bootstrap
refresh, recurring gate, remote push, or comptime coverage integration occurred.
