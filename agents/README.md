# agents/

Documentation written for coding agents working on this repository, plus the
project skills in `agents/skills/`. The rules for editing this tree are in
`agents/AGENTS.md`.

This tree covers **how work is done here**. The `docs/` book covers **what the
language and library are**; link into it rather than restating semantics.

## Start with the task

Read the nearest `AGENTS.md`, the source and tests that own the requested
behavior, and any plan or specification the user named. Project skills then
route the work without requiring the whole documentation tree:

- `plan-x2c-change` - decide one PR-sized design, proved by a probe.
- `execute-x2c-plan` - implement and publish one decided change.
- `fix-x2c-bug` - reproduce a defect, fix it small, pin it with one test.
- `integrate-x2c-package` - bring a C library to an ordinary x2c surface, or
  judge whether a package is complete.
- `review-x2c-repo` - survey defects and drift and report reproduced findings;
  fix them only when the user authorized changes.
- `simplify-x2c-source` - connected architectural deletion campaigns.
- `clean-x2c-source` - local cleanup after structural choices are settled.
- `find-comment-slop` - read-only discovery of comment cleanup candidates.
- `find-redundant-validation` - read-only discovery of redundant checks and
  diagnostic-only validators.
- `improve-x2c-agent-process` - dedicated reviews of the agent harness.

`agent-failure` is also in `agents/skills/`, but Gary invokes it himself to
record a failure he saw. Never select it; `plans/agent-failures.md` is the
index it appends to.

Open `x2c-philosophy.md` only at the section relevant to the behavior being
changed. Use `quick-start.md` for build commands and the module map,
`x2c-development-guide.md` for less common compiler and build facts,
`x2c-coding-style-guide.md` for mechanical style, and
`x2c-code-organization-guide.md` when deciding where code belongs.

## Reference

- `replacing-manual-ast-walks-with-match.md` - how the parser, macros,
  compile-time Lisp, Match, transforms, and backend share canonical ASTs;
  structural patterns and templates feed ordinary semantic operations.
- `x2c-debugging-guide.md` - dumping phases and isolating miscompiles.
- `adapters-macros-decorators.md` - living guidance for choosing and
  evaluating adapters, macros, decorators, Maps, and generated ledgers.
- `logger-and-diagnostics-guide.md` - the sole owner of Logger and compiler
  diagnostics contracts.
- `x2c-module-catalog.md` - generated inventory of `src/` and `lib/` modules
  and their non-static functions. Regenerate with `make doc-generate`; never hand-edit.
- `x2c-docs-drift-report.md` - documentation families that remain unaudited.
  Historical workflow restrictions there do not override the root
  `AGENTS.md`.

## Skills

Skills are in `agents/skills/`. Codex discovers the same directory through
`.agents/skills`, and Claude Code through `.claude/skills`.
