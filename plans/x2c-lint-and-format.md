# x2c lint and format

> Status: needs author scoping - designed 2026-09-17, no phase implemented.
> This is the design that [x2c-scripting-ports](x2c-scripting-ports.md)
> defers under "Rewrite on the compiler instead of translating", where
> `tools/x2c_source.py` is called the keystone and the rewrite is left "to be
> planned on its own before implementation". Gary decided three things when
> this was scoped: lint ships as an `x2c lint` subcommand, it stays an
> optional check until it can replace the Python analyzers, and the 31-class
> ceiling gets a diagnostic rather than a runtime change. Rule inventory comes
> from the 2026-09-17 dogfooding survey; the adoption work it feeds is
> [x2c-dogfooding-remediation](x2c-dogfooding-remediation.md).

## The result

One engine, built into the compiler, that answers three questions about a
hand-authored `.x` file and can act on two of them.

1. Is this code saying something the compiler already knows is redundant? It
   answers that today for casts, explicit converters, and region escapes.
2. Is this code correct but not the idiom this repository teaches? That is
   new: a rule table, a proof mode that checks a rewrite emits byte-identical
   C, and an autofix for the rules that are pure token edits.
3. Is this file's whitespace what the style guide says? That is the formatter,
   last and smallest.

The motive is mechanical. Agents reproduce what they read, and review has not
closed the gap: the survey measured zero uses of `in` in 33k lines of `src/`
against 142 `.contains(` calls, 279 hand-written acquire-and-`defer` pairs and
zero `$auto` in `packages/`, and 178 removable arrows. A tool can hold a line
that review does not.

## Three tiers, and the rule for deciding which one a finding is

This is the load-bearing decision; everything else follows from it.

**A compiler warning** is on by default, on the build path, and requires all
four of: universal to the language rather than a house preference; free,
because it rides a walk the compiler already performs; near-zero false
positives, because there is no suppression mechanism and
`Compiler.report_warning` never changes exit status; and a fix that is
byte-identical C, or the compiler is advising a behavior change. The
unnecessary-cast and unnecessary-converter warnings qualify - the converter
warning records one entry during parsing and seven destinations compare
against it. The region pass cost +4.3% translation time and needed an explicit
ruling, which is the ceiling rather than the budget.

**A lint finding** is correct code that is not this repository's idiom. It is
opt-in, never on the build path, may need whole-file context, and its
equivalence is proven by diffing generated C rather than asserted. This is
where the survey's rule families live: `->` where `.` works, `%` where a bare
literal means the same, `.contains(x)` where `x in c` fits, an acquire-and-
`defer` pair where `$auto` applies, `Type.method(x)` where `x.method()` works,
`{ return e; }` where `=>` fits, `String.new("lit")` and `Array.new()` where a
literal fits, field-by-field initialization, ungrouped declarations, plus the
comment, validation, and bloat families the Python analyzers own today.

**A format change** is determined entirely by the token stream: width,
wrapping, indentation, brace and `else` placement, blank runs, spacing.

Promotion from lint to warning requires all four warning tests, which almost
no style rule passes - `.contains` to `in` is taste, not truth. Writing that
down is what stops the compiler acquiring a house style it cannot retract.

Two boundaries need stating because they blur. Ungrouped adjacent declarations
look like formatting but change tokens and need to know the declarations are
independent with no comment between them: a lint rule with a structural fix,
never the formatter. Comment slop is a lint finding; a formatter may reflow a
comment's interior only under an explicit flag and never deletes one.

Four survey findings are **not** rule candidates at all. They are missing
diagnostics, and they belong in `fix-x2c-bug`: `Var.new(<string>, "lit")`
translating to a value that aborts at runtime, `.` through a pointer to a
pointer typedef emitting a wrong call, `.` to an anonymous-aggregate member
emitting uncompilable C, and a method call with too few arguments translating.
A linter that grows around a compiler which stays silent on wrong programs is
the wrong shape.

## Where it lives

The engine is `src/lint.x`, reusing `Frontend` and `ParsedUnit` exactly as
`tools/x2c-graph` drives them, matching canonical forms with `match` and
`%()` patterns over the bound, typed AST. Types are already resolved, so the
membership rule can check that a receiver is a Map, List, Array, or String and
not a `SymbolSet`, which `in` rejects. Token rules read
`compiler.tokenizer.tokens`, which retains comment and space tokens with exact
line, column, length, and position - the honest replacement for a pseudo-parser
that has to re-implement `%(...)`, `%<<...>>`, `$(...)`, and `#define` bodies
in regular expressions. The comment family needs both, bridged by the `(at N
node)` origin rows and a binary search of the token array by position.

