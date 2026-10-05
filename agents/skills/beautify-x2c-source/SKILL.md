---
name: beautify-x2c-source
description: >-
  Rewrite one hand-authored x2c source file to the Shape standard in
  agents/x2c-code-standard.md while keeping its behavior, algorithms,
  and data structures: split long functions into named steps, make each
  dispatch action one line, group shared context into records, call existing
  owners instead of repeating their work, give incidental work one place,
  rename with the glossary, and put the file in reading order. Use for any
  request to make a src/ or lib/ file readable at the function and file
  level. Use clean-x2c-source for comment and spelling cleanup alone, and
  simplify-x2c-source for removing machinery across files.
---

# Beautify x2c source

Rewrite one file so a reader can follow it from top to bottom. Behavior,
algorithms, and data structures stay the same. A small tweak is allowed when
it is neutral or better and makes the code easier to read. The standard is
[the code standard](../../x2c-code-standard.md), especially FN, FA, FI,
and NM.
The [source organization plan](../../../plans/archive/x2c-source-organization.md)
records the last campaign, its rules, and its measurements.

## Settle the file boundary first

List the file's subjects and apply FI-1 and MO-3 in
[the standard](../../x2c-code-standard.md). Settle the boundary before
function work.

## Outline before editing

Read the whole file, its tests, its callers, and the existing owners it
could call. Write an outline in the session notes: the file's subject in one
sentence, its sections in reading order, and one line per function. A
function whose line needs "and" gets split. Measure the file:

```sh
builds/0/x2c lint --all path/to/file.x
```

The `long-function`, `deep-nesting`, `long-parameter-list`, and `long-name`
candidates mark functions outside the bands. When the wave has a coverage
report from the [coverage probe](references/coverage-probe.md), read the
file's never-executed functions and lines.

## Rewrite

Work in this order:

1. Apply PR-3 and FI-7. Confirm deletion candidates from callers and
   producers; coverage remains discovery evidence.
2. Apply FA-5 to FA-8 and PR-2 to repeated work and existing owners.
3. Apply FN-1 to FN-6, FA-2, and FA-3 to function and record shape.
4. Apply LT-1 to acquisitions and paired state; follow HP-1 and HP-2
   when the affected work is on a measured hot path.
5. Apply NM and the standard's role-name glossary.
6. Apply FI-4 and FI-5 to the outline and reading order.
7. Apply CM with [clean-x2c-source](../clean-x2c-source/SKILL.md).

Preserve the PR-10 compatibility boundary. Apply MO-4 to a large move and
PR-4 to any proposed validator, diagnostic, or negative fixture.

## Verify

Verify the coherent change once, including a worker batch of related files.
Run `make build`, then the fixtures and unit suites that exercise the changed
behavior:

```sh
unittest/compiler-fixtures/run.sh check --fixture NAME
make -C unittest test-all && (cd unittest && ./test-all NAME_suite)
make stage-1 && make stage-diff-1
```

Stage 1 uses the edited compiler to translate the same source as stage 0.
`make stage-1 && make stage-diff-1` proves the compiler's output is
unchanged. `make stage-diff-0` against a current bootstrap proves a
respelling's own generated C is unchanged. Follow the standard's proof
obligations; never rebaseline a difference to make a rewrite pass. A hot
path also follows [performance checkpoints](../../performance-checkpoints.md).

## Report

Report the file's subjects and any boundary split, `.x` lines deleted and
added, then the shape measures before and after: sections over 400 lines, functions over 40 lines, the deepest brace depth, the largest
parameter count, and the longest name. Name each neutral algorithm tweak and
its reason. Delivery follows the root [AGENTS.md](../../../AGENTS.md); in
a campaign, the orchestrator collects workers' handoffs and either publishes
each batch or submits it to the shared integrator, as Gary selected.
