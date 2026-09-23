> Status: active
> Approved September 23, 2026. Implementation starts from `8c0b1a92`,
> the then-current `origin/dev`. The retained read-only review is in
> `.context/post-merge-integration-review-2026-09-23.md` in the campaign
> workspace. The local reconciliation below records the repair commits;
> delivery to `dev` still requires Gary's approval.

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
   prove or decline native record layouts (F4). F4 excludes packed layouts:
   packing is unsupported and produces a direct compile error. F2 also
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
| Shared ownership and effects | S2 fixed pooled result summaries, but aggregate-contained borrowed pointers, retaining native calls, unknown callees, pointer arithmetic, and exact-once File/Job finalization remain outside the current advisory proof. | Add an aggregate borrow and a retaining native callback control; compare region warnings and meta eligibility with native lifetime and call effects. |
| Compiler metadata consumers | M2 enumerates selected public definitions; protocol witnesses, editor discovery, and bounded runtime exposure have separate consumers. Representation and effect proof must precede wider methods. | Trace a supported Iter witness into docs and editor output, then test a bounded Buffer/Array/Map candidate. |
| Native representation parity | Positive-only enum signedness differs on the reviewed macOS target; ordinary folding is fenced. LLP64 `size_t`, wider `long double`, foreign arrays, callback signatures, and Linux/WSL or APE/MSYS2 behavior were not validated. | Run a native/meta boundary matrix on LLP64 and extended-`long double` hosts; test one foreign array and callback crossing. |
| Performance | The saved snapshot predates this campaign; noisy timing deltas do not attribute a regression. Func frames, evaluator replay, and module relinking need controlled measurements. | Compare exact committed trees on one quiet host, then isolate Func per-call cost, include replay, and no-op versus changed native-module links. |
| Duplicate serializers | `src/type.x` repeats builtin tag membership already represented by Var tags; `etc/lisp-bindings.x` recursively builds signature literals alongside compiler literal caching. | Prove focused generated forms match canonical owners, then delete one duplicate table or builder at a time. |

## Local commit reconciliation

The following 26 change commits follow `8c0b1a92` on the stabilization
branch. The named fixtures and probes are the bounded evidence for retaining
them; this ledger does not claim every platform or argument combination was
tested. The two upstream integration merges and the later user-directed pack
correction are listed separately.

| Plan item | Commits | Disposition and evidence |
| --- | --- | --- |
| C1 destination conversion | `a1779f0a`, `310399be`, `c934bccd` | Retain. The `meta-destination-conversion` fixture covers destination, pointer/Symbol, and conditional-symbol cases; the local constant-string follow-up adds its composed hash case. |
| C2 effects and writes | `8d14c9f2`, `0c747a85` | Retain. `meta-fold-effects`, `meta-expression-effects`, and `run-meta-native-effects.sh` cover runtime effects and selected-branch writes. |
| C3 typed Func calls | `08edced1`, `05d993d1`, `a44f4762`, `6de15600` | Retain the typed-call repair, redundant-conversion cleanup, Lisp callback follow-up, and generated bootstrap bridge. `meta-func-calls`, `run-lisp-init.py`, and stage comparisons cover the transition. |
| C4 local statics | `b6d79c71` | Retain. Local-static fixtures and `run-meta-local-statics.sh` cover evaluator-session storage. |
| F1 foreign tags | `bd723e57` | Retain. `package-foreign-tag` checks first-use foreign tags. |
| F2 lexical templates | `5da137cb` | Retain. Lexical-shadow macro fixtures check template binding identity. |
| F3 source-unit names | `e801a32a` | Retain the distinct-unit naming behavior. The macro file-scope probe and three reviewed macro snapshot corrections cover its generated-name changes. |
| F4 native layout | `b5f3d5ba`, `7815096c` | Retain `b5f3d5ba`'s nonpacked layout protections. Its pack support and all of `7815096c`'s pack-uncertainty replay are superseded by `2334d78c`, which rejects packed layouts. |
| S1 static initializers | `fb1009c8` | Retain. `static-initializer-classification` checks evaluation and storage classes. |
| S2 pooled ownership | `858f935a`, `fe7a95ad` | Retain. Pooled and mixed ownership fixtures cover both summaries. |
| S3 native modules | `7a50d0cb` | Retain. `run-native-modules.sh` checks relinking after library changes. |
| M1 graph tooling | `d26c3f1e`, `2971ca48` | Retain. Graph AST parity and allocation tests cover preload and direct counts. |
| M2 public definitions | `f1228d90` | Retain. The public-definition projection probe and generated API reference cover compiler-selected declarations. |
| M3 inventory | `a56fc066` | Retain failed-probe fences. The fresh optional `meta-api-coverage.py --probe --write` report records the repaired tree; it remains evidence, not a gate. |
| M4 sanitizer | `760c2c28` | Retain. The full sanitizer script receives sufficient stack. |
| M5 editor | `14f5b50b` | Retain. Editor grammar tests cover contextual `meta`. |
| Status and disposition | `82396494` | Retain the evidence-status reconciliation and bounded `meta_api_disposition.py` rules; the fresh M3 report exposes their resulting classifications. |

`19e29a03` integrated upstream documentation/sample and build-metrics work;
`be751853` integrated upstream symlink-home and build-cost work. Neither is a
packed-layout repair. `2334d78c` then removed pack replay, made `#pragma
pack` and packed attributes direct errors, and regenerated bootstrap. The
later `0b4c2d87` merge includes current `origin/dev` build-metrics changes.

The ten worker worktrees have no missing committed repair to cherry-pick.
`ef39528f` is patch-inequivalent by history but its source and fixture bytes
are represented by `0c747a85`. Of six dirty frontend files, the local
constant-string source and two fixture files were integrated, the generated
API inventory was rerun on the repaired compiler, and the two status files
were reconciled without importing their stale next-phase link. The original
checkout's modified backlog is incorporated above; its untracked next-phase
plan is copied here with pack replay removed. No next-phase implementation
has started.

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
