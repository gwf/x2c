# Public-first function reading order

> Status: active, foundation implemented and validated, 2026-10-27.
> Gary authorized the skill, documentation, and four-example check-in, then
> a local conversion campaign. Optional lint is deferred. The foundation
> commits precede campaign edits; campaign work remains local for review.

## Result and scope

Establish a reusable skill for reviewing or revising function reading order.
Publish the skill, its canonical style guidance, and the reviewed examples
before starting a separate local conversion campaign across all existing
hand-authored x2c files in src/, lib/, and examples/. Preserve behavior,
function bodies, signatures, visibility, module membership, and runtime ABI.
Only function order and their documentation and section comments change.
Keep the campaign local for review; publication needs Gary's later direction.

The current tracked inventory is 186 src, 128 lib, and 105 example .x/.xp
files. These are inventory counts, not claims about files needing edits.
Exclude generated lib/x2c.x from authored edits and identify other generated
inputs by their producers. Inventory module members as well as entry units.
Non-x2c supporting example files remain part of examples but need no function
reordering. Account for every inventoried file as changed, already conformant,
generated, no movable functions, or constrained with a specific reason.

## Reading-order rule

FI-4 in agents/x2c-code-standard.md owns the rule. Other guides and the skill
link to it rather than defining competing rules.

1. Preserve the required prologue and source-order boundaries. Order actual
   source-written function definitions, not prototypes, macro invocations,
   generated helpers, protocol declarations, or protocol adoptions.
2. Use caller-to-callee edges between functions defined in the same physical
   file. Resolve names through the compiler in the containing translation
   unit. Cross-file dependencies explain context but do not authorize moves
   between files. Include resolved function-value references, callbacks, and
   implicit method/operator dependencies where available; report unresolved
   dependencies rather than guessing targets or claiming graph completeness.
3. Collapse strongly connected components. A recursive component has no
   strict internal topological order. Present its central operation first,
   then its continuation and conceptual steps. Keep related explanations
   close, as in regex.x's _run followed by _resume.
4. Emit public definitions first in caller-before-callee topological order.
   Account for paths through private functions when ordering public functions.
   A component containing both visibility tiers is still one recursive unit
   for analysis; public-first placement takes precedence inside that cycle.
5. Visit public functions in that order. For each, collect reachable private
   definitions not already emitted. Emit that group in caller-before-callee
   component order. Shared helpers belong to the first group that reaches
   them; later groups may call upward. Do not duplicate helpers.
6. Treat module-visible functions as private implementation for this rule,
   preserving their storage class. After public groups, use remaining
   module-visible definitions as roots, then remaining private components.
   In an all-private file, start from components with no incoming local call
   edges. Use existing order for unrelated roots and remaining disconnected
   components; do not infer dead code from missing callers.
7. Use existing source order to break unconstrained ties by default. Adjust
   ties and recursive interiors for clear conceptual steps. Broad conformance
   accepts these alternatives; it does not demand one exact permutation.
8. Place section comments at the operations they introduce. Keep precise
   representation comments beside types and state. Preserve function-attached
   documentation. Prefer readable sections over a comment for every graph
   node. Group size guidance remains FI-5, not an excuse to split functions.

Only public definitions must precede private definitions within a safely
reorderable region. Keep preprocessing branches, includes, macro/keyword/alias
availability, top-level script statements, initialization declarations,
registration-sensitive meta/decorator operations, and location-sensitive
expansions intact. Types and state retain their relative order and precede
uses that require them. Check __LINE__-style observations and source excerpts
in examples when movement could change output. A real source-order conflict
gets a narrow exception and explanation, not new forward declarations,
visibility changes, rewritten bodies, or a silent skip.

A single public root still produces one private group: this rule does not
promise to fix translation.x's pipeline/worker separation. Readability within
that group remains an editorial task under the stated ordering constraints.

## Delivery 1: skill and canonical guidance

