# Lint

`x2c lint` reports x2c source that departs from this repository's idiom.
Each finding names a rule code and the rule ID in
[the code standard](../../agents/x2c-code-standard.md) that owns it;
`--rules` prints the table. Language rules run by default, `--all` adds the
style rules, and `--rule CODE` selects rules. Pass module entry files: lint
checks each member file that an entry splices under the member's own path
and lines, and proves a member's fixes through its entry's translation. The
census in `tests/run.sh` lints the entries that `tools/sources.sh` lists, so
it covers their members.

The command is experimental. It builds in a checkout with `make commands`;
`make install` and release payloads do not install it.

## Function reading order

`function-reading-order` is an optional FI-4 style candidate. Select it
explicitly after building the lint command:

```sh
builds/0/libexec/x2c-lint --rule function-reading-order \
  -I src -I lib src/expressions/expressions.x
```

The driver form is `builds/0/x2c lint --rule function-reading-order FILE...`.
Pass module entry files; the candidate checks their physical member files in
context and reports each member's physical path and line.

`--all` alone excludes this explicit-only candidate. Combining `--all` with
`--rule function-reading-order` selects it alongside the ordinary rules.
Normal lint selections and the existing corpus census retain their behavior.
Findings keep lint's zero exit status; unreadable or unparseable inputs retain
lint's nonzero status. This candidate creates no edits, including with --fix.

### Checks

- Public placement: the first public definition after private implementation
  in each ordinary function run.
- Public dependency inversions: caller-before-callee paths through known
  private, generated and module-member functions, projected onto one physical
  file. Paths name bound references, including function values and callbacks;
  the checker does not guess indirect targets.
- Private direct inversions: a helper precedes its first known consumer.
  Earlier distinct consumers justify later upward calls, including consumers
  in a recursive group or known meta definition. Self-reference alone does
  not introduce a helper for another reader.

Dependency order inside a recursive component is free. Mixed components still
have public-first placement. Unrelated ties remain valid. Module definitions
are private implementation for placement. Thematic group fragmentation is
outside this candidate's scope.

### Coverage and exceptions

Only mapped ordinary authored definitions enter source-order comparisons.
Comments and whitespace can separate definitions in one checked run. Other
source forms are boundaries, including macro/decorator/meta definitions,
includes, declarations, preprocessing and script statements. Directives inside
an ordinary function also exclude it from these comparisons. Known generated
or nonmovable AST functions can still explain dependency paths.

Coverage lines go to standard error. A zero-definition row or no findings
never certifies whole-file conformance. The graph covers the configured parsed
unit; omitted compile-time definitions, unresolved callbacks, other units and
other preprocessing configurations remain coverage limits. Repeated configured
views still run; identical diagnostics are deduplicated. Member suppressions
use the same immediate-next-physical-line rule as other lint findings:

```c
// lint: allow function-reading-order FI-4: retained teaching sequence
int primary(void) { return helper(); }
```

Use the function-ordering skill for a reading-order review that needs those
source-order judgments. Keep deliberate code unchanged while reviewing
candidates.

## Local checks

Run `sh commands/lint/tests/reading-order.sh` for the optional graph, boundary,
module, layout, script, selection, suppression and read-only checks. This
focused script is not part of the recurring gate. The existing lint checks
remain `sh commands/lint/tests/run.sh`.
