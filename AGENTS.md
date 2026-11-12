# Repository Guidelines

x2c is a shipped, self-hosting superset of C developed on `dev`.
`main` is release-only and advances deliberately during publication. The
compiler (`src/`) and runtime (`lib/`) are working examples of the language.
Make each requested change useful, idiomatic, and verified, moving the
repository from one healthy state to the next.

Treat the user's architecture and established boundary contracts as premises.
Uncertainty calls for inspecting the owning contract, not adding compensating
machinery or new caller obligations. A concrete conflict must be surfaced
before changing that architecture. This rule takes precedence over generic
robustness, verification, and completion guidance in repository instructions.

## Start with the task

Read the nearest `AGENTS.md`, any plan or specification the user named, and
the source and tests that implement the behavior. Use
[agents/README.md](agents/README.md) to select the smallest matching skill
and relevant references; it is the task directory for this repository.

@agents/README.md

Begin with a working example of the same kind of code. The
[idioms chapter](docs/src/guide/idioms.md) explains language choices;
`examples/manifest.txt` identifies executable examples and their checks.
Current source and tests establish implementation behavior. The book under
`docs/` owns language and library semantics; agent guidance links to it.

An implementation request authorizes routine implementation decisions,
verification, and delivery as described below. A request for investigation,
review, advice, or a plan is read-only unless it also authorizes changes.
Resolve consequential choices with Gary when the request leaves them open,
especially changes to public semantics, compatibility, or caller obligations.
Complete routine missing plan details and its design review within an
already authorized implementation; a missing heading is not a reason to stop.
Follow Gary's explicit direction using the smallest proportionate action.
Repository process is a default, not an excuse to enlarge, delay, or redirect
the task; deviate only for a concrete safety or correctness risk, and state
that risk plainly.
Do not materially enlarge the requirement a change serves. If a repair would
roughly double its code, concepts, validation, or cost, choose a simpler
boundary or ask Gary before implementing it.

When Gary says current work looks wrong, slow, wasteful, or off-scope, stop
that work and verify the specific concern against a known baseline before
offering reassurance or continuing.

Use subagents for independent discovery or bounded work. A session that
launches implementation subagents is their orchestrator: load
`orchestrate-x2c-work` first. Its workers never merge `dev`, gate, or push;
the orchestrator collects their private handoffs and owns the session's
delivery choice below. Verify a reported finding against current source and
reproduce claimed behavior before acting on it or presenting it as established.

## Write x2c that belongs here

Prefer composing current language features and existing operations. Follow a
connected simplification across files when it serves the requested behavior.
Beautiful x2c is brief, direct, and easy to reason about; measurements and
passing tests support that result rather than replace it.

- Match and literal templates express AST structure. Reuse ordinary compiler
  operations for binding, typing, scope, lifecycle, placement, diagnostics,
  and emission order. The [Match guide](agents/replacing-manual-ast-walks-with-match.md)
  owns the procedure for compiler syntax work.
- Compile-time code may construct any canonical AST List. Ordinary operations
  accept forms by structure and position, without authenticating their origin.
  Preserve this deliberate behavior described under "Macro-visible syntax"
  in `docs/src/reference/language.md`; do not add origin tracking or a second
  validator to reject legal constructed syntax.
- Free names in a macro body resolve where the expansion lands, as in C.
  A macro keeps a file-scope declaration only for a name it lists with
  `using name`; `using $name` creates a fresh private name. Do not make
  definition-site binding a default. See "Keeping a file-scope name with
  `using`" in `docs/src/reference/language.md`.
