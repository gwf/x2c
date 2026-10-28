# Allocation accounting and Notes database ownership

> Status: active
> Implementation and focused verification are complete on 2026-10-28.
> Ready for shared integration and final publication validation. The mutex
> Notes baseline retains response construction outside the database lock.

## Requested result

Make Scope allocation accounting opt-in and disabled by default. Preserve
ordinary allocation ownership, cleanup, and the public ScopeStats layout.
Compare the Notes mutex server against a variant whose dedicated thread owns
SQLite and receives requests through a shared channel, with one reply channel
carried by each request. Keep the unchanged Go implementation as a reference.
The channel topology was explicitly selected by Gary.

## Decisions

- Latch X2C_SCOPE_ACCOUNTING=1 at Scope initialization. Other values and absence
  leave accounting off. No mid-process enable/disable API is introduced.
- Scope.accounting_enabled reports that fixed mode. Scope.stats returns zero
  counters when disabled. Scope, managed-allocation, and raw-backing counters
  share the mode; metadata, names, ownership, and finalizers are unchanged.
- The LSP and REPL explicitly opt in when launched by the compiler because
  retained-memory recycling and statistics depend on those counters. Existing
  tests that assert counters opt in at process launch. Default-off behavior has
  focused coverage. Disabled automatic leak accounting is documented.
- The mutex Notes app keeps copied-row acquisition and statement finalization
  inside the mutex, then performs missing-row handling, Map construction, and
  tag parsing outside it.
- The database-thread server is an independently executable benchmark variant,
  with the same routes, SQLite schema, SQL, CLI, logging, persistence, and
  prepared-statement policy. Database open/use/close belongs to one thread.
  HTTP parsing and response construction remain in HTTP workers.
- Request/reply storage must obey existing Channel, Scope, and Pool lifetime
  contracts. The HTTP worker creates a child output Scope and buffered reply
  channel before submitting its stack request. Only the database thread writes
  that output while the HTTP worker waits. The database thread borrows the
  request Pool and output Scope for the query, then restores its own state
  before posting completion. No output export or second acknowledgement is
  needed. Do not add runtime synchronization or ownership machinery.

## Evidence and work

Previous controlled measurements are in debug/notes-accounting/findings.md.
Per-allocation accounting off increased the moved-response variant from 28,528
requests/s to 54,977 requests/s; Go reached 65,869. Those temporary binaries
suppressed three accounting helpers, whereas the permanent opt-in covers all
Scope statistics. New comparisons therefore use matched final-runtime builds.

Accounting and database-variant workers have isolated worktrees, based at
8abe19fad00cd86d6cab7a57ed38f08cf47a453a, with private handoffs. The orchestrator
owns the benchmark harness, integration, authored-diff review, and PR submission.
The active shared integrator owns final generated artifacts and full
publication validation; this session runs no full gates.

After combining reviewed changes, run meaningful focused runtime/command checks
and the existing Notes API/concurrency/restart checks for both servers. Compare
optimized mutex, database-thread, and unchanged Go binaries using identical
1,000-row fixture copies, 64 clients, one-second warmup, five-second measurement,
and five rounds with varying order. Preserve all samples, native provenance,
errors, and resource metrics. No timed loads run alongside worker builds.

## Design review

The environment latch avoids partial statistics and free-counter underflow from
late activation. Consumers opt in instead of silently losing memory estimates.
The dedicated database thread is Gary's requested alternative, not an inferred
runtime redesign. A benchmark variant keeps both approaches reviewable without
adding a runtime backend switch to the normal app. Response lifetime and error
propagation are the main implementation questions. Do not promote either
architecture based only on a successful prototype or a single timing sample.
Review and fix the complete authored diff before submission.

## Completed comparison

The [dated report](../examples/apps/notes/bench/reports/2026-10-28-architectures/interpretation.md)
retains all fifteen measurements and build provenance. At 64 clients, medians
were 49,765 requests/s for mutex x2c, 38,650 for database-thread x2c, and 65,858
for Go. The database-thread variant had lower p99 latency (2.59 ms versus
4.69 ms) and higher CPU use. Both x2c variants passed the external Notes suite;
SQL error recovery, outstanding-write shutdown, and failed-reply allocation
were also checked. The ordinary example remains the mutex version. The
shared integrator owns the remaining final generated refresh and gate.
