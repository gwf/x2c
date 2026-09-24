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
builds/0/x2c lint --rule silent-shape-guard src/*.x lib/*.x lib/*.xmacro
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
  --rule validator-diagnostics src/*.x lib/*.x lib/*.xmacro
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

Recommend deletion only when the existing path still:

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
their output shapes. Use the ordinary consuming operation to handle source
bytes, Lisp values, files, and serialized data. Once it establishes an internal
fact, its consumers can rely on it. Canonical AST Lists are accepted by
structure, as
documented in `docs/src/reference/language.md` under "Macro-visible syntax".

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

Completion is a read-only report of source-checked candidates, the behavior
that makes them redundant, and any unresolved uncertainty. For an authorized
campaign, use `simplify-x2c-source` to remove the whole connected slice: helpers,
state, repeated checks, dedicated diagnostics, validator-only fixtures,
comments, symbols, and generated artifacts. Keep direct tests of valid
behavior and of any retained public failure rule.