- Apply [PR-4](agents/x2c-code-standard.md#principles) to established facts,
  checks, diagnostics, and fixtures. Preserve guarantees at their owning
  boundary instead of reconstructing them downstream.
- Follow `agents/x2c-code-standard.md`, the single definition of x2c source
  style, including ER-4 and ER-5 for shared Error causes and PR-6 for
  representations; `agents/x2c-philosophy.md` holds their facts. Update the
  book when documented behavior changes.
- The compiler emits calls into the runtime and the bootstrap compiles against
  it, so public runtime signatures are effectively ABI. Preserve them unless
  the task authorizes a compatibility change.

Review a design before implementation and the completed authored diff before
publication validation. Look for existing code to reuse or delete, checks
that repeat established facts, and new machinery that does not earn its keep.
Fix what the review finds. Durable plans follow `plans/README.md`.

## Work in the repository

Preserve unrelated work and inspect tracked and untracked changes before
committing. Edit authoritative sources; use documented targets to regenerate
`bootstrap/`, `lib/x2c.x`, and generated documentation.
Never hand-edit bootstrap C/H. Keep temporary outputs in `/tmp` or
`unittest/build/`, workspace notes in `.context/`, and full failure logs in
`debug/`. Keep new files ASCII and shipped code free of debug scaffolding.
Direct destructive operations outside the requested change need approval.

Private worktree commits are checkpoints and may be made whenever useful,
including incomplete experiments and intermediate bootstrap states. A local
commit alone requires no build, test, gate, performance checkpoint, generated
refresh, or separate bootstrap commit. Keep the working compiler and bootstrap
usable for the next development step: refresh bootstrap before adopting a
capability the seed cannot consume. Feature introduction, local rebootstrap,
and adoption may share one branch and one publication batch. Individual local
commits need not rebuild from their own bootstrap.

## Repo Map

See [source ownership](src/README.md) and the
[repository map](agents/quick-start.md#repository-map).

## Verify and deliver

Use `agents/quick-start.md` for setup, focused commands, and optional checks.
Reproduce a reported defect before editing and verify the user-visible result
with focused tests or executable examples. Unit suites and compiler fixtures
follow `unittest/AGENTS.md`; ordinary checks preserve checked-in expectations.
The integrator runs broad checks once on the completed batch.

Fresh worktrees, or worktrees that have integrated changed `bootstrap/`, need
`mkdir -p debug && make build-safe >debug/bootstrap.log 2>&1` before using
`builds/0`. During implementation, build or probe when it answers a current
question. The local bootstrap-transition policy is under
[Work in the repository](#work-in-the-repository).

Published tips on shared upstream branches must rebuild from their shipped
bootstrap. The integrator validates the completed integrated tree before
publishing; work branches use focused submission checks.

### Select integration ownership

Follow intended design succession, not merge order. A change that supersedes
an earlier design governs its scope, even if its branch predates intervening
fixes on `dev`. Reassess those fixes and tests against the replacement design;
preserve unaffected requirements, not obsolete assumptions. Never infer
precedence from merge status or timestamps alone.

Shared-integrator submission is the default delivery mode:

- With explicit direct delivery, an individual session integrates, gates, and
  publishes its work to `dev`.
- With explicit direct delivery, an orchestrator collects private handoffs,
  integrates, gates once per coherent batch, and publishes to `dev`.
- An individual session or orchestrator normally submits ready PRs targeting
  `dev`. The standing `integrate-x2c-prs` session batches, reviews, gates, and
  publishes them. Either individual sessions or orchestrators may submit.

Direct delivery requires Gary's explicit instruction. Pass the selected delivery to delegated workers.
Local-only work and a requested review stop still take precedence. An absent
integrator leaves submissions waiting.

When selecting or switching modes, establish the worktree's role and delivery
with `tools/integrate-dev.py context --role <role> --delivery <delivery>`.
Roles are `individual`, `orchestrator`, `integrator`, and subordinate `worker`;
delivery choices are `direct`, `pr`, and `private`. Subordinate workers always
use `worker`/`private` and give their changes to their orchestrator. Context
setup verifies the common Git push hook; stop on a conflicting hook setup
rather than silently replacing it. These tools and canonical skills work for
both providers; provider-specific session or messaging APIs are unnecessary.

For shared-integrator delivery, run meaningful focused checks.
Then push a work branch and submit its non-draft PR through
`tools/integrate-dev.py submit`. Record the starting revision, exact head,
dependencies, local-rebootstrap evidence when applicable, and focused
evidence as described in
[quick start](agents/quick-start.md#submit-to-the-shared-integrator).
The coordinator enrolls it with `integration-ready`; merely creating a PR
does not enroll it. Readiness requests integration of that pinned revision.
Withdrawals take effect when observed before push, rather than transactionally
across GitHub and Git.

The integrator owns final generated artifacts, performance work, and the
publication gate once per combined batch. Report a PR as submitted, not
published. For a requested review stop, use `individual`/`pr` or
`orchestrator`/`pr` context, push only a draft PR branch, and leave it
unenrolled until review is complete.

### Validate publication

The integration owner follows
[publication validation](agents/skills/integrate-x2c-prs/SKILL.md#validate-publication)
for both shared integration and explicit direct delivery. PR submissions use
focused evidence; the integrator runs the final gate.

### Process ceiling

Preserve the existing validation targets. `precommit` is Gary's readiness
sequence, not a Git commit prerequisite; changes to it must make it faster or
simpler, or be necessary for build correctness. `sanity-check` remains bootstrap refresh, safe rebuild,
and builds through stage 3, without added checks. `agent-pr-check` consolidates
existing publication checks; additions require removing or consolidating an
existing requirement of comparable cost.

Gary's explicit approval is required before adding, expanding, or reordering
process that increases build or precommit time, or adding any recurring gate,
test requirement, planning step, or commit step. Proposals must identify
existing work of comparable cost to remove or consolidate. Keep optional
checks optional.

## Report delivery state

Follow Clear communication in the maintainer's personal agent settings (not in
this repository) for conversational style. Check worktree and remote state
before saying a workspace is safe to delete. Identify repository requirements
by their current file and distinguish recommendations from requirements.
Supporting evidence can live in the plan, PR, or `.context/`.
