> Status: done
> Implemented 2026-10-16 through `28d1ceec`; definitions remain with their owners.
> Publication requires the existing gate and generated-artifact review.

# Normalize error reporting in src

## Result and scope

Normalize diagnostic definitions and calls throughout hand-authored `src/`.
Keep each definition with its owner and preserve existing messages and behavior.
The result uses named local diagnostics, shared catalogues only where useful,
and the existing reporting operations. It introduces no reporting framework.

Include compiler diagnostics, driver errors and warnings, SDK rejections,
component meta diagnostics, deferred analysis findings, and their message and
note helpers. Inspect inline reporting as well as existing macros. Separate
progress and debug entries encountered in mixed catalogues by their names;
do not redesign general logging or progress output.

Runtime, package, and external-command catalogues outside `src/` are not part
of this migration. Preserve calls to their existing APIs. Generated source,
including `src/linked-meta.x`, changes only through its documented generator.

## Current evidence

The survey found 390 `$report.*` macro definitions in 35 source files:

- Driver and build: `build`, `cli`, `frontend`, `main`, `project`, `script`,
  `toolchain`, and `utils`.
- Parsing and typing: `collect`, `parse`, `statements`, `symbols`, `literals`,
  `macros`, `expressions-reports`, `parse-report-macros`,
  `compiler/declarations`, and `compiler/parsing`.
- Lowering and emission: `cache`, `callables`, `lambdas`, `stage`, `transform`,
  `emit/initialization`, and `generate/output`.
- Meta execution: `meta-group`, `meta-helper-client`, `meta-native`, and
  `meta-sdk`.
- Protocols and analysis: `protocol/adapters`, `protocol/declarations`,
  `protocol/registry`, `protocol/resolution`, `regions/flows`, and `regions/walk`.

This is a starting inventory, not the scope boundary. Component files also
call `x2c_diagnostic_*` directly or through typed meta helpers. Reporting
boundaries such as `diagnostics.x` own generic delivery rather than case
catalogues. Inspect all source files for remaining case-specific reporting.

`expressions-reports.x` is included by `expressions.x` and `macros.x`.
`parse-report-macros.x` is included by `parse.x`, `statements.x`, and `symbols.x`.
Their macros are nonstatic intentionally. File-local catalogues use static
macros. No diagnostic catalogue meta-effect installer was found in this tree;
ordinary include processing installs exported compile-time definitions.

## Conventions

### Ownership and placement

- Keep a diagnostic used by one file in a diagnostic section near that file's
  top, as a `static macro`. Several call sites may use that one definition.
- Put genuinely shared diagnostics in `<owner>-reports.x`, included directly
  by consumers. Shared declarations remain nonstatic so consumers can use them.
  Do not change visibility merely to make declaration text uniform.
- A large local catalogue may move into a sibling file if this improves
  reading, but separation is not mandatory. Preserve binding and visibility
  when doing so; default to retaining local definitions.
- Share by responsibility and meaning, not merely matching message text.
  Do not duplicate a shared definition for each consumer or create a global
  compiler-wide catalogue.
- Retain typed functions for substantial computation, such as constructing
  delegate-path notes. Do not add a macro that only forwards to such a helper.

### Names and arguments

Macro names have one dot: `$action.owner_condition`. Use the responsibility
that owns the diagnostic, not its diagnostic category, as `owner`. Use one
consistent owner spelling across its catalogue, such as `protocol`.

| Action | Meaning |
| --- | --- |
| `$fail` | Reports a diagnostic and does not return normally |
| `$report` | Reports or records an error and returns |
| `$warn` | Reports or records a warning |
| `$note` | Constructs note text or a notes List |
| `$reason` | Constructs a reason String |
| `$error` | Retains the existing structured Error-raising convention |
| `$progress` | Presents ordinary progress or status output |
| `$debug` | Emits existing debug logging |

