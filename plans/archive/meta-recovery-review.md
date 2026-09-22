# Meta recovery: the short review

> Status: obsolete
> Superseded on 2026-09-22 by the byte-storage implementation recorded in
> [meta recovery](meta-recovery.md). This review kept a record
> wrapper, a per-allocation tracker and a runtime scalar dispatch that the
> independent review rejected; it is preserved as evidence only.

## Implementation checkpoint - September 22

The recovery milestone is approximately 60% complete; this is an engineering
estimate, not a test-pass percentage or a claim that the complete campaign is
ready. Native system-header records (`timespec_get`), scalar output pointers
(`frexp`), and user iterator callbacks with explicit local storage now have
passing native/interpreted parity cases. The storage tracker has been removed,
and scalar projections share the compiler's native scalar ledger.

Remaining before handoff:

- Fix integration regressions in protocol-valued scalar cells and pointer/Var
  conversion; verify canonical pointee qualifiers through real source calls.
- Finish lifetime, persistent REPL, return, and exceptional-exit regression
  checks without changing ordinary native heap ownership.
- Complete independent authored-diff review, regenerate derived artifacts,
  and run the exact-tree gate. No commit or push is authorized.
- Surface remaining type-shape/protocol gaps below; do not count them as
  silently accepted exclusions.

Dynamic native extension building/loading remains a separate final campaign
stage, not part of this recovery milestone.

## The picture

```text
Your declarations
    -> compiler types + shared lifetime/protocol facts
    -> interpreted operations using those facts
    -> existing Scope storage and native Func adapters
```

No parallel type inventory, memory tracker, or interpreter escape checker.

## 1. Local records, including system-header records

```c
SystemRecord result = {0};       // Illustrative system-header type.
int status = system_query(&result);
if (status == 0) use(result.field);
```

The native API writes the actual bytes backing the local. The source function's
automatic-storage Scope reclaims them on return or error. Compiler header
discovery supplies the type, not a handwritten replacement or special wrapper.

**Decided:** use existing `--cpp-symbols` when a header body is otherwise
unavailable. Gary accepted this first-stage requirement on 2026-09-22.
Automatic discovery is deferred; no silent fallback or replacement declaration.

## 2. Assignment and return

```c
int *alias = &a.x;
a = b;                         // Copy into a; alias remains valid.
return a;                      // Copy value before local storage ends.
```

Use the existing interpreted call frame, distinguishing source functions from
synthetic Lisp lambdas. Returned aggregate bytes reach the caller while the
callee is still alive. No hidden-result calling convention or execution stack.

**Engineering check:** settle owner propagation across callbacks, parameter
materialization, and optimized execution before implementation. Semantics agreed;
no request for you to reconfirm C behavior.

## 3. Heap lifetime is not automatic-local lifetime

| Storage | Owner |
| --- | --- |
| Bytes standing in for C automatic locals | Source-function frame |
| Ordinary Scope heap allocations | Source program's active Scope |
| Persistent REPL bindings | Session |

A native C call does not automatically open a heap Scope. Removing the recovery's
blanket allocation override avoids inventing promotion machinery to repair its
shortened lifetimes. Array/Map stores remain shallow and preserve identity.
Value boxing copies aggregates as native x2c does; pointers remain borrowed.

## 4. Protocol adoption and user iterators

Internal adoption reuses the existing Iter/Var/Cleanup conformance and explicitly
advertised operations. It does not expose every method of a marked type.

User meta map/filter callbacks have existing Func-backed iterator machinery.
A new pull callback is a distinct case: a native function pointer is not an
interpreted function. Its reusable bridge must be established, not assumed or
replaced with a new protocol. Returned state, source, and captures must all remain
alive under the same rules as compiled code.

**Engineering check:** custom pull callbacks and source-function callback owner
propagation. No claim that composition tests establish full iterator support.

## 5. Native functions now; extensions last

Current stage: mark declarations, generate existing adapters, rebuild compiler.
Interpretable user meta bodies do not require that rebuild.

Final stage: build a native extension, then explicitly load it for subsequent
translation/build/REPL use. Reuse typed adapters; no libffi requirement. No loader
scaffolding belongs in the current recovery.

## Limits to review, not hide

Array/union/bitfield/anonymous or layout-attributed members, all pointer families,
and all lifetime flows are not established by the current implementation.
These are **not approved exclusions**. A narrower first delivery requires an
explicit choice; it cannot quietly become the meaning of "ordinary structs."

**Execution now authorized within this reviewed design.** The detailed plan
records keep/consolidate/remove decisions and bounded mechanism checks.
Consequential scope changes still require review; publication is not authorized.
