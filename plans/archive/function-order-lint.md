# Optional function reading-order candidate

> Status: done, implementation and findings review complete, 2026-10-27.
> Implementation: `2422a235`. Gary authorized validation and publication.
> All nine reviewed placements and the module layout remain unchanged.
> Thematic fragmentation and further ordering work remain deferred.

## Contract

Add `function-reading-order` as an FI-4 style candidate in the existing lint
command. It requires explicit `--rule` selection, including when combined
with `--all`; family selection excludes explicit-only candidates. Existing
census and readiness commands retain their existing selections and baseline.
Findings retain the lint command's existing zero exit status. Read/parse
failures retain their existing nonzero status. This rule proposes no fixes.

Use the existing parsed unit, definition rows, bound reference collector and
physical source mapping. Compute dependency reachability across the configured
unit, then check each physical file. Include bound callbacks and generated
intermediates in paths. Do not infer indirect targets or dependencies by name.

Within an ordinary authored run separated only by comments or whitespace,
report the first public definition following private implementation. Report
public dependency inversions, including private intermediary paths, and
private direct edges whose helper appears before its first known consumer.
An earlier consumer exempts later upward calls, even when recursive unit-wide
reachability would merge editorial themes. Recursive interiors are accepted.
Public-first still
applies inside mixed public/private recursive groups. Existing unrelated ties
remain valid. Module functions are implementation, not public placement roots.

Meta/decorated definitions, directives, declarations, top-level statements and
other active source forms bound safe runs. Compile-time-only definitions may
not survive the available parse. Report ordinary-definition/run coverage on
stderr; silence does not establish full-file conformance. Keep unknown source
constraints as review limits rather than adding prototypes or compiler APIs.
Member findings and suppressions use physical paths/lines. Repeated configured
views still run; only identical findings are deduplicated across views.

## Verification and delivery

Use focused optional fixtures for positive inversions and accepted shared,
recursive, independent, module, layout, script, and source-boundary cases.
Verify explicit/default/all selection, suppression, and read-only --fix.
Run the existing lint suite for compatibility. The focused optional script is
not added to a recurring gate. Review the completed authored diff and fix
findings before final local verification.

Inventory all tracked src/lib/examples .x/.xp files. Analyze configured entry
units and module members, and record generated files and failures explicitly.
Save raw findings, coverage and a readable report in .context/function-order-lint.
The initial review stop excluded source-order repairs, package installation,
publication, commits and pushes. Gary subsequently authorized publication of
this lint implementation after validation. No ordering repairs or module
changes are selected.

## Design review

Reuse compiler identities, AST references, definition metadata, module source
maps, rule selection and suppression. No parser, persistent graph snapshot,
compiler warning, cache or new gate is introduced. Missing graph facts remain
coverage gaps; candidates are review evidence and never an automatic move.

## Local outcome

Focused optional tests, the existing lint suite, native command build and
documentation checks passed. The 419-file inventory has 416 ordinary-subset
coverage rows, two generated exclusions and one existing package-context parse
failure. Final output is nine public dependency candidates in four files;
shared-helper placements are accepted by a conservative first-known-reader
check. Raw evidence and the review report are in
`.context/function-order-lint/`. All src/lib/examples files remain unchanged.

## Review decision

The nine remaining candidates are advisory. Keep all current placements and
module boundaries. Public-first thematic ordering remains a guideline for
substantive edits rather than a zero-warning cleanup target. The candidate
requires explicit selection and remains excluded from default and --all
family selection. Publication uses the existing agent-pr-check; the focused
optional script remains outside recurring gates.
