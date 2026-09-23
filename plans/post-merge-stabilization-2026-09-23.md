> Status: active
> Approved September 23, 2026. Implementation starts from `8c0b1a92`,
> the then-current `origin/dev`. The retained read-only review is in
> `.context/post-merge-integration-review-2026-09-23.md` in the campaign
> workspace. Each completed batch records its delivery commit here.

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

Record evidence, dependencies, and a next experiment for shared
ownership/effects and exact-once finalizers; broader metadata consumers;
enum/LLP64/long-double/foreign-array/callback and untested-platform parity;
controlled evaluator/replay/module performance; and deletion of duplicate
builtin tag and signature-literal serializers. These are follow-ons, not
implicit implementation work or new recurring gates.

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
