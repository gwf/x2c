# Recover generalized meta declarations

> Status: obsolete
> The recovery checkpoints written before 2026-09-22's review, kept as
> evidence. The work they describe was superseded by the byte-storage
> implementation in [meta recovery](meta-recovery.md).

## Required result

`meta` advertises declarations for translation-time execution. Keep contextual
type adoption without an extra `type` keyword and separate initialized
file-static compile-time values from emitted runtime instances.

Struct locals use scope-owned backing memory. Field reads, writes, addresses,
initialization and value copies operate over that storage. Assignment preserves
the destination address and its field aliases. Invocation-local storage ends
with its execution owner, including exceptional exits. By-value results reach
caller-owned storage before the callee owner ends. Borrowed pointers retain
their actual owner's lifetime; session retention must not hide expired locals.
Persistent REPL values require a persistent owner distinct from temporary work.

Primary acceptance case: an ordinary local struct declared by a C library or
OS header is passed by address to a synchronous native API, filled in place,
and read by interpreted code. Its backing storage is reclaimed at invocation
exit, including exceptional exit. Supporting only x2c-authored record types
does not meet this requirement. Imported type/layout facts must use the
canonical compiler type owner, not handwritten copies, curated record lists,
or per-type APIs. Explicit `--cpp-symbols` discovery is approved; its corrected
header expansion and the native call path still require integrated validation.
Pointer retention by an asynchronous or retaining API is a separate lifetime
case and must not be treated as a synchronous borrow.

Representation and cleanup reuse existing Var and Cleanup protocol facts.
Marking a type does not expose all its methods. Native adapters and discovery
must derive from marked declarations, without a second handwritten inventory.
No type-name special cases or type-specific runtime API are permitted.

## Recovery work

### Campaign sequencing decision: native extensions last

User decision, 2026-09-22: project-provided native extension building and
dynamic loading are important but deferred to the final meta campaign stage.
The current stages use native implementations linked into the compiler;
rebuilding the compiler to add bindings is acceptable for current internal use.
Do not make extension loading, a new CLI command, or a plugin ABI prerequisites
for record/type/lifetime recovery. The architecture review is complete and
implementation has resumed under meta-recovery-design.md.

The final stage has an explicit two-stage workflow: first build the user's
native code with declaration-generated typed adapters into a host-loadable
module; then explicitly load/register it for translation, build, or REPL use.
Reuse normal build machinery, canonical types, existing adapters, and the same
binding path as compiler-linked natives. No libffi or bespoke ABI engine is
required by the proposed typed-adapter approach. Exact CLI/config spelling,
registration compatibility, shared runtime state, and module lifetime remain
design questions for that stage, not settled implementation details.
Compile-time extension dependencies and final application link dependencies
are separate; a library used only to compute embedded results need not become
an application dependency. Do not implement speculative loader scaffolding now.

### Current recovery sequence

1. Independently audit the current authored diff against the original request.
   Preserve evidence and distinguish salvageable lowering from rejected storage.
2. Remove the timespec bridge, its special compiler/interface cases and its four
   x2c helper APIs. Remove derived advertisements through normal generation.
3. Retain reviewed declaration parsing, scalar state and useful initializer and
   field-resolution machinery. Generate native target adapters from declaration
   metadata rather than adding manual math target rows.
4. Establish the general descriptor producer for field type, size, alignment,
   offset and access operations. Investigate newly encountered source types and
   existing compiled types explicitly. Do not substitute dynamic compilation,
   a curated type list or a narrower lifetime without a reviewed decision.
5. Replace list-and-cell record storage with the generic backing representation
   and connect it to invocation ownership, value returns, native borrowed
   references, applicable protocol cleanup, and persistent REPL state.
6. Test memory reclamation, exceptions, assignment alias preservation, nested
   records, by-value calls/returns, inline declarations and native mutation.
   Exercise unrelated record types through identical machinery. Demonstrate
   marker-derived function registration without a new handwritten target row.
7. Independently review and fix the authored diff, regenerate derived artifacts,
   inspect them, and run the repository gate. Stop for user review before push.

## Current evidence and design review

The independent initial audit confirms session-owned record cells and an
assignment bug: replacing the destination's record detaches existing field
addresses. A focused execution reproduced 12 from the meta implementation and
22 from equivalent native code for an alias retained across struct assignment.
The existing runtime already supplies Scope allocation, finalizers,
owner transfer, and typed Func argument references. Reuse those owners.

The current REPL rejects type declarations. Existing generic record lowering
also restricts fields to numeric scalars or nested adopted records. Neither is
evidence that the user's requested inline types or protocol-backed values work.

General layout production and ownership integration are under investigation.
This plan deliberately does not declare those implementation choices resolved.

## Active implementation checkpoint: 2026-09-22

