# Reset agent onboarding for maintenance after launch

> Status: done - implemented and validated, 2026-09-07.
> The commit adding this archived plan delivers the approved guidance and
> tooling changes.

## Result

Teach agents to maintain shipped x2c from current documentation, working
examples, and existing implementations. Routine implementation requests
include validated delivery directly to `main`; requested PRs remain available
for review. Investigation and planning requests remain read-only unless they
also authorize changes.

The change is repository-local. Preserve language semantics, compatibility,
technical references, existing validation targets, skill names, shared skill
discovery, personal settings, and stored memories.

## Implementation

1. Rewrite the root onboarding around finding relevant source, making a
   coherent idiomatic change, verifying the result, and delivering it. Keep
   `agents/README.md` as the skill catalog and route other entry points there.
   Introduce the book's idioms, manifest-backed examples, and current source
   exemplars before deeper references. Shorten nested guidance to its local
   facts, retaining generated-file rules, representations, lifetimes, tests,
   package acceptance criteria, and compatibility requirements.
2. Review all eleven skills and their UI prompts. Retain distinct tasks and
   useful technical instructions while removing repeated workflow and
   historical reprimands. Routine implementation may resolve missing plan
   details and complete a design review. Consequential unresolved choices
   still need a decision. Keep cleanup scanners optional, remove per-comment
   inventories, and choose regression coverage by behavior rather than a
   fixed test count. Agent-process work follows the requested deliverable,
   including strategic reviews. Incident capture stays user-invoked.
3. Make durable plans concise and decision-complete, with a design review and
   final authored-diff review. Retain detailed technical references and the
   philosophy's inventory and checks; repair stale exemplars and remove
   duplicated workflow instructions from revised entry points.
4. Remove the Claude reply-length hook, its dedicated test, and its unused
   transcript reader. Retain retrospective measurement helpers. Correct
   incident capture's existing-workspace diff and shared-clone history to use
   `origin/main`; preserve historical records.
5. Document explicit push destinations. Routine direct delivery uses
   `git push origin HEAD:refs/heads/main`. Requested PRs push to the same-named
   workspace branch with `main` as the base. Fetch and integrate current main,
   review, and validate before publication. A rejected non-fast-forward push
   requires reintegration and validation again; never force-push main.
6. Review and fix the completed authored diff for unnecessary machinery,
   repeated guidance, lost technical facts, and broken references before
   publication validation. Deliver one coherent change directly to main.

## Validation

- Check Markdown links, referenced examples and symbols, skill metadata,
  instruction and skill symlinks, and remaining Claude configuration.
- Run focused harness tests, including actual temporary Git repositories for
  existing-workspace comparison and missing-workspace shared-clone history.
- Use fresh isolated planning sessions for routine fixes, requested PRs,
  read-only investigation, unresolved semantic choices, and ordinary tasks
  that must not select incident capture. Keep prompts free of expected answers.
- Confirm the repository no longer installs a reply-length hook. Compare
  entry-point and skill text before and after without an arbitrary size quota.
- Run `tools/gate-state.py ensure agent-pr-check` on the final tree because
  tooling changes are included. Review any generated changes and verify remote
  publication. Add no recurring gate or test requirement.

Baseline: root `AGENTS.md` had 377 lines and 3,215 words. Root and nested
instructions plus the eleven skill entry points went from 18,764 to about
9,700 whitespace-delimited words, preserving the technical references.

Six focused harness tests pass, including both main-based Git scenarios.
Documentation, skill metadata, local links, and shared discovery checks pass.
Six fresh isolated Claude sessions exercised direct delivery, a requested PR,
read-only investigation, an unresolved semantic choice, explicit execution,
and a detailed explanation. These establish the tested planning behavior,
not long-session reliability. No repository reply-length hook remains.
The existing full publication check passed without generated-artifact changes;
publication requires it to remain valid for the final recorded tree.
Workspace-local `.context/` and `debug/` retain detailed evidence.

## Plan review

Existing source, examples, the book, shared skill links, and validation
commands supply the knowledge and execution paths this design needs. The
change removes duplicated instructions, unnecessary stops, and a length-based
hook rather than adding another enforcement mechanism.

The detailed technical inventory remains available, preserving x2c-specific
facts while shortening onboarding. The only new regression coverage verifies
incident capture against main. There is no new validator, diagnostic, language
mechanism, public API, or recurring process.
