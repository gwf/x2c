> Status: done
> Approved and delivered September 23, 2026 as `9b71607f` on `dev`,
> including the scope strip `30615669`. The retained read-only review is in
> `.context/post-merge-integration-review-2026-09-23.md` in the campaign
> workspace.

# Post-merge stabilization

Repair the confirmed compiler, runtime, package, build, and tooling defects
before further meta-surface expansion. Preserve native behavior for ordinary
calls. Explicit meta evaluation remains available for native targets whose
effects cannot be proved foldable. Typed and reference-bearing `Func` calls
and function-local statics require full supported execution in the evaluator;
declining those supported cases does not close this plan.

## First implementation batch

- C1: Resolve destination types before conditional, typedef, pointer,
  Symbol, argument, return, and constant-value conversions. Include the
  composed `String.hash` case.
- C2: Carry existing transitive effect facts through native wrappers and
  persistent storage, fence unproved enum folding, and execute discarded
  expression effects in the selected branch exactly once.
- F1: Give package tag ownership to definitions and standalone forwards,
  while preserving foreign first-use tags.
- F2: Preserve lexical binding and tag identity inside source templates.
- S1: Classify fixed `sizeof`, VLA-dependent `sizeof`, and transformed local
  collection static initializers according to their actual evaluation.

Each repair starts with its retained source repro on the current base, adds
focused behavioral coverage, reviews the authored diff, and records a local
commit. Integrate independent commits only after conflicting owners are
sequenced. The campaign checkout alone publishes to `dev`.

## Dependent repair sequence

1. After C1/C2, implement typed value and reference-bearing `Func` calls
   (C3), then session-owned persistent compile-time local statics (C4).
   C4 also depends on S1. Call preparation uses canonical signature and
   native-defined evaluation order; reference carriers address live caller
   lvalues. Static identity is the function and local binding, scoped to one
   evaluator translation session, with first-reach, retry, recursive-init,
   and stable-address behavior.
2. After F1/F2, distinguish same-basename source units (F3) and conservatively
   prove or decline native record layouts (F4). A packed attribute on a
   parsed source struct is rejected; `#pragma pack` passes through. F2 also
   unblocks complete compiler-selected public-definition enumeration (M2).
3. Repair pooled ownership summaries (S2), native-module link freshness
   (S3), graph preload and allocation reporting (M1), docs generation and
   fresh API inventory (M3), the default full sanitizer invocation (M4),
   and editor grammar and evidence-backed status (M5). M3 follows semantic
   repairs and M2; M1's allocation portion follows S2.

## Validation and delivery

Use the relevant differential repros and real consumers: foreign packages
plus HTTP/JSON, native modules, graph/parity, full sanitizers, docs/site,
editor, and an installed compiler module. Check cold/warm interfaces and
staged reproducibility when serialization or ownership changes. Independently
review calls, storage, and native crossings before publication. Fetch and
integrate current `origin/dev`, review authored and generated diffs, run
`git diff --check`, then run `tools/gate-state.py ensure agent-pr-check` on
the exact candidate tree. Run a separate advisory performance checkpoint for
throughput, generated runtime, or build-orchestration changes. Push explicitly
to `refs/heads/dev`; never advance `main` for this campaign.

## Backlog boundary

These are follow-ons, not implicit implementation work or new recurring gates.

| Priority | Evidence and dependency | Next experiment |
| --- | --- | --- |
| Shared ownership and effects | S2 covers pooled and mixed Scope/Pool result summaries, but aggregate-contained borrowed pointers, retaining native calls, unknown callees, pointer arithmetic, and exact-once File/Job finalization remain outside the current advisory proof. | Add an aggregate borrow and a retaining native callback control; compare region warnings and meta eligibility with native lifetime and call effects. |
| Compiler metadata consumers | M2 enumerates selected public definitions; protocol witnesses, editor discovery, and bounded runtime exposure have separate consumers. Representation and effect proof must precede wider methods. | Trace a supported Iter witness into docs and editor output, then test a bounded Buffer/Array/Map candidate. |
| Native representation parity | Positive-only enum signedness differs on the reviewed macOS target; ordinary folding is fenced. LLP64 `size_t`, wider `long double`, foreign arrays, callback signatures, and Linux/WSL or APE/MSYS2 behavior were not validated. | Run a native/meta boundary matrix on LLP64 and extended-`long double` hosts; test one foreign array and callback crossing. |
| Performance | The saved snapshot predates this campaign; noisy timing deltas do not attribute a regression. Func frames, evaluator replay, and module relinking need controlled measurements. | Compare exact committed trees on one quiet host, then isolate Func per-call cost, include replay, and no-op versus changed native-module links. |
| Duplicate serializers | `src/type.x` repeats builtin tag membership already represented by Var tags; `etc/lisp-bindings.x` recursively builds signature literals alongside compiler literal caching. | Prove focused generated forms match canonical owners, then delete one duplicate table or builder at a time. |

## Current implementation evidence

The stabilization candidate retains the focused destination-conversion,
effect, foreign-tag, lexical-binding, native-module, graph, sanitizer and
editor fixtures. Compile-time `Func` and local-static behavior is limited to
the cases exercised by the retained fixtures. Generated documentation and
interfaces are checked with the final tree. Packed directives pass through
to C; parsed source structs with a packed attribute are rejected. The
mixed-owner warnings remain covered by their fixture. Unneeded probe scripts
and speculative meta-surface cases are outside this delivery.

## Plan review

Existing parser, type, binding, static-initializer, layout, and allocation
producers establish the facts their consumers need. Repairs reuse those
canonical operations and structural AST Lists, removing duplicate or
incorrect paths instead of authenticating syntax origin or adding a second
validator. New persistent state is limited to evaluator-session static
storage and callable-signature transport, whose lifetime and identity cannot
be represented by an automatic frame. Negative cases protect native crossing,
established argument refusals, recursive static initialization, and truthful
API completeness; no other dedicated validation layer is planned. Review
each completed source diff for repeated checks, extra state, and opportunities
to delete obsolete paths before publication proof.
