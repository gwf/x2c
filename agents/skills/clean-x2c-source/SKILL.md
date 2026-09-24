---
name: clean-x2c-source
description: >-
  Audit and revise one or more hand-authored x2c source files for consistency
  with the repository coding style while preserving behavior, public
  contracts, representation details, and generated-file boundaries. Use for
  source cleanup, comment compaction, header normalization, readability
  passes, style migrations, comment audits that find and rank narrating,
  repetitive, or misplaced comments, or requests to make files under src/ or
  lib/ conform to agents/x2c-coding-style-guide.md.
---

# Clean x2c source

Make hand-authored source clear and consistent with the
[style guide](../../x2c-coding-style-guide.md), preserving behavior and useful
technical explanations.

## Read the file in context

Read nearest instructions, the complete target source, relevant style-guide
sections, and the tests, public declarations, and book pages that explain its
behavior. Preserve unrelated edits and generated-file rules. Use the
[philosophy](../../x2c-philosophy.md) when implementation responsibilities are
unclear. Structural redesign belongs in `simplify-x2c-source` when authorized.

Optional discovery commands, from the repository root:

```sh
make commands
builds/0/x2c lint --all path/to/file.x
python3 agents/skills/find-redundant-validation/scripts/redundant_validation.py \
  --static-match-captures --details path/to/file.x
```

`x2c-lint` reads the compiler's tokens and its parse of the unit; `--rules`
lists each rule's code, family, kind, and style-guide section. Language rules
run by default; `--all` adds the repository style rules, and `--rule CODE`
selects one. Violations include whitespace, width, forward declarations,
reliable wrapping errors, immediate declaration/assignment pairs,
one-statement braces, negated `is` tests, and receiver methods where renaming
the subject parameter to the first letter of its type would save wrapped
lines. Candidates need source review: width exceptions, runtime
declarations, horizontal compaction, short control flow, repeated accessors,
adjacent static output, narration, rulers, stock prose, and pointer
parameters that could be `&` reference parameters. The idiom
candidates, `member-arrow`, `contains-in`, `plain-string`, and
`expression-body`, each propose a respelling; `--fix` writes the ones that
leave the file's generated C and header byte-identical. The comment rules
are described below. Method-match
bindings read through `assoc` are candidates for source `match`; keep method
matching when bindings escape the local branch.

## Audit comments

The comment rules report at a comment's first line. Violations are history
and unfinished-work notes, narrated null guards, decorative or all-capitals
labels, prose that restates the next function's name or the next statement,
`/**` boilerplate, a `/**` on a `static` helper, detached or stacked `/**`
comments, and `/**` in a library module that `docs/library-manifest.txt`
marks contract or internal. Candidates are catalog-style labels, module
headers that inventory the implementation, repeated paragraphs, and stock
prose. To rank files for a comment audit, count the findings per file:

```sh
builds/0/x2c lint --all src/*.x lib/*.x | cut -d: -f1 | sort | uniq -c |
  sort -rn | head
```

For each leading file, read the flagged comment with the code below it and
ask what fact would be lost if the comment disappeared. Remove prose that
only repeats the adjacent code. Keep a comment that gives a non-obvious
reason, invariant, lifetime, compatibility restriction, or the measured
reason a shorter design was rejected, compacting it without dropping the
fact. Treat missing or misleading documentation separately; a bloated
comment does not excuse a missing public summary. Confirm `/**` findings
against `docs/AGENTS.md`: public callables in `src/` and generated-reference
modules keep an adjacent `/**` with a standalone first sentence. A
read-only audit reports source-checked candidates and false positives and
edits nothing.

## Revise and review

Retain facts that are not apparent from code: lifetime, representation,
ordering, grammar, compatibility, failure behavior, and reasons a shorter
implementation would be wrong. Keep tables, diagrams, grammars, equations,
and aligned examples intact when their spacing carries meaning; verify
significant columns if changing their layout.

Keep module headers about shared behavior, place local details beside their
implementation, and remove repeated narration. Normalize names, prologues,
spacing, and control flow using the style guide. Use the available 79 columns,
group declarations when appropriate, prefer `value is not Type`, and simplify
side-effect-free temporaries or converters only when their semantics agree.
Verify unfamiliar syntax in current source, documentation, or a compiler probe.

Reread the whole file after edits, including the surroundings of changed
hunks. Check that substantive comments and semantic details remain available.
For multiple files, review each in its own context and validate the coherent
batch.

## Validate and deliver

Inspect `git diff --check` and the source diff. Use focused behavior checks
when the edits can affect behavior, then follow root publication validation
and delivery instructions. Refresh affected generated files only through
repository targets and inspect their changes.

If changing the linter itself, run `make commands-check`.

The result is clearer source with preserved behavior and technical knowledge.
Report meaningful changes and verification; scanner counts are supporting
evidence only.
