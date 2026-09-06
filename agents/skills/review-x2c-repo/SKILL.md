---
name: review-x2c-repo
description: >-
  Survey the repository or one named area of it for latent defects,
  inconsistencies, drift, and things that should be removed, then report what
  reproduces. Use for a post-merge integration review, a
  whole-repository sanity check, or a focused maintenance pass over tests,
  benchmarks, documentation, or examples. Do not use to carry out a broad
  deletion campaign; use simplify-x2c-source.
---

# Review the x2c repository

Find what is actually wrong and reproduce it. Review requests are read-only;
fix findings or write a tracked catalog only when the user explicitly
authorized changes for this session.

The caller sets the scope when they name a merge window, subsystem, or one
axis such as test coverage, benchmark health, documentation accuracy, or
examples. A direct invocation with no narrower scope, or a request to review
the repository, means the whole repository. Do not silently reduce it to
recent merges.

## Establish the relevant baseline

Record the current branch and `HEAD`, reuse current green evidence when it
applies, and run the smallest relevant non-mutating checks while discovery
proceeds. A read-only review is not publication: do not run
`agent-pr-check` merely to establish a baseline. The baseline says what passes;
it does not replace inspecting the requested scope.

## Slice the scope and name a hypothesis for each slice

Derive slices from evidence, not arbitrary directory ranges. For a post-merge
review, take the merge range from `git log` and give each merge its own
section. For a focused pass, slice the one axis by owner. For a
whole-repository review, cover the compiler, runtime, build and tooling, tests,
packages and examples, documentation and site, and release readiness. Recent
changes can suggest hypotheses for those surfaces; they cannot substitute for
covering them.

Give every slice a named hypothesis: the specific asymmetry or failure you
expect there, and what evidence would show it. "Compare the map family
against the array family for a guard, error path, or convention present in
one and absent in the other with no principled reason" produces findings.
"Review `lib/`" produces prose.

Fan out read-only across slices. Do not call the review complete until the
requested slices were examined; if time or evidence leaves a slice unchecked,
say the review is incomplete and name it.

## Apply x2c's standards to recommendations

Judge findings by the root Project Priorities and the `Trust what was actually
established` section of `agents/x2c-philosophy.md`, not generic
defensive-programming expectations. A review that asks a trusted consumer to
repeat validation already owned by its producer is harmful; recommend removing
that validation. If an invariant is not actually established, strengthen its
existing owner instead of adding checks to every consumer.

Recommend new validation only at an untrusted or status-bearing boundary, for
deliberate public behavior, or when the existing path can accept wrong output,
corrupt state, or cross an unsafe native boundary. Name and reproduce that
consequence. Risk aversion by itself is not a finding.

Compile-time Lisp is trusted code, and canonical AST Lists are deliberately
accepted by structure rather than authenticated by origin. The settled rule is
in `docs/src/reference/language.md` under "Macro-visible syntax". Do not call a
legal AST assembled by Lisp a forgery, including `src`, `construct(src)`, or a
static declaration, and do not recommend identity tracking, provenance state,
a second validator, or a negative fixture to reject it. This is a
do-not-re-report decision. Malformed data and forms rejected by the ordinary
operation for their position remain separate behavior.

For parser, macro, compile-time Lisp, Match, transform, generator, or emitter
work, read `agents/replacing-manual-ast-walks-with-match.md` and check whether
each producer constructs the canonical AST and reaches the ordinary semantic
operation for that form. A parallel decoder, validator, repair walk, or
semantic constructor is a candidate only after its distinct behavior is
reproduced. `x2c-graph flows` and `compare` can establish exact parsed-source
paths, but a shared or exclusive path is evidence to inspect, not proof of
semantic equivalence or a defect.

## Reproduce before a finding becomes work

Reviewers reading source cannot reproduce anything, so the root `AGENTS.md`
rule about subagent claims is the whole job here rather than a caution.

Reproduce every finding at current `HEAD` before it enters a catalog, a plan,
or a fix. If it does not reproduce, it is not a finding; record it as refuted.
Rank by what the reproduction shows, not by how alarming the description is.

Verification is the part of a review that is usually too thin. Spend the
budget there rather than on adjudication layers, priority taxonomies, or
agents reviewing other agents' findings.

## Stop or fix according to the request

For a review-only request, report the reproduced finding, its consequence, and
the exact repair without editing the worktree. Do not create a tracked catalog.

When the user also authorized fixes, follow `fix-x2c-bug` for anything that
needs diagnosis and keep unambiguous mechanical corrections in the same pass.

When changes were authorized but a repair needs a design decision, changes
public semantics, or is large enough to deserve its own session, stop and
report it. Write a catalog only when the user requested one.

## Record only when authorized

When the user requested a durable catalog, write it into `plans/` under
`plans/README.md`'s conventions, with the `> Status:` header and a date in the
name. It is durable planning, not
ephemeral workspace state. Catalogs written to `.context/` have been lost
every time, and the next review then rediscovers the same defects.

The record has three required parts:

- **Findings** still open, each with its reproduction and its owner.
- **Refuted** claims, with why they do not hold, marked do-not-re-report. This
  is the part that is always dropped and the part that saves the most work.
- **Verified clean**, naming what you examined and found sound, so the next
  review knows its coverage instead of re-reading it.

## Route removals rather than listing them

Removal candidates found here are rarely acted on as catalog rows. When a
review finds connected structural bloat, name it as a candidate campaign for
`simplify-x2c-source` with its evidence, rather than filing individual rows
that nobody executes. Delete small unreferenced things only when changes were
authorized.

## Report

When the user requested a catalog, it holds the detailed record: the baseline,
what was fixed, what was reproduced and left open, what was refuted, and what
you verified clean.
Gary gets the current findings, what you recommend he do about them, and
whether the workspace is safe to delete, in the self-contained reply the root
`AGENTS.md` Communication section describes. Link the catalog as supporting
evidence, never as a substitute for that answer. A review that recounts its
process at length has produced nothing. State the scope actually examined and
do not make a broader completeness or release-readiness claim.