Delivery is an `x2c lint` subcommand: a mask bit, a `cli_commands[]` row,
option rows, a help printer, and dispatch in `src/main.x`. Nothing calls lint
on the translate path and no flag puts it there, so translation cost stays
zero; the cost is binary size, measured at Phase 1 against a stated threshold,
with the engine moving into a tool over `builds/libx2c-dev.a` if it exceeds
one. A subcommand publishes this repository's house style on the compiler's
public surface, which is the real objection to it; the mitigation is that
rules carry a family - language-universal or repository policy - and the
default set is the language-level rules, with repo policy selected explicitly.

Rules are plain x2c in one static table, the shape `printf_family_info[]` and
`cli_options[]` already use: code, family, input (`<ast>`, `<tokens>`,
`<both>`), fix kind (`<none>`, `<textual>`, `<structural>`), whether the fix
must translate identically, the message stem, the style-guide anchor, and the
check. `x2c lint --rules` prints the table, and that table is the whole
configuration surface.

## Findings, dispositions, and suppression

A finding reuses the diagnostics entry shape - code, severity, message,
location, notes - so the JSON Lines writer, the snippet and caret renderer,
and the editor's byte-span reply all work unchanged. Two additions: a `<lint>`
severity, so lint never looks like a compiler warning in a build log; and a
disposition, which promotes the survey's own vocabulary to a field - `SAFE`,
`CHANGES-FAILURE-PATH`, `NEEDS-MORE`, `KEEP`, `PREVIOUSLY-DEFERRED`. Default
output shows `SAFE` only.

`PREVIOUSLY-DEFERRED` carries a plan citation, so a finding an archived plan
already declined is reported with its reason rather than as a fresh idea. The
`$auto` rule must cite
[core-system-macro-defer-audit](archive/core-system-macro-defer-audit.md) and
must separate a `defer x.free()` right after a complete initialized
declaration, which is `SAFE`, from an explicit free at end of block, which
`$auto` would also run on an error exit. Reporting the second as the first is
how a linter loses an author's trust in one session.

Suppression exists on day one, because the repository deliberately contains
the anti-patterns: roughly 128 percent-string sites in
`unittest/compiler-fixtures/` whose subject is percent strings, and 190 arrows
on native-header struct pointers where `.` is broken C. Path-glob exclusions
per rule live in `etc/lint.xlisp`, beside the other runtime-loaded data, and a
`// lint: allow <code> - reason` comment suppresses one line, with the reason
required and printed by `--allowed`, so a suppression documents intent rather
than silencing a rule.

## Autofix is proven, not asserted

`--fix` applies non-overlapping textual edits right to left, one pass per
file. For any rule whose fix must translate identically, `--fix` translates
the file before and after and refuses to write on any difference; `--prove` is
on by default and `--no-prove` must be spelled. This promotes the survey's
central technique to a tool guarantee: 374 arrow candidates were classified by
rebuilding each file with one line changed and diffing the generated C, not by
eye. Identical C means removable by construction, which no regex tool can say.

Structural fixes - declaration grouping, designated initializers,
acquire-and-`defer` to `$auto` - stay report-only with a suggested spelling in
a note until the formatter's printer exists. Autofix never touches comments.

## Detection methodology

How these anti-patterns were found, and what a rule author owes before a rule
ships. Each step has a matching fixture.

**Census, then classify every hit by reading.** A rule starts as a whole-repo
census of its raw pattern, followed by hand classification - every hit for a
small family, a documented sample for a large one - and ships only when the
KEEP set collapses into a few stated predicates. The arrow rule is the model:
374 real member accesses, 178 removable, and the 196 keeps decompose into
exactly four predicates. Those four predicates are the rule. Each becomes a
negative fixture, and the census count goes in the rule's doc comment as the
expected finding count at the commit where it lands, so later drift in either
direction is visible.

**Decide equivalence by rewriting and diffing generated C.** No rule asserts
equivalence from reading. A corpus runner applies each identical-translation
rule to every hit in the authored tree and diffs before and after; any
difference fails the rule, not the file. The counter-examples found this way
become negative fixtures: `%{}` at a `Var` destination, where the bare form is
Null; `===` identity against a cached literal; `Var.new` raw payloads.

