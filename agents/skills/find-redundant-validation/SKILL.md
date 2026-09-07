---
name: find-redundant-validation
description: >-
  Find and rank likely redundant validation in hand-authored x2c source,
  including returns after non-returning errors, impossible null or growth
  checks, diagnostic-only validators, recursive AST checkers, and manual List
  shape checks that may be one match. Use for over-validation audits, release
  bloat reviews, redundant-check hunts, or comparison with a revision that
  removed defensive machinery. This skill is read-only and never rewrites
  source.
---

# Find redundant validation

Use the finder to make a review queue, then prove each candidate from source,
history, and behavior. A score is the strongest individual mechanical signal;
independent weak signs are not added together. It does not mean the check is
wrong or estimate how many lines can be deleted.

For a broad compiler audit, start with values produced by one stage and
silently rejected by a later consumer:

```sh
python3 agents/skills/find-redundant-validation/scripts/redundant_validation.py \
  --producer-consumers --details src lib
```

This groups structural guards under their direct callers, the `try_*parts`
helper they re-run, or the exact private map they read. It shows where the
value entered the consumer and whether an impossible branch continues,
returns null or the original value, applies a default, or retains a partial
result. These are candidates, not conclusions: read the reported producer and
consumer before deleting anything. A direct caller is only a producer
candidate until source establishes that it constructed or normalized the
value.

Source `match` does not make a function trustworthy. It may be the clearest
recognition code in the function while adjacent `is <list>`, tag, arity, or
`try_*parts` guards still distrust the same compiler-produced value.

Use `--frameworks` when the specific question is whether a
connected validator-named diagnostic subsystem exists. It groups those
functions by authored lines; it is not the starting point for producer-side
trust work.

For a parser, AST, or source-quality audit, list static method matches that
construct a binding List only to read it locally with `assoc`:

```sh
python3 agents/skills/find-redundant-validation/scripts/redundant_validation.py \
  --static-match-captures --details src lib
```

These are candidates for source `match`, not automatic rewrites. Keep method
matching when its pattern is dynamic, the caller needs only a boolean, or the
binding List crosses the local branch.

## Review exact mechanical findings

From the repository root:

```sh
python3 agents/skills/find-redundant-validation/scripts/redundant_validation.py \
  --details src lib
```

Use `--min-score 1` to include weak candidates in ordinary mode, `--limit 0`
to show all results, `--json` for analysis, and `--rev REV` for a historical
tree. Generated `lib/x2c.x` and untracked files are excluded.

Compare a deletion with its parent or a reduced revision:

```sh
python3 agents/skills/find-redundant-validation/scripts/redundant_validation.py \
  --compare OLD..NEW --details src lib
```

Comparison mode reports candidate functions and diagnostic fixture families
that disappeared. Read
[`references/calibration.md`](references/calibration.md) when changing the
finder or deciding whether it recognizes the intended pattern.

## Decide whether a candidate is redundant

Read the complete function, the code that creates or normalizes its value,
every downstream consumer, the relevant Error or compiler-stage behavior, and
the commit that added the check. Ask what observable result would change if
the check disappeared.

Delete the check only when the existing path still:

- preserves every valid program's generated output and runtime behavior;
- rejects invalid input before it can become silently wrong output, corrupt
  compiler state, or cross an unsafe native boundary; and
- preserves any diagnostic that the language or public API deliberately
  promises.

It is acceptable for invalid source to fail later or with a different message
when neither diagnostic is promised and the later failure is safe. A negative
fixture written only for the candidate validator is evidence of that
validator, not an independent production consumer.

Keep checks for untrusted external input, documented null or absent values,
resumable user-defined Error causes, callbacks, I/O status that can return,
overflow before an operation, and public behavior that would otherwise accept
an invalid program or value.

## Check the shape before writing another check

Trust the value published by each compiler stage. The scanner establishes
token boundaries and spelling, the tokenizer establishes token class, parsing
and macro binding establish canonical AST shapes, and transforms establish
their output shapes. Validate arbitrary source bytes, Lisp values, files, and
serialized data where they enter; do not repeat the same validation after that
code has published its internal value.

When code inspects one static List or AST shape with `car`, `cdr`, `len`, and
type tests, first decide whether failure needs its own behavior:

- use direct access or flat destructuring when an earlier phase guarantees the
  shape;
- use a source `match` when success selects a local branch and failure can use
  the existing path; and
- keep explicit checks when each rejection has intentional behavior that the
  surrounding compiler would not otherwise provide.

Do not replace a redundant validator with a shorter validator or add a
catch-all match arm solely to preserve its diagnostic.

## Hand off an authorized deletion

This skill only discovers candidates. For an authorized campaign, use
`simplify-x2c-source` to remove the whole connected slice: helper functions,
state, repeated checks, dedicated diagnostics, validator-only fixtures,
comments, symbols, and generated artifacts. Keep direct tests of valid
behavior and of any retained public failure rule.
