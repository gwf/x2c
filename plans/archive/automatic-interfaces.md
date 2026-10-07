# Ordinary source modules and automatic interfaces

> Status: done
> Implemented and validated on 2026-10-06 at 6938c195. Gary requested local
> retention after validation; no remote branch was changed. The source started
> at origin/dev cb67de5ec658af4f9108433f24f062543c6087d4.

## Result

An ordinary .x file holds runtime and compile-time declarations. Including
that file installs its public interface. Static declarations belong to their
implementation; non-static declarations are public. Types required by public
interfaces are public, including their complete definitions when required.
Authors need neither visibility pragmas, macro packs, nor exported import lists.

Non-static standalone type declarations and constants remain public. Public
roots include objects, functions, method owners, macros, aliases, protocols,
and dependencies of bodies emitted into the header. Implementation bodies
remain with their provider. Authored opaque forwards retain their hidden layout.
Static type declarations can be promoted when a public interface needs them.

File-scope macros and keyword aliases are public by default. Static macro and
static keyword keep helpers local. Static typedef and static class express
implementation types. Generated default methods inherit their type's storage.
Static meta functions are local in both phases; a public meta function can
call the provider's private helpers. Lexically local definitions remain local.

Top-level Lisp contributions are public unless prefixed with static. Public
forms run once per consuming translation session, at the include position.
Retained declaration outputs replay without running their producer twice.
Ordinary free names in macro expansions retain use-site binding semantics.

## Implementation

1. Extend existing macro and type productions with static storage. Retain
   completed canonical macro definitions and alias snapshots in ordered
   source rows. Freeze literal cache keys rather than provider-local IDs.
2. Replace pragma filtering with declaration storage and type dependency
   selection. Use the same public type selection for interface metadata and
   generated headers. Preserve source-order emission and ordinary forwards.
3. Replay public compile-time rows when collection or full parsing reaches an
   include. Reuse ordinary include identity, cycle handling, and dependency
   invalidation. Record public Lisp contributions with their source context.
4. Advertise public bodied meta functions with their provider path. Bind them
   lazily through the existing helper's provider table. Keep provider-private
   helpers and state inside that provider; link public native meta functions
   across provider units normally.
5. Build the new capability before migrating callers. Convert macro-only
   modules into ordinary .x files, combine single-owner packs with their
   source where appropriate, and replace pack imports with includes. Preserve
   private source helpers through static declarations. Replace pragma/private
   authoring and remove export-import paths, copied meta bodies, and restricted
   pack parsing after the migration.
6. Update source tools and the book for ordinary source interfaces. Regenerate
   derived bootstrap, runtime prelude, and documentation through their owners.
7. Review the completed authored and generated diffs, fix issues, then run
   publication validation and deliver to the resolved destination.

Independent implementation workers own macros.x, the meta provider modules,
and collect.x/generate.x respectively. The orchestrator owns parser/state
integration, migration, tools, documentation, final review, and delivery.

## Validation

Use focused compiler fixtures and temporary programs to check:

- included public macros, alias snapshots, private helpers, source order,
  repeat includes, cycles, and cold/interface-cache equivalence;
- nested and interpolated literal templates across independent literal caches;
- static type privacy, public type dependency promotion, opaque handles,
  method owners, and aggregate field reflection;
- provider-owned meta calls, private helper/state access, cross-provider calls,
  and translation-session isolation;
- Lisp effect execution once, source context, and declaration-production replay;
- migrated compiler/runtime self-hosting, executable examples, book samples,
  and affected package clients.

The existing final publication command owns bootstrap convergence and full
required checks. No new recurring gate or validation process is added.

## Plan review

The parser already establishes declaration and template shapes. Existing Sym
records establish storage, bindings, and type structure. Consumers reuse those
facts; no origin authentication or parallel syntax validator is added.

Canonical macrodef snapshots, source-node rows, freeze/thaw, include collection,
type promotion, forwards, and project helper tables are reused. Provider paths
are necessary to select the defining helper table. Literal cache keys are
necessary because numeric IDs are private to one Compiler. A per-session effect
set prevents observable duplicate top-level Lisp effects between collection and
full parsing.

The completed migration deletes special macro-pack ownership, exported import
paths, import provenance withholding, copied imported meta runtime bodies,
weak-definition emission, and helper localization for duplicate pack bodies.
Shared libraries remain shared .x modules; this does not duplicate their text
into every caller.

The resulting source uses ordinary declarations, static storage, includes,
canonical Lists, and existing compiler operations. Fixtures protect observable
publication, binding, cache relocation, native linkage, and effect behavior.
No additional defensive validator or diagnostic-only fixture is planned.

## Evidence and boundaries

The full existing publication gate passed at the validated implementation:
256 bootstrap/stage C/H files converge, and 384 cold C/H/interface files
match stage 1. All 1,094 compiler fixtures and 2,450 artifacts pass. All
941 native tests pass with 24,994 assertions. Documentation, 101 executable
book samples, commands, and all CLI, protocol, header, and meta probes pass.
The reviewed generated artifacts are committed; the local branch is
codex/automatic-interfaces.

The advisory performance snapshot was not run because the host had sustained
unrelated CPU load from VS Code's C++ service. Optional full Cstar verification
was unavailable without its prepared libcstar.a; its reduced native control
passed. These limitations do not weaken the required correctness evidence.

Ordinary includes retain declaration maps, macro snapshots, public Lisp
forms, provider meta advertisements, and source positions. Runtime bodies
remain compiled from their defining .x modules. Build inputs must include
those providers when their runtime declarations are used.

The new interface rules preserve opaque pointers. Public inline bodies that
access an opaque handle's fields require its layout, so their typed syntax
must participate in the same type selection as public signatures.

Cold included providers bind public inline bodies after the include graph is
collected. They use the completed signatures without parsing active ancestors
again. Compile-time effects retain their original source positions.

A native enum cycle that depends on a later object-like #define was already
unsupported at the pinned baseline. The baseline generated an included
header with an unknown by-value enum type. Moving the enum before that
include instead encounters the unavailable #define. This change does not
add preprocessing evaluation or promise to support that cycle. The reduced
baseline and candidate evidence is retained in
/tmp/x2c-publication-failure/type-cycle-native-state/baseline/.

Editing `_selector_middles` in the shipped selector producer also fails cold
on origin/dev 0bba0aed, before this migration. The unchanged consumer compiles
and prints `1 1`; the edited producer fails its compile-time address result.
The migration does not add a helper bootstrap phase for that existing cycle.
Comparable source, fresh-cache logs, and native control evidence are retained
in /tmp/x2c-legacy-selector-baseline/.