1. Add agents/skills/order-x2c-functions/SKILL.md, following skill-creator.
   Provide read-only check and authorized revise modes. The check reports
   misplaced groups, shared-helper crossings, recursive groups, and material
   boundaries. The revise mode moves complete function spans, carries their
   documentation, and repairs section comments. Neither mode authorizes body
   cleanup, renaming, module splits, or visibility changes.
2. Use existing compiler-backed graph datasets/snapshots and source tokens
   for discovery and identity. Query the containing unit for module members.
   Reuse commands/graph and query-x2c-project rather than writing another
   parser or treating the temporary regex-based scripts from this experiment
   as production tooling. Exact source spans must come from tokens and be
   checked against the authored declaration before a move. Missing spans
   require a bounded manual move or an explicit unresolved report.
   Begin with an agent-assisted workflow, not a repository-wide automatic
   rewriter. Add a helper only for demonstrated repeated mechanical work;
   it must consume compiler facts rather than recover bindings from text.
3. Replace FI-4's current lifecycle/public-entry-last wording with the rule
   above. Reconcile FI-3's prologue wording and FI-5's section guidance.
   Update the FI-4 worked example in agents/x2c-coding-style-guide.md with
   two public roots, shared helpers, and a recursive group. Check
   agents/x2c-code-organization-guide.md for contradictory guidance.
4. Add precise routing in agents/README.md. Update beautify-x2c-source to use
   the ordering skill for its file-order step, and clean-x2c-source to route
   order-only requests there. The existing .agents/skills and .claude/skills
   symlinks expose the canonical skill; create no provider-specific copies.
5. Review the four existing experiments against the final rule. Keep their
   unchanged-body evidence, correct any unsafe movement, and repair section
   comments where needed. Retain a readable recursive parser/matcher order
   in regex.x. Do not silently replace its reviewed order with a tie-breaker.
6. Exercise skill discovery and both modes on a multi-root file, a recursive
   file, a module member, an indentation/script example, and a nonmatching
   body-cleanup request. These are bounded implementation checks, not a new
   recurring test requirement. A second check should accept the revised file
   without proposing cosmetic reshuffling.
7. Review and fix the authored diff. Follow existing publication requirements
   for the combined source/documentation change, including initial safe build
   because this worktree has no builds/0 compiler. Do not hand-edit bootstrap
   or demand byte-identical whole generated files: declaration order and line
   locations can legitimately change. Verify unchanged definitions and relevant
   executable behavior. Use tools/gate-state.py ensure agent-pr-check for
   publication. Gary has selected a local foundation check-in followed by
   the local campaign; a local commit does not require publication. Integrate
   and check in Delivery 1 before the local campaign. No new gate or repeated per-file full build is added.

## Delivery 2: local corpus campaign

Start from the checked-in Delivery 1 revision. Refresh the tracked inventory;
use tools/sources.sh for containing entry units, not as the complete list of
physical files. Use examples/manifest.txt and the examples Makefile to find
existing checks and intentional tutorial sequencing. Include support modules,
non-manifest source, .xp, and #pragma indent files in the disposition list.

Work in bounded batches of related units. Begin with small single-file units,
then module members, then meta/macro-heavy files and examples. Retain the
existing style if already broadly conformant. Keep source-order-sensitive
regions unchanged when necessary and record the exact reason. Every file
gets assessed; lack of compiler coverage is unresolved work, not conformance.

Preserve function definitions byte-for-byte, including internal comments;
compare declaration/type/state content and order outside moved functions,
allowing only the selected section-comment changes. Review attached-comment
boundaries. Recompute graph facts as needed and check visibility, membership,
signatures, and recursive groups. Do not use unrestricted textual replacement.

For each coherent batch, use focused translation and existing executable
checks appropriate to its units. Run make examples for the curated example
checks and use the manifest's build/probe/manual dispositions for the others.
Do not claim interactive or dependency-dependent examples were executed when
only translated. Missing dependencies do not authorize installation. Review
any generated-output differences as ordering/location changes or investigate
unexpected behavior; never rebaseline tests to make reordering pass.