Choose the action from the actual callee and control flow. An stderr message
followed by a caller-owned return is not a nonreturning `$fail`. A deferred
warning remains deferred. Keep unrelated existing runtime macro names intact.

Arguments are context, explicit source site when applicable, then semantic
operands. Reports without source locations need no dummy argument. Preserve
the distinction between an explicit token, NULL with origin fallback, and
the current token. Pass the same expression the old definition used; do not
replace every implicit location with `c.token` indiscriminately.

Typed reporting helpers retain ordinary function syntax. Use an owner and
action in their name when renaming clarifies their role, for example
`_delegate_fail_ambiguous`. Do not change public reporter API names.

### Construction and delivery

The caller detects the condition. The catalogue owns case-specific wording,
category, message formatting, and note construction. Existing helpers retain
shared formatting, context selection, collection, recovery, and termination.
Use a direct expression body for one call and a scoped statement block when
construction needs temporaries. Retain existing helpers and List literals.

Extract substantial inline case-specific diagnostic construction into this
pattern. Generic renderers, pass-through reporters with caller-supplied text,
native failure floors, and short structured raises retain their representation.
Do not wrap every reporting API call merely to increase catalogue coverage.

For example, keep this definition in `protocol/registry.x`:

```c
static macro Stmt $fail.protocol_adoption_conflict(
  Expr $c, Expr $site, Expr $adoption, Expr $first_location) {
  {
    String first = %"first: ${_location_string($first_location)}";
    String second = %"second: ${_location_string($adoption.location)}";
    String spelling =
      _adoption_spelling($adoption.base, $adoption.participant);
    $c.report_error(
      <protocol>, %"conflicting adoption declarations for $spelling",
      $site, %($first $second));
  }
}
```

Its call is `$fail.protocol_adoption_conflict(c, c.token, adoption, first_location)`.
The macro retains the current formatting helpers and note order.

## Compatibility

Preserve message and note bytes, interpolation, note ordering, structured
payload keys and values, categories, severity, source selection, streams,
exit status, and returning versus transferring behavior. Preserve diagnostic
ordering, suppression, deduplication, limits, and deferred emission.

Preserve macro argument evaluation count and order, temporary scope, binding
hygiene, allocation lifetime, and ambient state such as `errno`. Do not change
NULL notes to empty Lists, or vice versa, as incidental cleanup. Do not move
guards, cleanup, or fallback actions into catalogue definitions. In particular,
component accumulating errors must still continue with their existing fallback.

No wording improvements, new diagnostics, or new validation are authorized.
On 2026-10-16 Gary approved one expected-output exception: the generated
cleanup helper definition line changes from 1262 to 1272. Its user-source
location, messages, and behavior are unchanged. Other expectations stay fixed. Report unrelated defects for
separate work instead of silently incorporating them.

## Implementation

1. Refresh the inventory against the implementation checkout. Search all
   hand-authored `src/` for report macros, direct diagnostic calls, rejection
   helpers, structured raises, and stderr reporting. Record each owner's old
   and new names, consumers, location behavior, and reporting operation in a
   temporary work record. Record retained generic cases as well as migrations
   so completion covers the whole directory.
2. Normalize private catalogues and their bound call sites by owner. Use
   symbol-aware edits or exact definition-and-call mappings with reviewed
   matches; do not apply unrestricted textual replacement. Keep existing
   reporting bodies unchanged except for the agreed argument normalization.
3. Normalize shared catalogues and all their consumers together. Rename
   `parse-report-macros.x` to `parse-reports.x`; retain `expressions-reports.x`.
   Resolve owner-qualified names from their actual responsibility and preserve
   include order, exports, and definition-time bindings.
4. Normalize component meta helpers, deferred findings, note/reason helpers,
   and substantial inline case construction. Keep typed computation typed.
   Classify mixed driver catalogues by actual behavior without changing their
   underlying output operation. Check the refreshed inventory for omissions.
