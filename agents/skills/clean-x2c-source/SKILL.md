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

# Clean x2c Source

Apply the repository style standard as a semantic audit, not as a formatter.
Start each file from its own source, tests, and contracts so conclusions from
one cleanup do not silently carry into another.

## Establish the boundary

1. Read the root and nearest `AGENTS.md` files.
2. Read the style-guide sections for the requested cleanup. Read the complete
   guide only for a repository-wide style migration.
3. Read `agents/x2c-philosophy.md` when ownership or contract placement is in
   question.
4. Inspect the target's current diff and preserve unrelated work.
5. Confirm that the target is hand-authored. Never edit `lib/x2c.x` or files
   under `bootstrap/`.
6. Read the target completely. Then inspect its tests, public declarations,
   generated reference, and user-facing documentation when they help define
   behavior.
7. Record structural deletion opportunities separately and route them to
   `simplify-x2c-source`; do not turn a style pass into that work.

Run the mechanical survey from the repository root:

```sh
agents/skills/clean-x2c-source/scripts/audit-source.sh path/to/file.x
python3 agents/skills/find-redundant-validation/scripts/redundant_validation.py \
  --static-match-captures --details path/to/file.x
```

Capture both outputs before editing so the final report can compare the same
measurements and candidates.

The survey reports violations separately from review candidates. Its small
lexical helper masks comments and literals and balances delimiters; it does not
parse, rewrite, or compile source. Violations include mechanical whitespace,
ordinary forward declarations, reliable wrapping errors, immediate
declaration/assignment pairs, and one-executable-statement braces. Width
exceptions, cross-unit runtime declarations, horizontal compaction, repeated
accessors, and adjacent static output remain review candidates because their
correctness depends on source meaning. The second command reports static
method-match bindings read locally through `assoc`.

Treat every finding as the start of a source review, not an automatic edit.
Keep a vertical body when it deserves emphasis or a comment, keep method
matching when its result must escape the local branch, and retain a reported
runtime declaration only for the exceptions in the style guide.

## Build a preservation ledger

Before deleting or rewriting prose, list the information that is not obvious
from the code:

- ownership and module boundaries;
- public behavior, failures, and lifetime;
- representation, bit layout, grammar, ordering, or phase constraints;
- compatibility and bootstrap requirements;
- reasons an apparently simpler implementation is wrong;
- intentional aliases, coercions, casts, forward declarations, and includes.

Treat tables, diagrams, grammars, equations, and aligned examples as semantic
artifacts. Their spacing may encode meaning. Preserve their rows byte-for-byte
when relocating them until their column relationships have been independently
checked. If a shortened replacement cannot carry the same coordinates, keep
the original or remove it only after proving another owner contains the full
information.

For every removed comment, identify one disposition:

- repeated by a stronger contract owner;
- directly visible in the adjacent code;
- relocated intact beside the code it explains;
- obsolete, with source or test evidence.

Do not use line count as a proxy for success.

## Revise the file

Follow the style guide and make the complete coherent pass:

- reduce the module header to ownership and shared constraints;
- move local representation details beside their implementation;
- compact trivial `/**` comments and preserve substantive contracts;
- remove narration, decorated rulers, repeated prose, and prohibited phrases;
- normalize prologue order, vertical space, width, names, and control flow;
- use the full 79-column budget before wrapping, keep short single-statement
  control flow horizontal, and group nearby declarations by type when they fit;
- write negative type tests as `value is not Type`, not
  `!(value is Type)`;
- inline one-use side-effect-free temporaries and prefer established predicates
  or helpers when they preserve the exact semantic domain;
- use only syntax verified in current source, documentation, or a focused
  compiler probe.

Keep public signatures and behavior stable. Do not broaden the task into
structural simplification, API redesign, semantic cleanup, or generated-
artifact refresh without explicit scope.

Use `apply_patch` for edits. Re-read the whole file after the patch; reviewing
only changed hunks misses spacing and narrative problems created at their
edges.

## Audit the result

Run both surveys again, then inspect:

```sh
git diff --check
git diff -- path/to/file.x
```

Verify each preservation-ledger item in the final source. For aligned semantic
artifacts, check row widths and significant columns programmatically rather
than relying only on visual inspection.

Review every wrapped construct and adjacent same-type declaration group against
the available horizontal space. Review every cast, converter, temporary,
hand-expanded predicate, negated `is`, class-style call, post-allocation check,
and forwarding layer. Remove or compact it only when the current compiler and
library contracts prove the intended form. Review every surviving comment for
information unavailable from the code.

## Validate

Use the narrowest check that proves the edited boundary during development.
For a completed coherent runtime or compiler batch, follow the repository
contract and run the broad gates once on the integrated result:

```sh
make build
make verify
make stage-3
```

After a green stress test, use `make stage-diff-all` when stage convergence
is relevant. Run documentation and artifact checks that the edit can affect.
Distinguish a stale generated hash or byte offset from a compile, runtime, or
contract failure; never describe a red aggregate target as fully passing.

Do not refresh generated documentation, symbol artifacts, or bootstrap merely
to hide a failing check. Refresh them only when the task includes those
derived changes and the diff has been reviewed.

## Work in batches

For multiple files, inventory the full set first and keep a per-file
preservation ledger. Edit coherent tranches, but do not run broad gates after
every file. Finish each file's source review before carrying its patterns into
the next file.

Mechanical findings identify candidates, not required edits. The audit script
must never be used as an automatic prose rewriter.

Run the helper's standalone focused tests after changing the audit itself:

```sh
python3 agents/skills/clean-x2c-source/scripts/test_source_style.py
```

## Report

The pull request body carries the files changed and why they were selected,
the before/after mechanical measurements, unique information retained or
relocated, any local simplification beyond prose and layout, the validation
that passed, and any stale derived artifact left behind. Gary gets the reply
the root `AGENTS.md` Communication section describes, plus an unresolved
decision if one is waiting on him.
