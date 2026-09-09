> Status: reference
> D1 design completed on 2026-09-09. Retain selective declaration collection
> and synthesized external prototypes for this milestone. Broad eager
> discovery and inferred owner-header insertion are rejected below; this is a
> completed design decision, not an unassigned implementation deferral.

# Declaration discovery and generated declarations

## Result and decision

Preserve forward references, source-ordered includes, and compile-time Lisp
behavior while emitting complete native declarations. The existing two-stage
frontend is the implementation: collect the declarations needed to parse a
unit, then bind and type its full source against that map. Do not replace it
with one eager expansion pass or infer new C header includes from declaration
locations.

The completed D1 code change retains `_Noreturn` and excludes external
prototypes already supplied by the unit's own generated header. No further
compiler implementation is recommended for broad discovery in this milestone.
There is no measured benefit that would justify changing evaluation order or
adding declaration ownership/cache machinery. Existing header contribution
reuse remains the place to avoid repeated include collection.

## Existing owners and their facts

- `Frontend.start/collect` in `src/frontend.x` configures one unit and seeds
  collection with a copy of the runtime symbol snapshot. `ParsedUnit.parse`
  passes the resulting globals to `Compiler.full_parse`.
- `Compiler.collect_symbols` and `_file` in `src/collect.x` walk source and
  includes in source order. `_parse_segment` reads cumulative globals and
  writes only the current segment's overlay. `_replay_cached` replays these
  overlays and include edges in the same order, once per visited file. It
  also carries dependencies, function definitions, and generated-name counts.
  A cached header must not depend on unit-local declarations before its first
  include; introducing such dependence would break existing reuse.
- `Compiler.shallow_parse_overlay` in `src/compiler.x` uses ordinary
  declaration parsing and the existing symbol owner. Function bodies and
  ordinary initializers are skipped. `_shallow_parse_unit_macro` uses the
  ordinary macro parser under `SymTxn`, commits declaration effects, and
  restores generated-name counters because full parsing expands again.
- `Compiler.parse_macro_lisp_shallow` in `src/macros.x` executes imports but
  consumes other top-level Lisp without evaluating it. Imported `Unit` macros
  qualify for shallow expansion; local ones qualify only when their template
  contains `protocol` or `adopt` rows. Imports share the unit's Lisp session.
  `full_parse` resets macro/import maps and parses the source in order;
  these operations are not a promise that arbitrary Lisp is pure or that
  every expansion is interchangeable between phases.
- `Sym` owns declaration types and binding identities. Forward identifier
  references can acquire a binding before a later declaration completes it.
  A source spelling alone is not evidence that two declarations are the same.
- `_header_and_source` in `src/generate.x` owns emitted visibility and header
  contents. `_static_prototypes` sees both partitions; the external collector
  accepts only a resolved global function binding absent from their local
  declaration set, deduplicates it, and calls `Type.declaration_ast`.
  `_partition_function` retains `_Noreturn` for bodies that never return.

## Concrete evidence

Probes used the current `builds/0/x2c`; sources were outside the checkout.
`debug/d1-discovery-design.log` records these results:

1. A function calls a later ordinary function without a source prototype.
   Translation, native compilation, and execution succeed and print `42`:

   ```x2c
   int caller(void) { return later(); }
   int later(void) { return 42; }
   ```

2. An included header declares `Choice` as `String`, then includes a second
   header declaring it as `List`. A consumer calling `value.len()` emits
   `List_len`; cold single-unit and warm batch C output are byte-identical.
   This probes collection merge order, not native acceptance of conflicting
   C typedefs. The existing header-cache suite separately covers owner-first,
   consumer-first, serial/parallel, and artifact replay cases.
3. An imported `Unit` macro defines a named function whose body uses a value
   from an imported `.xlisp` file. A caller before the invocation compiles
   and prints `42`. The same local macro using an earlier ordinary
   `$(def local_answer 40)` also prints `42`, with the caller either before
   or after the invocation. These are compatible paths to preserve, not a
   reason to expand all local macros during collection.
4. `$(d1_unbound_top_level_probe)` followed by an ordinary function passes
   `translate --dump-cpp-symbols` with exit 0, but full translation exits 1
   with `compile-time Lisp evaluation failed`. The existing phase boundary
   deliberately postpones that evaluation. Evidence:
   `debug/d1-lisp-boundary.log`.

The earlier D1 native owner/consumer proof preserves `_Noreturn` under
`-Werror=return-type`; the header-cache probe verifies omission of a duplicate
prototype supplied by the generated primary header. Evidence:
`debug/d1-native-after.log` and `debug/d1-header-cache.log`.

## Reuse boundaries and rejected alternatives

**Keep the current selective collection schedule.** Moving arbitrary Lisp or
all macro expansion into discovery changes when definitions, imports, errors,
and external effects occur. Reusing an expanded, bound AST in full parsing
would additionally need to preserve caller scopes, binding identity, macro
state, generated names, and transactions. A declaration map is not a reusable
full expansion. No second parser, speculative full expansion, or general AST
memoization is warranted.

**Keep source-requested includes and primary-header suppression.** A source
location does not establish that a generated owner header is available, that
it publishes a declaration with its complete native properties, or that adding
it preserves preprocessor and include order. C declarations can come from a
snapshot, macro expansion, native header, package, or merged include segment.
Do not replace a synthesized prototype merely because one of those producers
has a filename. Doing so would also add a build dependency on a generated
header that a single-unit translation need not produce.

**Reuse facts only at their current lifetime and identity.** Included
contributions already belong to the header cache; final binding/type facts
belong to the unit; emitted header membership belongs to partitioning. The
narrow D1 fix uses that final membership directly. If profiling later finds
one of these existing traversals materially expensive, improve that owner
and compare exact output before considering additional retained state.
This is a condition for a future independent optimization, not remaining work
for the present design assignment.

## Delivery and validation

Deliver this design alongside the completed D1 implementation and retain the
current language semantics. No additional public decision, compiler change,
recurring gate, or broad validation requirement is introduced. Review this
record and the authored package documentation, then use the parent plan's
existing final-tree publication command.

## Plan review

Existing parser, symbol, transaction, cache, and partition owners establish
all facts used above; consumers do not reconstruct scopes or validate AST
provenance. The recommendation reuses those owners and adds no helper,
representation, traversal, cache, validator, diagnostic, or permanent negative
fixture. It rejects a second expansion/discovery framework and unsupported
inferred includes. The temporary failing Lisp probe establishes the deliberate
evaluation boundary; it does not introduce earlier rejection. The completed
D1 source uses ordinary `Match`, binding identity, and `Type.declaration_ast`.
