---
name: clean-x2c-source
description: >-
  Audit and revise one or more hand-authored x2c source files for consistency
  with the repository coding style while preserving behavior, public
  contracts, representation details, and generated-file boundaries. Use for
  source cleanup, comment compaction, header normalization, readability
  passes, style migrations, or requests to make files under src/ or lib/
  conform to agents/x2c-coding-style-guide.md.
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
adjacent static output, narration, rulers, and stock prose. The idiom
candidates, `member-arrow`, `contains-in`, `plain-string`, and
`expression-body`, each propose a respelling; `--fix` writes the ones that
leave the file's generated C and header byte-identical. Method-match
bindings read through `assoc` are candidates for source `match`; keep method
matching when bindings escape the local branch.

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