The approved replacement now builds through its first self-host stage. It uses
one exact-C scalar ledger, compiler-owned derived layouts, and the existing
detached Lisp call frame for marked source-function automatic storage. The
parallel allocation tracker and blanket native-allocation override are removed.
Ordinary native heap allocations keep their native Scope ownership. C dangling
pointers remain undefined behavior, not a reason for an interpreter escape
scanner, implicit deep copies, or a persistent-container write barrier.

Focused checks on that built compiler pass for record copies/returns, stable
field aliases, inline/nested records, all native scalar field types, boxed
scalar container results, globals, and existing native functions. Actual
system-header field discovery passes with the approved --cpp-symbols path.
These are intermediate results, not an exact-tree gate.

Remaining integration work: native system API mutation through a real record
address; native scalar-pointer backing; explicit iterator destinations and
interpreted callbacks; combined lifetime/REPL/error-path coverage; independent
authored-diff review and final generated-artifact validation. Extension loading
remains deferred. Work is local and uncommitted.

## Historical recovery checkpoint: 2026-09-22 (superseded)

The following records the rejected intermediate design and its diagnostics.
Its proposed tracking/write-barrier policy is not the current architecture;
the active design and checkpoint above supersede it.

The work remains uncommitted and local on `codex/meta-values-types`. Authored
source removes the timespec-specific bridge and manual math target rows.
Declaration-derived target generation emits a `sinf` adapter. Generic record
descriptors, Scope-owned byte storage, stable places, in-place assignment,
native record adapters and REPL type/initializer handling are implemented but
still undergoing integration validation. No final gate has passed this tree.

The assignment-alias probe now runs as `22 22` (interpreted and native).
Instrumented compilation exposed a descriptor-builder double free caused by
combining deferred Array cleanup with `list_free`; the builder now leaves
cleanup with its deferred owner. This is not evidence that every lifetime
path is safe.

Independent review identified unresolved ownership boundaries:

- Mutating an already-persistent Array or Map can retain invocation-owned
  referents without passing through result export. A general persistent-write
  rule is needed; exporting only the final result is insufficient.
- Borrowed pointer pass-through in Context export does not recursively reject
  temporary pointers embedded in containers or closure captures. Top-level
  pointer checking does not cover those paths.
- Tracking covers record storage and evaluator scalar cells, not arbitrary
  native allocations exposed as raw pointers.

These findings block publication and completion claims. The proposed rule is
to preserve persistent container identity, export inserted values to its
owner, and reject pointers whose invocation-local storage would expire. This
consequential ownership choice has been presented for review; no new general
write-barrier mechanism is authorized by this checkpoint alone.

### Resumed validation

The compiler and unit-test executable now build after correcting generated
native layout assertions to use canonical declaration and identifier ASTs.
Generated C contains valid `sizeof`, `_Alignof`, and `offsetof` assertions.
Context and Iterator suites pass: 37 tests, 1530 assertions.

At that checkpoint two runs aborted: the Func suite at
`func_meta_record_value_and_place_bridge`, and the Lisp suite separately aborts
at `lisp_transports_void_outside_collections` (both exit 134). The binding
agent attributes the former to the test's handwritten descriptor disagreeing
with compiler metadata; that diagnosis needs a generated-descriptor regression
test, not relaxed descriptor validation. Subsequent diagnosis found the Lisp
run used the wrong working directory: its relative init.xlisp path requires
running from unittest. From that directory the named test passes; the suite
later reaches a separate native-constructor Func signature failure. This does
not establish an overall passing Lisp suite.
Logs are in `debug/meta-recovery-focused-units.log`,
`debug/meta-recovery-lisp-units.log`, and
`debug/meta-recovery-context-iter.log`. These failures must be resolved before
the final gate. Documentation now explicitly warns that its old layout and
session-lifetime descriptions are superseded and not release claims.

### September 22 integration evidence (not final-tree proof)

The rejected allocation tracker and ordinary-evaluator allocation override are
gone. Canonical compiler layouts and existing Scope/Context owners now drive the
small native-storage bridge. The full unit executable passed 943 tests with
20,628 assertions (`debug/meta-recovery-all-units.log`). Subsequent source edits
still require rebuilding and rerunning that evidence on the final tree.

The first broad fixture sweep ran 792 fixtures and exposed pointer/Var
conversion regressions, stale generated expectations, and old unsupported-case
expectations. Autodiff and meta-SDK regressions subsequently passed focused
reruns. Map output/cursor failures remain under investigation; they are not
approved behavior changes. The old frexp rejection fixture was removed in favor
of native-pointer execution coverage, and explicit Iter storage now has a
positive parity fixture.

Several new parity fixtures initially allowed the compiler to fold both calls.
Those runs proved interpreted results only. The fixtures are being corrected
to force runtime-dependent native calls, with generated-C inspection required
before claiming native/interpreted parity.

The initial optional REPL check passed. Stronger persistent-field-alias coverage
then exposed dropped top-level pointer declarator modifiers; the connected
preservation fix is being integrated. Completion also needs to avoid executing
meta declaration effects. No exact-tree gate or publication claim has been made.
