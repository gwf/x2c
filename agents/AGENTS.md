# AGENTS - Agent documentation (`agents/`)

> Scope: applies to files under `agents/` only.

Read the root `AGENTS.md` first. Open only the section of
`agents/x2c-philosophy.md` relevant to the work. Notes specific to this tree:

- `agents/` documents **how work is done in this repo**: contracts, build lore,
  style, debugging, and the generated internals inventory. The user-facing book
  in `docs/` documents **what the language and library are**. When a page here
  needs language semantics, link into `docs/`; never restate them, because a
  second copy is a second thing to drift.
- Evidence first: verify every claim (file names, APIs, flags, commands)
  against the current tree before writing it, citing `file:line` where
  practical. A stale reference is worse than no reference.
- Complete code samples must compile with `builds/0/x2c` after `make build`.
  A guide may state once that its fragments are illustrative rather than label
  each one. `bin/x2c` is the bootstrap compiler unless stage 0 has
  intentionally been installed.
- Prefer fixing or deleting a drifted doc over adding a parallel one.
- `logger-and-diagnostics-guide.md` is the sole owner of Logger and compiler
  diagnostics contracts; do not create parallel quick or technical guides.
- `x2c-module-catalog.md` is generated. Run `make doc-generate`; never hand-edit it.
- Skills are authored in `agents/skills/`. `.agents/skills` and
  `.claude/skills` expose that directory to Codex and Claude Code.