**Probe a limit by generating declarations until it breaks.** A rule that
suggests a construct with a capacity limit must know the limit. The concrete
case is `class`: at most 31 record or heap classes per linked program, and the
32nd aborts at startup even when never boxed. One file cannot count the rows
in a link unit, which is the answer - class conversion is never an autofix. It
is reported as `NEEDS-MORE` with the limit named, or not at all. The probe is
pinned as a fixture so the limit is a checked fact rather than a remembered
one.

**Compare a file against the exemplar.** `--score` ranks files by weighted
findings per 100 lines, to queue cleanup rather than gate anything.
`literate-lisp.x` must score zero: a rule that fires on the exemplar is wrong
about the house style by definition. The corollary matters as much - the three
most dated files in the survey scored low mechanically because their dated
spelling is an absence. Scoring finds bad spellings and cannot find the
absence of good ones, so a zero score is not a clean file.

**Read the archive first.** Every rule declares in its doc comment the
archived decisions that bound it, and the `PREVIOUSLY-DEFERRED` disposition
reports a declined finding with its citation. A fixture per cited decision
carries the archived reason in its expected output, so a later reversal is
visible as a diff.

The checklist a rule author follows: census and record the count; classify
until KEEP is a list of predicates; rewrite and diff; probe any limit; read the
archive and attach citations; write the rule, one positive fixture, one
negative fixture per KEEP predicate, and the proof entry; confirm the exemplar
still scores zero.

## The formatter

`src/format.x` is not a source formatter: it prints emitted C tokens, has no
comments and no AST input. Its whitespace helpers are reusable and nothing
else is.

One contract keeps a formatter small: it changes only whitespace tokens, so
the non-trivia token sequence is invariant byte for byte. That is checkable
per file by tokenizing both sides, which means the formatter needs no
generated-C proof at all and idempotence is a one-line test. Anything that
changes tokens is a lint rule instead.

What is missing today is narrow and worth stating exactly. Trivia exists, with
spans. Node starts exist partially - origin rows carry the opening token's
position, anchored at statement and declaration granularity. Node ends do not
exist anywhere in the AST, and macro-constructed nodes carry a marker rather
than a position. So the prerequisite is a half-open token range per node and a
rule attaching each comment to a node: one more integer per origin row plus
anchoring at expression granularity under a request flag, so ordinary
translation pays nothing. Not a new parser, and not a CST.

Token-only formatting ships first as `--check`: trailing whitespace, tabs,
blank runs, spacing, indentation by bracket depth, `else` placement, and width
reporting. AST-guided wrapping waits until `--check` has run over the whole
repository and the remaining diff has been measured; the repository already
holds 79 columns by hand, so token-only plus the linter may be the entire
value.

## Editor integration

The reply already carries diagnostics as byte spans and `argv[3]` is already a
request kind, so there is a slot. Four increments: a `lint` kind adding a lint
array in the same shape, which the extension maps to a Hint with the rule code
so VS Code's grouping works; a `fixes` array of byte-range replacements behind
a code-action provider; a `format` kind and a formatting provider, which
`package.json` does not contribute today; and nothing else. No language
server - the one-request-per-process protocol is adequate for per-file lint
and format, and an LSP is a separate project with its own justification.

## Consolidation and deletion

Four Python analyzers over one regex pseudo-parser are replaced: 604 lines of
style checks, 569 of comment slop, 1,042 of redundant validation, 860 of
source bloat, three pytest suites, and a shell script - 4,013 lines. Each is
deleted only after a recorded parity run shows lint reports a superset of its
findings on the same corpus, diffed as file, line, and category sets and
pasted into this plan; `tools/x2c-graph/tests/ast-parity.x` is the precedent.
A finding the Python tool produced and the rule does not is either a missing
rule or a documented false positive, and both go in the record.

`find-comment-slop` and `find-redundant-validation` fold into
`clean-x2c-source`, selected by rule family: one skill, one tool, two
`SKILL.md` files and two script directories removed. The style guide's review
checklist stops citing `audit-source.sh` and cites the tool. Every rule's
message cites the guide section that owns it, and a rule without a guide
section does not ship - that is what keeps the tool from becoming a second,
drifting style authority.

`tools/x2c_source.py` is not deleted here. When this plan finishes, its
remaining importers are the doc and metrics generators, which belong to
[x2c-scripting-ports](x2c-scripting-ports.md); this plan hands that plan the
keystone with a smaller blast radius.

## Phasing

0. Finish the precursor: give the two conversion warnings real codes instead
   of the generic `<warning>`, and fix the duplicate-report defect. Codes are
   the precondition for suppression, editor grouping, and lint's own dedupe.