5. Update the local-catalogue section of
   `agents/logger-and-diagnostics-guide.md` to describe the adopted conventions.
   Update any live references to renamed files or internal macros. Leave
   archived historical plans unchanged. Refresh generated artifacts only with
   existing repository targets when required.
6. Review and fix the completed authored diff before publication validation.
   Check ownership, binding, location selection, message and payload identity,
   return behavior, and unnecessary wrappers. Confirm that every source owner
   in the inventory is migrated or has a concrete reason to retain its form.

## Validation and delivery

Use existing focused checks during implementation when they answer a current
question. The diagnostic fixture checks (`make verify-fixtures`) compare
checked-in output without rewriting it. Reuse existing diagnostics, recovery,
protocol, component, and driver coverage for affected owners. Preserve all
expectations; investigate mismatches rather than accepting them as renaming.
Where existing coverage misses a changed construction, use a bounded before
and after probe for its message, location, notes, and control flow. Do not add
a recurring check or a parallel diagnostic test framework.

Follow the root instructions for fresh-worktree bootstrap preparation and
final delivery. The implementation uses the existing publication command,
`tools/gate-state.py ensure agent-pr-check`, after integration and diff review.
Do not run its broad components separately solely for publication. Review any
generated deltas. Apply existing performance guidance only if the actual
change reaches a covered hot path; this plan adds no performance requirement.

Gary authorized implementation on 2026-10-16 and subsequently selected
shared-integrator delivery. This session submits the reviewed change; the
integrator owns final combined validation and publication.

The full `agent-pr-check` gate passed at
`7a2524f72c182d40572c245cc61068f1129203ac`: 1,239 compiler fixtures,
951 unit tests, and 26,008 assertions passed. The later integration of
`dc98736033a92c37ffcd94b83faaf07b99e45b55` changes optional conformance
tooling and guidance. That integrated tree has not repeated the full gate.

## Implementation record

Definitions remain with their owners. Shared parse reports now live in
`src/parse-reports.x`. Driver errors, warnings, and progress have distinct
names. Component definitions followed the upstream move into `src/components/`.
All existing catalogue bodies retain their reporting construction; substantial
inline construction now has local definitions or typed helpers.

The compiler catalogue migration checked 341 existing bodies against their
originals after reversing explicit-site substitutions. All matched. A paired
translation produced 50 C/header files: 40 were byte-identical; the others
include changed source metadata and extracted construction. Driver paired
translation produced 16 files: 15 were identical and one differed only in three
private helper names. These comparisons do not claim whole-tree byte parity.
The component worker passed 33 existing fixtures without expectation changes.
The final integrated publication proof is recorded by `gate-state` and
`land-dev`; the comparisons above are focused evidence, not that proof.

Two component constraints preserve existing behavior: generated linked-meta
copies consume exported macros from their owners, and `dynamic_unary` keeps
its direct diagnostic because operation discovery does not expand macros.
The native duplicate warning uses a typed local helper because its nested
String join did not type-check after macro extraction. No generator changes,
message changes, or new checks were introduced to bypass these constraints.

The survey retained generic reporting boundaries, pass-through messages,
typed protocol/cycle helpers, native failure floors, short structured raises,
simple driver literal errors, and generated script exception rendering.
Full per-owner evidence is in `.context/report-normalization/coverage.md`.

## Plan review

- Existing detection establishes the error condition. Existing reporters own
  location resolution, severity, storage, recovery, and termination. The
  migration adds no consumer checks of those facts.
- Reuse reporting APIs, formatting helpers, typed meta helpers, and ordinary
  include visibility. Remove obsolete names and any duplicated definition
  whose shared ownership is established. Add no registry, installer, cache,
  representation, traversal, or forwarding layer.
- Local static macros, shared direct includes, scoped construction, and typed
  functions are existing x2c forms. The source remains organized around its
  owners rather than a new reporting framework.
- No new validator, dedicated diagnostic, negative fixture, or recurring
  process is proposed. Existing checks and bounded comparisons establish
  preservation of deliberate public behavior.
