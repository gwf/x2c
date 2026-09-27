# Independent read-only phase5 review

Reviewed phase5 request, compiler-dual-macro-contract sections 1-6, and the
in-progress isolated macros/statements/transform/stage producer path. No source
edits, builds, or probes were performed by this reviewer in phase5.

## Contract qualifications

1. Final open preparation handles exactly three authoritative known native call
   roles: x2c_exception_push, sigsetjmp, x2c_exception_landed. It ALWAYS keeps
   native String callees with producer-known void/int result Types, even when
   a typed x2c declaration exists. The typed-callee attempt added forward
   declarations and failed raw C parity. Existing resolve_global rows are
   audit-only facts, not the emitted call contract. This preserves generated
   exception.h/setjmp declaration and include placement without fabricated
   program identities or guessed fallback signatures.

2. Preparation is private once per Compiler/unit at literal try/defer parsing,
   canonical try/defer binding, and managed-initializer cleanup production.
   Macro definitions do not prepare while macro_holes is active. These sites
   cover the synthetic tries later produced by defer lowering without adding
   late resolution in transform. The earliest relevant parse/bind site fixes
   the native protocol; later declarations cannot change it, by design for
   these three known native roles. This does not freeze first-use lookup for
   arbitrary source functions, typedefs or tags. Those generic roles are outside
   this narrowed phase5 proof, not additional blockers for its completion.

3. `_prototype_open_code` projects the stored body before parameter substitution,
   so it does not recursively reinterpret bound/lowered hole payloads. Its
   recognition of a call's compiler binding by name is specialized proof
   machinery. General free-role extraction and prepared role metadata remain
   required before the open rule can be broadly implemented. Meta producer
   callees are correctly outside the program free-reference rule.

4. The try lowering client now selects the Macro and calls shape with prepared
   values, without stage wrappers or envelope inspection. Actual `_try_frame`,
   `_try_declarations`, `_try_region`, `_try_landing`, `_try_cleanup` operations
   attach their established stages. Plain List remains source by contract;
   List shape never authenticates stage. The declaration sequence is lowered
   because its producing operation completed the relevant typed/lowered
   assembly, not because it happens to be a declaration-shaped List.
   Existing parent Expr conversion, return context and source-guard handling
   must stay ordinary owners. General staged producer composition still needs
   separate tests; successful try parity cannot establish all conversions.

5. Probe-only direct stage wrappers and four-callee native dispatch remain
   scaffolding. A successful candidate establishes the narrowed application,
   not the final generic helper ABI, transparent lifetime contract across all
   helper outputs, or arbitrary user meta-function dispatch.

## Cumulative budget

A 5% planning ceiling and 2% aim are reasonable proposed engineering choices,
not thresholds derived from the current noisy samples and not approved policy.
State them explicitly as advisory. A sustained overage should lead to profiling
and simplification or a user design decision, without new recurring gates.

Keep the actual current cumulative candidate-versus-original-baseline result as
one ledger total. A new lowering's incremental percentage-point contribution is
(new cumulative time minus previous cumulative time) divided by the SAME
original baseline time; it is not the sum of
independently measured percentage slowdowns against changing baselines. More
plainly, record each candidate's total ratio and derive its increment by
subtracting successive total ratios. Replacing a try implementation replaces
its row. Combined remeasurement remains authoritative because interactions and
noise invalidate a sum as a performance conclusion.

Record application count and transaction count (or explicitly unmeasured) in
actual ledger rows, not just in the prose requirement. Track default and live
modes independently. Negative noisy live deltas cannot pay for a repeatable
default slowdown. Include cold preparation separately if later migrations make
per-unit preparation substantial; current translation medians do not settle
cold startup, allocations, runtime hot paths or full build throughput.

## Final review evidence and remaining required checks

Final source was re-read after the native-projection and preparation fixes.
The actual try client has no explicit stage wrappers and writes the three
runtime calls inside the compiled-in open body. Preparation projects before
hole substitution, with no late transform resolver. The scope boundary now
matches the narrowed request. Parent reports saved candidate
`/tmp/x2c-dual-phase5-final`, SHA256
`ed6eb83bfb2e8977554ade3b95baaa75df123f58e3d76e9f6b646322e56252c5`,
passes the opt-in caught rollback probe and native continuation (`17 1 1 23`).
This reviewer did not rerun it.

Required phase5 evidence still pending at this review timestamp: final same-
binary 62 raw C/H/outcome comparison and paired cost measurement. Earlier
phase4 parity establishes its own bound-native-hole control only. Once those
complete, no further generic open-role/hygiene/ABI experiments are required to
complete this narrowed phase5 proof. Freeze qualifications remain necessary:
three native roles, provisional private dispatch/carriers, and producer-stage
facts demonstrated for this try path. Cold preparation cost, allocation counts,
all compiler state rollback and generic conversion instrumentation were not
requested as new completion gates and remain unmeasured limitations.

The root plan's phrase "That proof passes" should refer explicitly to phase4
until the final phase5 comparison completes. The migration ledger should mark
application count unmeasured if it has not been counted; one transaction per
try is an implementation fact, not a measured total transaction count.
