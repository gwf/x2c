---
name: clean-x2c-source
description: >-
  Audit and revise one or more hand-authored x2c source files for consistency
  with the repository coding style while preserving behavior, public
  contracts, representation details, and generated-file boundaries. Use for
  source cleanup, comment compaction, header normalization, readability
  passes, style migrations, comment audits that find and rank narrating,
  repetitive, or misplaced comments, or requests to make files under src/ or
  lib/ conform to agents/x2c-code-standard.md.
---

# Clean x2c source

Make hand-authored source clear and consistent with the
[code standard](../../x2c-code-standard.md), preserving behavior and useful
technical explanations.

## Read the file in context

Read nearest instructions, the complete target source, relevant standard
sections, and the tests, public declarations, and book pages that explain its
behavior. Preserve unrelated edits and generated-file rules. Use the
[philosophy](../../x2c-philosophy.md) when implementation responsibilities are
unclear. Reshaping functions and file order belongs in `beautify-x2c-source`,
and structural redesign in `simplify-x2c-source`, when authorized.

Optional discovery commands, from the repository root:

```sh
make commands
builds/0/x2c lint --all path/to/file.x
```

`x2c-lint` reads the compiler's tokens and parse. Use `x2c lint --rules`
for current codes and kinds; `--all` includes repository style findings,
and `--rule CODE` selects one. Apply LY, ST, EX, CM, and NM from
[the standard](../../x2c-code-standard.md). Review candidates in source.
`--fix` writes only respellings whose generated C and header are identical.

## Audit comments

Apply CM and FI-2 from the standard. Findings start at a comment's first
line. To rank files for a comment audit, count findings per file:

```sh
builds/0/x2c lint --all src/*.x lib/*.x | cut -d: -f1 | sort | uniq -c |
  sort -rn | head
```

For each leading file, read the comment with its code. Apply CM-1 to CM-8,
then confirm CM-5 findings against `docs/AGENTS.md` and the module manifest.
A read-only audit reports source-checked candidates and false positives.

## Revise and review

Apply LY, ST, EX, CM, and NM within the selected scope. Keep tables,
diagrams, grammars, and equations intact when columns carry meaning.
Verify unfamiliar syntax in current source, book pages, or a compiler probe.

Reread the whole file after edits, including the surroundings of changed
hunks. Check that substantive comments and semantic details remain available.
For multiple files, review each in its own context and validate the coherent
batch.

## Validate and deliver

Inspect `git diff --check` and the source diff. Use focused behavior checks
when the edits can affect behavior, then follow root publication validation
and delivery instructions. Refresh affected generated files only through
repository targets and inspect their changes.

`builds/0/x2c lint --fmt-diff path/to/file.x` shows the spacing changes
formatting would make; it never writes.

If changing the linter itself, run `make commands-check`.

The result is clearer source with preserved behavior and technical knowledge.
Report meaningful changes and verification; scanner counts are supporting
evidence only.