1. Engine, subcommand, token rules reproducing `source_style.py` and
   `audit-source.sh`; parity run; delete both; rewrite the review checklist;
   measure the binary-size delta.
2. The identical-translation idiom rules with `--fix --prove`. The survey
   already enumerates the targets, so this phase ends with one cleanup
   delivery per family, each quoting its proof run.
3. Comment rules; parity; delete `comment_slop.py`; fold the skill.
4. Editor lint kind, then fixes and code actions.
5. Structural rules, report-only; parity against `audit-source-bloat.py`.
6. `fmt --check`, token-only, with the whole-repo diff measured before
   `--write` is proposed.
7. Separate approval each: the redundant-validation family, `fmt` promotion,
   AST-guided wrapping, and any gate.

Phases 1 through 3 are worth shipping even if nothing after them lands. That
is the test of this phasing.

## Process ceiling

This plan adds no gate. `precommit`, `sanity-check`, and `agent-pr-check` are
unchanged through Phase 6; the tool builds on demand. Lint fixtures live with
the tool, not in `unittest/compiler-fixtures/`, so `make verify-fixtures` does
not grow - that harness is reserved for rules that become compiler warnings,
where the existing `diagnostics` phase already byte-compares stderr. If lint
is later to run in `check-after-precommit`, the consolidation ledger above is
the equal-cost removal the ceiling requires. This plan names that trade and
does not take it.

## What this does not build

No rule DSL, plugin system, or severity matrix - rules are x2c functions in
one table, configured by a path-glob list and a line comment. No second
parser, ever: if a rule cannot be written on the tokenizer or the bound AST it
is not a rule, and reintroducing a heuristic matcher inside the new tool would
be the same mistake in a new language. No lint pass on the translate path. No
warnings-as-errors and no per-code compiler suppression. No AST
pretty-printer: the whitespace-only contract makes it unnecessary, and
building one is how a formatter acquires the ability to change a program
silently. No autofix for structural rules until a printer exists, and none
that touches comments. No class-conversion autofix. No `not in` invented to
make the membership rule symmetric - a linter must not create pressure for
syntax. No rewriting of `unittest/compiler-fixtures/`. No LSP server, CI
dashboard, or metrics trend.

## Risks

False positives are the one failure that cannot be walked back: an agent that
sees a wrong suggestion learns to ignore every suggestion. The census
obligation, the negative fixtures, and disabling by default any rule that
cannot reach zero false positives on the repository corpus are the answer.
Agents treating lint output as a work queue is the second risk, which the
`SAFE`-only default and the required proof run address. A second style
authority drifting from the guide is the third, which the cite-a-section rule
addresses - and the survey found the guide already wrong in two places, so
Phase 1 corrects the sections its rules cite. The honest last risk is that an
optional tool may not be run, which is exactly the broken-windows problem it
exists to solve; the two options, left open, are to rely on the skills that
invoke it or to spend the consolidation ledger on a gate.

## Plan review

**Facts established elsewhere and not rechecked.** Binding identity,
expression types, and receiver resolution come from the typing pass and rules
read them. Token spans and trivia come from the tokenizer; no rule re-lexes.
Region and lifetime facts belong to `src/regions.x` and no rule restates them.
Equivalence of a rewrite is established by the compiler itself through the
generated-C diff, not by a rule's reasoning.

**Deletion and reuse.** Deletes 4,013 lines of Python, two skills, three
pytest suites, and a shell script, and hands `tools/x2c_source.py` back with
three importers instead of five. Reuses `Frontend`, `ParsedUnit`, the
diagnostics entry shape, the JSON Lines writer, the source-context renderer,
the editor byte-span protocol, and the tokenizer. The genuinely new mechanisms
are three - the rule table, the disposition vocabulary, and the proof harness -
and each is justified above; none is a framework.

**Idiomatic x2c.** Rules are `match` and `%()` walks over canonical forms with
a static table, the shape of `src/cleanup.x` and the rewritten `src/regions.x`,
rather than a visitor framework imported from another compiler.

**Validators, diagnostics, and negative fixtures.** Every rule ships one
positive fixture, one negative fixture per stated KEEP predicate, and a proof
entry where the fix must translate identically. Each negative fixture protects
a case where the obvious rewrite changes behavior: the `Var`-destination
`%{}`, the `===` identity literal, the native-header arrow, the
function-pointer field whose name is a method, and the `$auto` that would add
error-path cleanup. No rule rejects legal syntax, no lint finding changes an
exit status, and nothing runs during translation. The four wrong-program cases
the survey found are routed to the compiler as diagnostics, where each
protects wrong output or a crash.
