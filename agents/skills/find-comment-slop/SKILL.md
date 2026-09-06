---
name: find-comment-slop
description: >-
  Find and rank bloated, repetitive, narrating, misplaced, or mechanically
  invalid comments in hand-authored src/*.x and lib/*.x files. Use for
  comment-cleanup audits or for choosing files that need manual review. This
  skill discovers candidates; it never rewrites source automatically.
---

# Find Comment Slop

Run the candidate finder from the repository root, then read the flagged
comments with their adjacent code. Do not turn its columns into a score and do
not add the two line counts together.

## Run both rankings

```sh
python3 agents/skills/find-comment-slop/scripts/comment_slop.py \
  --rank violations --details src lib
python3 agents/skills/find-comment-slop/scripts/comment_slop.py \
  --rank bloat --details src lib
```

The violation ranking counts comments that match a direct rule in
`agents/x2c-coding-style-guide.md`: narration of a function or statement,
decorated or all-capitals labels, source history, `/**` in the wrong place,
and stacked or detached generated documentation.

The bloat ranking is deliberately a review queue, not a verdict. It counts
repeated paragraphs, vague prose, and module headers that look like
implementation inventories. Public documentation is never flagged merely for
crossing a word or line threshold; length without a concrete defect taught
agents to delete useful explanations.

`violation-lines` and `review-lines` estimate the amount of comment text to
inspect. `violations` and `reviews` count distinct comments. `comments` is the
file's total comment-line count. Rank by the requested column, not by comment
density or file size.

## Judge each candidate

For each leading file, inspect the candidate and the definition or statement
immediately below it. Ask: if this comment disappeared, what fact could not be
recovered from the code?

- Delete prose that only says what the function, branch, or statement does.
- Shorten a public doc comment to its observable behavior: mutation,
  ownership, sentinel meaning, failure behavior, or a surprising cost.
- Keep a comment that explains a non-obvious reason, invariant, lifetime,
  compatibility restriction, or consequence.
- Keep the exact measured reason a tempting shorter abstraction was rejected,
  especially identity or hot-path behavior; compact the prose without deleting
  the fact.
- Treat missing or misleading documentation separately. More documentation
  does not offset a bloated comment, and a bloated comment does not excuse a
  missing public summary.

Confirm `/**` findings against `docs/AGENTS.md` and
`docs/library-manifest.txt`. Public callables in generated-reference modules
need an adjacent `/**` comment and a standalone first sentence; compiler,
contract, and internal modules do not use that delimiter.

Report concrete examples from the top files and identify false positives.
Never rewrite source merely because the script flagged it. Use
`clean-x2c-source` only after the user chooses a cleanup scope.

Use `--rev REV` to inspect a historical tree, `--json` for machine-readable
output, and `--limit 0` to show every file. Generated `lib/x2c.x` is excluded.
