---
name: beautify-x2c-source
description: >-
  Rewrite one hand-authored x2c source file to the Shape standard in
  agents/x2c-coding-style-guide.md while keeping its behavior, algorithms,
  and data structures: split long functions into named steps, make each
  dispatch arm one line, group shared context into records, call existing
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
the [Shape chapter](../../x2c-coding-style-guide.md#shape), the
[reading order](../../x2c-coding-style-guide.md#reading-order), and the
naming glossary under
[Names expose ownership](../../x2c-coding-style-guide.md#names-expose-ownership).
The [source organization plan](../../../plans/archive/x2c-source-organization.md)
records the last campaign, its rules, and its measurements.

## Settle the file boundary first

List the file's subjects. For a file over 1,500 lines, or one whose subject
needs "and", apply "Large files" in the
[organization guide](../../x2c-code-organization-guide.md): count the
private helpers each candidate boundary would cross in each direction, and
split only a part with its own owner, a one-way dependency, and its own
tests. Function work comes after the boundary is settled.

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

1. Delete uncalled functions, unreachable arms, and checks of facts a
   producer established. Confirm each by reading callers and producers; a
   zero count in the coverage report is a candidate, not proof.
2. Replace repeated work with calls to its existing owner. Give a stanza of
   three or more lines that repeats three or more times one helper, macro,
   or table.
3. Split functions. Dispatcher arms become one-line calls to named helpers,
   phases become named steps, flags become separate functions or early
   returns, and a group of parameters passed through several helpers
   becomes a record whose methods are the steps. A record copied into
   locals on entry is a parameter list; pass the parameters instead.
4. Replace hand-expanded idioms with system macros: `$let` for save and
   restore, `$scope(&owner)` for a pushed destination, and `$auto` for an
   owned local.
5. Rename with the glossary. A helper name is two or three words and omits
   the file's subject.
6. Reorder the file into the outline. Open each section with a lower-case
   label and, when the concept needs it, up to three sentences.
7. Run the comment pass from [clean-x2c-source](../clean-x2c-source/SKILL.md).

Keep public runtime names and signatures unless Gary approves a change.
Compiler methods are provisional API; a rename updates their callers in
`commands/` too. Add no validators, diagnostics, or negative fixtures. On a
measured hot path, add no `defer`, `$scope`, `$let`, or `$auto` to a helper
without a paired measurement. When a move is large, commit the move and the
change separately so review sees the change.

## Verify

Run `make build`, then the compiler fixtures and unit suites that exercise
the file:

```sh
unittest/compiler-fixtures/run.sh check --fixture NAME
make -C unittest test-all && (cd unittest && ./test-all NAME_suite)
```

Then, once per file:

```sh
make stage-1 && make stage-diff-1
```

Stage 0 is the bootstrap compiler's translation of the edited source, and
stage 1 is the edited compiler's translation of the same source. Byte
equality shows that the rewrite left the generated C unchanged for all of
`src/` and `lib/`. A difference is a behavior change to find and fix; never
rebaseline it. A batch that touches a hot path also needs the
[performance checkpoint](../../performance-checkpoints.md).

## Report

Report the file's subjects and any boundary split, `.x` lines deleted and
added, then the shape measures before and after: sections over 400 lines, functions over 40 lines, the deepest brace depth, the largest
parameter count, and the longest name. Name each neutral algorithm tweak and
its reason. Publication follows the root [AGENTS.md](../../../AGENTS.md); in
a campaign, the orchestrator integrates and gates each batch once.
