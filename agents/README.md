# Working on x2c

Start with the requested behavior, a current implementation, and its tests.
The [root guidance](../AGENTS.md) covers authorization, validation, and
delivery. This page routes tasks to skills and deeper references.

## Learn from working code

- [Programming idioms](../docs/src/guide/idioms.md) explains how to choose
  values, collections, protocols, macros, and cleanup.
- [The language tour](../examples/tours/language.x) shows the language in an
  executable program. `examples/manifest.txt` records each example's role,
  check, and expected output; use it to find a relevant smaller example.
- [The implementation map](../docs/src/internals/implementation-map.md)
  connects features to compiler and runtime modules. Read a nearby operation
  and its tests before introducing another implementation.
- [Implementation exemplars](x2c-philosophy.md#exemplars) identifies the
  specific property to learn from each referenced module.

The book under `docs/` owns language and library semantics. This directory
explains how to work on their implementation; link to the book when semantics
are needed rather than maintaining another copy.

## Select the task skill

- [plan-x2c-change](skills/plan-x2c-change/SKILL.md) - answer a question about
  current behavior, or decide a design before implementation.
- [execute-x2c-plan](skills/execute-x2c-plan/SKILL.md) - implement, verify, and
  deliver an already-decided change.
- [fix-x2c-bug](skills/fix-x2c-bug/SKILL.md) - reproduce a defect, repair its
  cause, and verify the observable behavior.
- [integrate-x2c-package](skills/integrate-x2c-package/SKILL.md) - integrate a
  C library or judge whether its x2c package is complete.
- [review-x2c-repo](skills/review-x2c-repo/SKILL.md) - investigate the requested
  repository area and report reproduced findings; edit only when authorized.
- [simplify-x2c-source](skills/simplify-x2c-source/SKILL.md) - remove connected
  architectural redundancy while preserving behavior.
- [clean-x2c-source](skills/clean-x2c-source/SKILL.md) - improve local source
  style after structural choices are settled.
- [find-comment-slop](skills/find-comment-slop/SKILL.md) - discover and rank
  comment cleanup candidates without editing.
- [find-redundant-validation](skills/find-redundant-validation/SKILL.md) -
  discover and rank redundant checks without editing.
- [improve-x2c-agent-process](skills/improve-x2c-agent-process/SKILL.md) -
  review or improve agent guidance and tooling for the requested workflow.
- [agent-failure](skills/agent-failure/SKILL.md) - capture a failure Gary
  explicitly asks to record. It is never selected for ordinary work.

Skills have one canonical copy in `agents/skills/`, exposed through
`.agents/skills` and `.claude/skills`. Authoring guidance is in
[agents/AGENTS.md](AGENTS.md).

## Open references when relevant

- [Quick start](quick-start.md) - setup, commands, and repository orientation.
- [Philosophy](x2c-philosophy.md) - design principles, implementation facts,
  and the evidence supporting them; read the section relevant to the task.
- [Source style](x2c-coding-style-guide.md) and
  [code organization](x2c-code-organization-guide.md) - how code reads and
  where it belongs.
- [Development reference](x2c-development-guide.md) and
  [debugging](x2c-debugging-guide.md) - build details and compiler instruments.
- [AST patterns](replacing-manual-ast-walks-with-match.md) - shared canonical
  syntax, Match, templates, and ordinary compiler operations.
- [Source graph](../tools/x2c-graph/README.md#investigate-a-change) - optional
  commands for callers, allocation returns, repeated walks, and source paths;
  verify findings in source before changing behavior.
- [Adapters, macros, and decorators](adapters-macros-decorators.md) - when
  generation and shared implementations make source clearer.
- [Logger and diagnostics](logger-and-diagnostics-guide.md) - delivery,
  presentation, and lifetime rules.
- [Module catalog](x2c-module-catalog.md) - generated source inventory;
  regenerate it with `make doc-generate`.
- [Documentation checks](x2c-docs-drift-report.md) - what current checks cover
  and what remains unaudited.