Keep the campaign changes local, with private checkpoint commits permitted.
Use a small coverage record in .context/ listing changed, already conformant,
and outstanding files and reasons. Review the final authored diff and fix
findings before final local verification. Publication, if later requested,
uses the existing combined gate and ordinary performance-policy applicability,
not a new function-order gate. Parallel implementation, if chosen, uses
orchestrate-x2c-work and isolated workers with disjoint files; workers never
publish. Do not launch a second campaign before the skill/guidance delivery.

## Optional lint candidate

Keep lint out of the critical path for the skill and campaign. Assess a
single opt-in style candidate, provisionally function-reading-order, owned
by FI-4. Existing commands/lint supports --rule CODE and --all, style
candidates, suppressions, and compiler-backed declaration analysis. Reuse
those interfaces; do not add a compiler warning, default build lint, an
editor dependency, or a recurring gate. Preserve experimental distribution.

The candidate should identify concrete visibility/group/component-order
problems with function names and locations. It must tolerate shared-helper
upward calls, arbitrary order inside recursive components, valid tie choices,
and source-order barriers. Human theme quality and section-comment meaning
remain review judgments. Do not compare against one exact canonical sort.

First check whether existing parsed facts and token locations can support
these distinctions cheaply. If useful, implement the narrow candidate as a
separate optional follow-up and add bounded linter fixtures for accepted and
reported arrangements. Do not reuse --fix's current whole-generated-file
identity contract for reorderings: changes to declaration order violate that
contract. No automatic reorder fix is selected. The structured-findings plan
remains independent; do not add its unfinished compiler interface as a
prerequisite. If false positives or required machinery outweigh the benefit,
retain the skill's read-only check and report why lint is deferred.

## Execution readiness

No architectural blocker was found in the inspected examples, style owners,
source graph documentation, or lint entry points. Full-corpus feasibility has
not been proved. Immediate follow-up can implement Delivery 1, using the
existing build setup and validation workflow. Source-order barriers and
unresolved graph edges need per-file assessment during the campaign.

The foundation is checked in locally before campaign work starts. Remote
publication remains outside the current local delivery. Optional lint is
deferred and does not block either delivery.

Foundation evidence: make build-safe and make commands passed; digest and regex
suites passed 12 tests and 194 assertions; the editor helper-cleanup probe and
compiler graph extraction passed. Independent review checked 126 unchanged
function definitions and unchanged nonfunction declaration tokens. Skill
metadata, routing, links, module-member/script/indentation forward checks, and
broad-conformance review passed. Source moves required ordinary generated
API reference refresh through make doc-generate; make doc-check passed.
The CLI boundary probe passed for translation, build/run/script, manifests,
and state. The semantic editor tests exercise definition and hover locations
through both direct and compatibility transports. Final
command results are retained under debug/function-order-*.

## Plan review

The compiler establishes resolved function identity, visibility, module
membership, and recorded call/reference relationships. Consumers reuse those
facts rather than reconstruct bindings. Graph absence does not establish
absence of callbacks, transformed calls, or semantic ordering constraints.
The move check establishes unchanged authored definitions; existing builds
and examples establish their tested behavior. Neither replaces the other.

Reuse the source graph, compiler tokens, existing lint findings and selection,
root publication workflow, and skill discovery symlinks. Replace contradictory
FI-4 guidance instead of adding a parallel style standard. The new skill
owns one bounded activity; it adds no parser, cache, source representation,
compiler semantics, or caller obligation. The resulting x2c remains ordinary
source with existing functions and representations, not new runtime machinery.

No new runtime validator or compiler diagnostic is proposed. The optional
lint candidate protects a deliberate style convention only and remains an
advisory review signal. Its bounded fixtures cover real grouping mistakes
and accepted exceptions; they protect no new language restriction. No new
recurring validation, commit requirement, or build step is proposed.
