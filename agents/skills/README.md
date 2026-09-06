# agents/skills/

Project skills for x2c. `.agents/skills` and `.claude/skills` are symlinks to
this directory, so Codex and Claude Code discover one canonical copy. Add a
skill as `agents/skills/<name>/SKILL.md`.

A skill belongs here when it encodes a repeatable x2c-specific workflow — the
kind of thing that would otherwise be re-derived from `agents/` prose every
session. Skills should link into `agents/` for the reasoning behind a rule and
into `docs/` for language semantics, rather than restating either.

Current skills:

- `plan-x2c-change` - decide one PR-sized design, proved by a probe.
- `execute-x2c-plan` - implement and publish one decided change.
- `fix-x2c-bug` - reproduce a defect, fix it small, pin it with one test.
- `integrate-x2c-package` - C library integration and package completeness.
- `review-x2c-repo` - survey defects and drift and report reproduced findings;
  fix them only when the user authorized changes.
- `simplify-x2c-source` - broad connected deletion campaigns.
- `clean-x2c-source` - style-focused cleanup after structure is settled.
- `find-comment-slop` - read-only discovery of comment cleanup candidates.
- `find-redundant-validation` - read-only discovery of redundant checks and
  diagnostic-only validators.
- `improve-x2c-agent-process` - evidence-based harness improvement in a
  dedicated review.
- `agent-failure` - record a reported failure in agent communication,
  compliance, or diligence, with evidence captured from the session it
  happened in. Gary invokes this himself; never select it.
