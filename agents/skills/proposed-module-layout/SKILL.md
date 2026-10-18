---
name: proposed-module-layout
description: >-
  Propose how an x2c source file or related files should become one module
  with responsibility-based component files. Read source and callers, assign
  symbol ownership, and identify private statics that must become module
  declarations. Use for module layout and decomposition proposals; this skill
  does not implement the split or change compiler semantics.
---

# Proposed Module Layout

Produce a concrete module layout that a developer can judge from the proposed
files, their operations, and their private interfaces. Keep the analysis yours;
do not ask the user to fill out operation descriptions or hunt through a
sequence of evidence screens. Source stays unchanged. Save the proposal and
its reproducible assignment manifest under `.context/` unless the user requests
another destination. Implementation is a separate task.

## Establish the source and semantics

Record the repository revision, analyzed files, and any uncommitted source
changes. Use source and graph data from the same snapshot. Canonical graph keys
identify functions; display names alone are not identities. Do not reuse a
saved proposal after source changes without reconciling membership and evidence.

Read the book's [module blocks](../../../docs/src/reference/language.md#module-blocks)
section, which owns the `static` and `module` storage classes and the
compile-time declarations that keep their own rules, and the relevant
implementation. Distinguish documented behavior from
what the current compiler supports; check the current status of known defects
before treating a candidate as implementable. Do not preserve an implementation
bug as a layout rule or repair the compiler during this analysis.

Design for one module entry and its component files, flattened into one
translation unit. A public declaration retains its external interface unless
a separate, evidence-backed visibility reduction is proposed. Source uses short
names; never generate or insert compiler file prefixes in the proposal.

Respect companion-directory and nested-member rules, declaration order, and
include resolution. Functions collected ahead of bodies do not imply that
objects, types, macros, or initialization can be reordered freely. Record
naming hazards such as path-prefix collisions and duplicate adopted class
short names separately from responsibility choices.

## Read operations and dependency ownership

Read every public operation's body and relevant callers. Record its concrete
operation, state or object, phase or lifecycle, source section, and evidence
locations. Names and proximity are clues, not proof. Use descriptions such as
"assemble module source" or "publish header declarations", not "utilities".

Trace private calls and function-value references recursively, including cycles
and shared helpers. Count each symbol once. Inspect private types, macros,
file-local state, initialization, and shutdown uses as well as calls. For each
state symbol, name its actual readers and writers. A common data format or
shutdown ordering contract is not by itself a same-file constraint.

The existing graph exporter and Partition's
[source analysis](../../../tools/partition/analysis.py), which runs the local
`codex` CLI over the captured source, can supply
identities, call edges, and an operation inventory. Inspect the source behind
claims. Partition's old static keep-together components describe constraints
for separate translation units; they are not indivisible component files under
the new module storage semantics. Do not use its old physical partition result
as the answer.

Keep unresolved and indirect references explicit. An unknown graph endpoint
must retain its original spelling and source evidence; it is neither an absent
dependency nor grounds to discard the useful remainder of the proposal. Source
inspection can establish references missing from the graph. State what remains
unknown and which assignments or visibility decisions depend on it.

## Build responsibilities, then assign components

Group operations by a concrete task, state owner, or lifecycle. Assign every
function exactly once to a component, including attached helpers and synthetic
initialization records where present. A shared helper has one owner and several
consumers; do not duplicate it into all consumers. Assign types and state to
owners too, recording dependencies from every component that uses them.

For each private symbol:

- If all uses stay in its owning component, retain `static`.
- If uses cross component boundaries within the module, propose `module`
  and list the consumers and reason for its owner.
- If ownership is unclear, retain an explicit unresolved assignment rather
  than inventing a helper-only destination. A helper-only component needs a
  coherent responsibility, execution entry paths, and accessible symbols.

When responsibilities share a private dependency, show the exact paths or
accesses. Choose between keeping the responsibilities together and giving the
shared symbol an owner with a module-private interface. Do not silently make
helpers public. Public call edges may cross components; eliminating those
edges alone is not a reason to merge responsibilities. Likewise, do not pull
an API entry point toward its callers merely because that reduces the cut.
Keep its implementation responsibility and private dependency chain visible.

Combine small components by meaning, not equal sizes. Record the prior
component IDs and concrete reason for each merge. A large coherent component
is a valid result. Do not force eight groups, balanced files, singleton targets,
or standalone compilation.

## Show the useful result first

Lead with the proposed directory tree and a short table: component name,
responsibility, public operations, owned helpers/state, and private interface
shared with other components. Explain the most important boundary choices
with exact symbols. Put full membership and evidence after the arrangement.

Report separately:

- Existing public calls crossing components.
- Private calls and function-value references crossing components, and the
  exact `static` declarations proposed to become `module`.
- Shared types, state, macros, and ordering dependencies.
- Opportunities to reduce public visibility, with all known consumers checked;
  zero-cut-change moves can still improve visibility.
- Unresolved references and constraints affecting confidence or feasibility.

Use distinct-caller counts separately from call-site counts. Cut changes are
supporting evidence, not a score that proves design quality. If anchor scores
help explain a boundary, use E = distinct external-file callers and D = distinct
same-file static callees reachable through static-only directed paths, excluding
the starting function. Cycles count once. The raw score is log(1+E)*log(1+D);
state the comparison population when normalizing. Shared helpers need their
other consumers shown. Anchoring estimates attachment, not a placement veto.

Label results explicitly as module-component candidates, separate
translation-unit candidates only when separately assessed, or unresolved.
Do not claim a source extraction compiled when only the layout was analyzed.

## Keep the proposal reproducible

Save a versioned JSON manifest with a format version, source revision and
working-source fingerprints, scope, component IDs/paths/responsibilities,
canonical function memberships, symbol owners, proposed storage changes with
consumers and reasons, source evidence, unresolved references, and merge history.
Use a small companion Markdown proposal for the human-facing arrangement.
Do not require Partition's old manifest schema to express the new semantics.

Check exact-once membership against the source inventory. Recompute crossings
from assignments, verify every known cross-component private reference has an
explicit storage decision, and check non-function dependencies separately.
Keep uncertain decisions visible rather than claiming a completed extraction.
No compiler rebuild or publication gate is required merely to propose a layout.
