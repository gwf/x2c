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

Use the validation rules of `x2c lint` to make a review queue, then prove
each candidate from source, history, and behavior. A finding does not mean
the check is wrong or estimate how many lines can be deleted. Build the
command once with `make commands`.

For a broad compiler audit, start with values produced by one stage and
silently rejected by a later consumer:

```sh
builds/0/x2c lint --rule silent-shape-guard src/*.x lib/*.x
```

Each finding is a structural guard whose failure continues, returns null or
a fallback, applies a default, or keeps a partial result. Read the function's
callers, the `try_*parts` helper it re-runs, or the private map it reads to
find the producer; a direct caller is only a producer candidate until source
establishes that it constructed or normalized the value. The rule skips the
trust boundaries listed in the calibration reference.

Source `match` does not make a function trustworthy. It may be the clearest
recognition code in the function while adjacent `is <list>`, tag, arity, or
`try_*parts` guards still distrust the same compiler-produced value.

Use `--rule validation-framework` when the specific question is whether a
connected validator-named diagnostic subsystem exists; it reports each group
of calling validators with its authored lines.

For a parser, AST, or source-quality audit, list static method matches that
construct a binding List only to read it locally with `assoc`:

```sh
builds/0/x2c lint --rule static-match-capture src/*.x lib/*.x
```

These are candidates for source `match`, not automatic rewrites. Keep method
matching when its pattern is dynamic, the caller needs only a boolean, or the
binding List crosses the local branch.

## Review exact mechanical findings

```sh
builds/0/x2c lint --rule return-after-report-error --rule return-after-raise \
  --rule fallback-shared-cause --rule fresh-literal-null-guard \
  --rule growth-check --rule shape-diagnostics --rule recursive-validator \
  --rule validator-diagnostics src/*.x lib/*.x
```

A function's reasons are reported when its strongest reason is a
non-returning-failure rule or diagnostics built on shape checks; weaker
reasons appear only beside a stronger one. To compare two revisions, run the
same command in a checkout of each (`git worktree add`) and compare the
output. Read [`references/calibration.md`](references/calibration.md) when
changing the rules or deciding whether they recognize the intended pattern.

## Decide whether a candidate is redundant

Read the complete function, the code that creates or normalizes its value,
every downstream consumer, the relevant Error or compiler-stage behavior, and
the commit that added the check. Ask what observable result would change if
the check disappeared.

Apply PR-4, ER-4, ER-5, and FA-9 in
[the standard](../../x2c-code-standard.md). Read its trust-boundary paragraph
under "Validation signals" together with the calibration reference.

## Check the shape before writing another check

Apply PR-4 and the standard's trust-boundary paragraph to the producer and
its consumers. For canonical AST construction, consult "Macro-visible
syntax" in `docs/src/reference/language.md`. Apply EX-9 and MA-7 when a
shape can be recognized or destructured; apply FA-9 before proposing a
replacement checker.

## Hand off an authorized deletion

Completion is a read-only report of source-checked candidates, the behavior
that makes them redundant, and any unresolved uncertainty. For an authorized
campaign, use `simplify-x2c-source` to remove the whole connected slice: helpers,
state, repeated checks, dedicated diagnostics, validator-only fixtures,
comments, symbols, and generated artifacts. Keep direct tests of valid
behavior and of any retained public failure rule.
