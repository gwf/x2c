---
name: order-x2c-functions
description: >-
  Check or revise function reading order in hand-authored x2c files under
  src/, lib/, or examples/. Put public functions first and group private
  dependencies by their first public user, preserving function definitions.
  Use for reading-order reviews, public-first ordering, and order-only
  source campaigns; use beautify-x2c-source for changes inside functions.
---

# Order x2c functions

Make a file readable from its public operations down through their private
implementation. [FI-4 in the code standard](../../x2c-code-standard.md)
owns the ordering rule; FI-3 owns the prologue and FI-5 owns sections.
Check requests are read-only. Revise only when authorized, moving whole
function definitions with their documentation and adjusting section comments.
Preserve bodies, signatures, storage classes, and module membership.

## Establish the file and dependencies

Read the complete file and nearest instructions. Identify its containing
translation unit, its source-written definitions, and the source-order
boundaries below. Inspect a nearby working example; `lib/regex.x` shows
multiple public operations, shared helpers, and mutually recursive groups.

Use compiler-resolved identities and source tokens for mechanical discovery.
[Source graph datasets and snapshots](../../../commands/graph/README.md)
provide calls, references, visibility, defining files, and source order.
For snapshots, use [query-x2c-project](../query-x2c-project/SKILL.md) to check
freshness and inspect occurrence evidence. Query module members through their
entry unit; assess ordering within each physical file. Cross-file calls do
not authorize moving definitions between files or widening visibility.

Read the source at reported edges. Include resolved callbacks, function-value
references, and implicit method or operator dependencies where available.
Do not infer bindings from matching spellings or invent indirect targets.
Graph omissions remain coverage gaps: parsed direct calls do not describe
all later lowering, native code, or callback behavior. For a small file,
source inspection can resolve dependencies directly; name any unresolved
case rather than calling the file conformant by default.

## Check the reading order

Build an outline with one line per function. Apply FI-4's public ordering,
recursive components, and per-public private groups. An outline need not be
a saved artifact for a single file. Preserve readable existing tie choices;
a different valid topological order is not a finding.

Look for public definitions buried among private implementation, private
groups separated without a source-order reason, and callers unnecessarily
below callees within a group. Shared helpers already emitted by an earlier
group may be called upward. A recursive component has no strict internal
sort: put its central operation first, then explain continuations and related
steps together. Do not expand that flexibility into unrelated body cleanup.

Check section comments against the resulting boundaries. Keep representation
explanations beside their types and state; place algorithm explanations with
the operations they introduce. Avoid a heading for every graph node.

Report concrete misplaced functions or sections, accepted recursive/shared
helper placements, and material source-order constraints. State unresolved
coverage separately. Accept a broadly conformant file without reshuffling
independent functions to match one canonical permutation.

## Revise safely

Use exact authored function spans, including documentation attached to each
function. Derive automated spans from source tokens and check them against
the declaration. If locations are unavailable, make a bounded manual move
or report the unresolved move. Never use unrestricted textual replacement
or a regex parser to recover function identity, binding, or body boundaries.
Prototypes, protocol declarations and adoptions, macro invocations, and
generated helpers are not source-written function definitions to reorder.

Keep includes, preprocessor branches, macro/keyword/alias availability,
top-level script statements, initializer declarations, and registration-
sensitive meta/decorator operations in their required order. Types and state
retain their relative order and precede uses that require them. Check
location-sensitive expansions and examples that observe source positions.
Apply the rule within safe regions when a boundary prevents whole-file
public-first order. Explain that exception; do not add forward declarations,
change visibility, or rewrite a function to force the sort.

Preserve script shebangs and indentation syntax, including `.xp` and
`#pragma indent` files. Treat an example's intentional teaching sequence as
context; preserve any sequence with a demonstrated semantic or presentation
constraint and identify it in the result. Generated files remain owned by
their producers, including `lib/x2c.x`.

## Verify and report

Compare before and after: each function definition, including its internal
comments, must remain byte-for-byte unchanged. Check attached documentation
and the content and relative order of declarations outside moved functions;
only authorized section-comment edits may differ. Review the complete file,
not just the diff. Run `git diff --check`, then use the relevant existing
translation or executable checks for the coherent batch. A text comparison
proves unchanged definitions, not unchanged behavior across source-order
boundaries. Whole generated C/H files may change order or line locations;
review those differences rather than requiring byte identity or rebaselining.

For a campaign, inventory physical source files as well as entry units and
use `examples/manifest.txt` for existing example checks. Record each file as
changed, already conformant, generated, no movable functions, or constrained
with a reason. Missing analysis or validation remains unresolved work.
Batch verification; do not add a per-file full build or recurring gate.

Report the groups changed, any exceptions, unchanged-definition evidence,
checks run, and remaining coverage. Root [delivery instructions](../../../AGENTS.md)
apply; a local-only request stays local. Optional lint is independent of
this skill and is not required to check or revise a file.
