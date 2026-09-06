# AGENTS - Compiler (`src/`)

Read the root `AGENTS.md` first. Open only the section of
`agents/x2c-philosophy.md` relevant to the work. Compiler-specific notes:

- Use focused self-host checks during development when they answer a live
  question. For publication, use the root rule; do not add a separate broad
  gate.
- The fixed-point transform driver relies on the verified List canonicalization
  contract: Lists created through `cons` have stable structural identity. Keep
  identity-dependent compiler behavior inside that canonical boundary.
- The compiler is meant to be a showcase of idiomatic x2c: prefer
  `match`/`match_replace` templates when they express a rewrite directly.
  Before changing parser productions, AST consumers, or transforms, read
  `agents/replacing-manual-ast-walks-with-match.md`; it owns the rules for
  recursive descent, structural captures, output templates, and transform
  recursion.
  After a green stress test, use `make stage-diff-all` to compare
  self-hosted stages. Run `stage-diff-0` when the task includes a generated bootstrap
  refresh.
