# plans/

All durable planning lives here. Build tooling and runtime-loaded bootstrap
data stay in `etc/`; ephemeral per-workspace state goes in `.context/`.

- `plans/` - active plans and reference inputs. Each file opens with a
  `> Status:` blockquote, usually several lines: the state, then a note
  saying where the work actually stands. The states in use are `active`,
  `blocked`, `reference`, and `needs author scoping`.
- `plans/archive/` - finished plans. The same blockquote, recording the
  outcome, its date, and the commit or PR that closed the plan. Write
  `done`, `rejected`, `obsolete`, or `retired`. Older entries also say
  `complete`, `completed`, `archived`, `superseded`, and `corrected`; each
  of those means `done` or `obsolete`. Never delete a plan; archive it with
  its outcome. Archived workflow restrictions record the authorization that
  applied at the time; current work follows the root `AGENTS.md`.

Keep a plan concise and decision-complete: the requested behavior, important
choices, implementation, relevant validation, and delivery should be clear to
another engineer. Use phases only when the work needs separately delivered
changes. Record measurements when they decide the design or verify its result,
rather than requiring a count for every task. Update status when work lands.

A planning-only request ends with the plan. An implementation request allows
routine missing details and the design review to be completed during the work.
Ask about unresolved consequential choices, such as public semantics or
compatibility beyond the request, rather than stopping for missing paperwork.
Delivery follows the root `AGENTS.md`; a plan need not imply a PR or another
session.

An archived rejection records the exact implementation, compiler capability,
and evidence measured at that time. It does not create a permanent rule against
the candidate family. New syntax, projections, compilation behavior, source
structure, or measurements may justify a new prototype. Treat old phrases such
as `do not reopen` or `no other candidate` as historical unless current
`AGENTS.md`, agent guidance, or an active plan restates the exact restriction.

## Current work and backlog

Reviewed against dev 2685655f on 2026-09-30. A historical
plan's original branch, baseline and authorization notes are evidence for
that work; its opening status and this index distinguish them from current
execution.

### Current work

- [Harness simplification and messaging](harness-simplification-and-messaging.md):
  authorized corrections to existing tools and guidance, a small
  cross-platform integrator messaging pilot, and separate external runtime
  repairs. Tool repairs and native messaging are implemented; external
  runtime repairs remain open.
- [x2c code standard](x2c-code-standard.md): stage 1 landed; Gary accepted
  the standard
  and decisions D1-D5 on 2026-10-05. Stage 1 (authority) and stage 2
  (Error keys, `<malformed>`, `builtin_*` linkage) are ready; stage 3
  (lint) follows stage 1, then repeated scan-and-fix cycles.
- [x2c self-expression](x2c-self-expression.md): Phase 0, language work,
  three waves, and the retained prototypes are on dev. The recorded
  follow-ups and unresolved language questions remain active.
- [Source consolidation research](source-consolidation-research.md): working
  typed-family, lowering, runtime, transaction, and package prototypes, with
  all original proposals tracked separately. Publication is implementation authorized.
  The earlier [first-wave record](archive/evaluator-and-source-consolidation.md)
  remains as corrected historical evidence.
- [Public release workflow](public-release-workflow.md): staging is live at
  `staging.x2c-lang.dev`, with successful candidate and staging runs. Only
  production baseline recovery, candidate/version choice, and promotion to
  `main` remain as release decisions.
- [Meta follow-ups](meta-followups.md): the meta protocol and native extension
  milestones were delivered through [meta sequencing](archive/meta-sequencing.md).
  The remaining recorded limits are system-header/layout details and
  `off_t`/`time_t` mapping; they do not block the delivered capabilities.

### Open backlog and scoped follow-ups

| Record | What remains |
| --- | --- |
| [Idiom synthesis, October 4](idiom-synthesis-2026-10-04.md) | Private implementation against origin/dev fd88fae4. Binder syntax clarified; three adjacent defects repaired. Fifteen issue families, four research records, selected rewrites, retained contracts, and bounded composition experiments. Delivery authorized only to codex/idiom-synthesis-refresh; PR and integration held. |
| [Post-integration fix list, October 2](post-integration-fix-list-2026-10-02.md) | Active orchestrated campaign: 42 scopes, three prior delivered repairs, and every review finding accounted for. Sol workers implement private batches, including the named-macro catalogue replacement and its literal-lowering prerequisite. |
| [Quotation adoption audit](quotation-adoption-audit-2026-10-03.md) | Param, Type, and Decl quotations; a structural rebuild for Unit, Field, and declarator syntax; and the retained autodiff review. Its other follow-ups landed through PRs #131, #142, and #143. |
| [SDK and system macros](macro-sdk-and-system-macros.md) | Captured-code diagnostic locations and enum consumers; the removed varops Lisp file is no longer work. |
| [Lint, format, and compiler-backed tools](x2c-lint-and-format.md) | Active; phases 0-7 delivered. The completed linter now runs as experimental `x2c lint`; later lint, format, and source-tool phases remain. |
| [Tooling ports](x2c-scripting-ports.md) | Extensionless tool names, the llms.txt generator, the documentation sample checks and `tools/check-docs` are delivered; release and gate ports remain; the compiler-backed rewrite moved to the lint plan. |
| [C on-ramp](x2c-c-on-ramp.md) | Landing-page adoption examples; the parser/corpus work already shipped. |
| [Explicit meta campaign](archive/explicit-meta-and-lifetime-campaign.md#backlog) | Parked compound-selector owner, direct function-handle assignment in meta bodies, a REPL test for wide scalar globals, destructuring beside a cleanup, and three small heap limits. |
| [Lifetime proof follow-up](lifetime-proof-followup.md) | Results from the shipped selected-root audit and an optional path to model indexed borrows, container values, native handles, and iterator callbacks. |
| [Source organization follow-ups](archive/x2c-source-organization.md#outside-this-plan) | Defects and costs found during the campaign, all fixed: the lambda cell cost, file-init inlining, private-include header types, the region cast false positive, the `try return` warning, the unused open-template paths, nested macro expansion cost, struct-tag method lookup, flaky libuv watch tests, and nondeterministic certify paths. |
| [Consolidation catalog C13](archive/consolidation-catalog-f28fc36.md#c13-larger-lifetime-sharing-locate-overlap-without-pretending-equivalence) | Shared lifetime summary and flow production; design and measurement before any rewrite. |

An entry here preserves remaining work; it does not dispatch it or add a gate.
Production promotion remains separately authorized under the release workflow.

### Decisions and completed records

- [Macro application cost](archive/macro-application-cost.md): done
  2026-10-04; phases 1 and 2 and the undo log in PR #129, phase 3 in
  PR #130, then PRs #132 and #135. Its open defer options stay under
  "Outside this plan".
- [Compiler error catalogue](archive/compiler-error-catalogue.md): done;
  catalogue and callers landed through `c08f1d84` and `bef9923d`, with
  once-only table initialization through `fcfaff40` and `2c8ddfb3`.
  The active post-integration campaign owns its named-macro replacement.
- [Value declarations and reference style](archive/value-reference-style.md):
  done; private contexts landed in PR #76, and public contexts through
  `cbecd92e` and `a373970c`. F14 and F29 track the runtime follow-ups.
- [Batched dev integration](archive/batched-dev-integration.md): done
  2026-10-01 at `0e2c03a93195`; all three delivery modes are live, the shared
  tools work in both native worktree types, and PRs #74, #75, and #76 landed
  with one successful full gate. Explicit review stops remain held.
- [Source organization](archive/x2c-source-organization.md): done
  2026-09-30; one subject per file, one owner per fact, reading order, and
  record ownership across `src/` and `lib/`, with 14 new units and every
  section under 400 lines.
- [Beautification](archive/x2c-beautification.md): done; Waves 0-5
  delivered through 0bccd679. Its deferred file-level work continues in
  [source organization](archive/x2c-source-organization.md).
- [Next compiler/library beautification](archive/compiler-library-beautification-next.md)
  and its [coverage record](archive/compiler-library-review-coverage.md):
  done 2026-09-30 as PR #72.
- [Native meta execution](archive/native-meta-execution.md) and the
  [meta-integration mitigation](archive/meta-integration-mitigation.md):
  done; present on dev.
- [Macro capture-role consolidation](archive/macro-capture-role-consolidation.md):
  done at 0e2f1359.
- [Bug findings](archive/bug-findings-f28fc36.md) and the
  [consolidation catalog](archive/consolidation-catalog-f28fc36.md): audits
  of `f28fc36`; every finding is repaired or decided except catalog C13,
  which is in the backlog.
- [Compiler dual-macro campaign](archive/compiler-dual-macro-contract.md#e45-final-source-family-accounting):
  done 2026-09-29 at `82d686e2`; shared grammar projections cover parsed
  source families. The [architecture reference](archive/compiler-dual-macro-architecture.md)
  records retained stage and backend owners, and the
  [aggregate result](archive/compiler-aggregate-source-forms.md) covers Array,
  Map, and String forms.
- [Raw-symbol macros translation](archive/raw-symbol-macros-translation.md):
  done; both repairs and the optional standalone sweep were verified.
- [Publication gate and local workflow](archive/publication-gate-and-local-workflow.md):
  implemented 2026-09-28; private checkpoints and local feature adoption,
  bounded parallel fixtures, and a smaller final publication gate.

- [Try template migration](archive/dual-macro-try-migration.md): done
  2026-09-27; try lowers through one open Macro value on `dev`.
- [Dual macro core support](archive/dual-macro-core-support.md): done
  2026-09-27; macro values, `macro open`, carriers and effects on `dev`.
- [Native `meta` definitions](archive/meta-native-definitions.md): done
  2026-09-25; definition marker and library migration delivered in
  `c3ac95fd` and `56b75433`.
- [REPL fit, status, and runtime surface](archive/repl-fit-and-runtime-surface.md):
  done 2026-09-25; all eight deliveries reached `dev`, and later REPL work
  belongs in `commands/repl`.
- [Meta sequencing](archive/meta-sequencing.md): done 2026-09-25;
  the optional selected-root lifetime proof completed step 4.
- [External commands](archive/external-commands.md): done 2026-09-24;
  framework, packaging, and `graph`/`repl`/`lint` moves delivered through
  `9b31112e`.
- [Meta authoring and coverage](archive/meta-authoring-and-coverage.md):
  done 2026-09-24; nested results came from the explicit meta campaign and
  nine lifetime-sensitive methods were certified.
- [Meta heap objects](archive/meta-heap-objects.md): obsolete; the explicit
  meta campaign delivered meta heap objects (`d0476fe1`, `a9e9ba5d`).
- [Post-merge stabilization](archive/post-merge-stabilization-2026-09-23.md):
  done; delivered as `9b71607f`. The
  [reproducibility record](archive/generated-lisp-reproducibility.md) is
  resolved by binding-ordered loop parameters (`29326dbd`).
- [Internal adoption campaign](archive/internal-adoption-campaign.md): done
  2026-09-24; phases 1-7 delivered, phase 8 closed by the lifetime
  certification. The 44 native-handle operations stay parked until a caller
  exists.
- [Meta lifetime certification](archive/meta-lifetime-certification.md):
  done 2026-09-24 (`1e8de764` through `263fa39b`); nine methods are
  meta-callable and `Var.token` stays private.
- [Indentation dogfooding](archive/indentation-dogfooding.md): done; the
  script tools use `#pragma indent`, converted by `tools/indent-convert`.
- [Indentation syntax](archive/indentation-syntax.md): done; `.xp`,
  `.xpmacro`, and `#pragma indent` select a tokenizer layout pass.
- [Cleanup lowering](archive/emit-cleanup-lowering.md): done; phase 1
  shipped as `68eea0a`, phases 2 and 3 measured and declined 2026-09-24.
- [Explicit meta calls, lifetimes, and computed values](archive/explicit-meta-and-lifetime-campaign.md):
  done; pieces 0-5 delivered through `49a239ec`.
- [Meta values, types, and native records](archive/meta-values-types.md):
  rejected local implementation; session-owned records and a hardcoded native
  bridge failed the requested storage and lifetime contract.
- [Meta recovery](archive/meta-recovery.md): done; delivered as `db86d4b7`.
- [Symlinked home spellings](archive/symlinked-home-spellings.md): done;
  delivered as `610c52f5`.
- [Meta recovery checkpoints](archive/meta-recovery-checkpoints.md),
  [design](archive/meta-recovery-design.md) and
  [review](archive/meta-recovery-review.md): obsolete; their record wrapper
  and allocation tracker were replaced by native byte storage.
- [September 18 decisions](archive/repository-review-2026-09-18.md#group-10-decided-2026-09-18):
  all nine were decided by Gary, with the original questions and implementation
  outcomes retained. They are not a pending-approval list.
- [September 17 review](archive/repository-review-2026-09-17.md) and
  [September 18 remediation](archive/repository-review-2026-09-18.md): historical
  findings, corrected diagnoses and delivered outcomes.
- [Dogfooding adoption](archive/x2c-dogfooding-remediation.md): bounded campaign
  complete; routine adoption and the linter backlog retain the optional work.
- [Original lowering](archive/x2c-lowers-to-lisp.md),
  [generalization](archive/comptime-x2c-generalization.md) and
  [meta milestones](archive/meta-functions.md): implemented phases, measured
  declines and integration history, superseded as execution plans by current
  meta work.
- [Generated environment](archive/generated-lisp-initial-environment.md),
  [initial algorithms](archive/migrate-initial-lisp-algorithms.md),
  [built-in macros](archive/migrate-builtin-macros.md) and
  [native binding algorithms](archive/migrate-lisp-binding-algorithms.md):
  completed September 20 migrations. Their generated Lisp is not unfinished
  hand-authored migration work.
- [Lowering spike findings](reference/lisp-lowering-spike-findings.md): historical
  design evidence, including the limits of its temporary artifacts.

## Required plan review

Before a plan is presented for approval, end it with a short `## Plan review`
that states:

- which exact facts existing producers or boundaries establish, and whether
  any proposed consumer rechecks those facts;
- what existing code the design deletes or reuses, and why each new helper,
  representation, traversal, cache, or other lasting mechanism is necessary;
- why the resulting source is direct and idiomatic x2c rather than a framework
  imported from another compiler or language; and
- every proposed validator, dedicated diagnostic, and negative fixture, with
  the wrong output, corrupted state, unsafe native crossing, or deliberate
  public behavior it protects. If there are none, say so.

Revise the design before approval when this review finds a duplicated
guarantee or machinery whose only benefit is earlier or more specific failure.
Tests, fixtures, performance work, and green gates may prove a design; they do
not justify keeping the machinery they exercise.

Each planned change also ends implementation with a source review before
the publication proof. That review inspects the completed authored diff for
the same trusted facts, deletion and reuse opportunities, unnecessary
machinery, and idiomatic x2c choices, and fixes what it finds. It is not a new
gate or a report.
