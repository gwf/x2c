# Package macro exports

> Status: done 2026-09-25 in cc94e05f. A direct public `.xmacro` import
> in the package entry is the export; one consumer `import "name";` supplies
> declarations, native meta targets, and the selected macro pack.

## Result

A package author may publish a macro pack beside its ordinary package API:

```x2c
// packages/shapes/src/shapes.x, above #pragma private
$(import "shapes.xmacro")
```

The consumer writes only `import "shapes";`. That import exposes the pack's
macros at this source position, after selecting the package's meta module or
linked extension. The author can keep implementation macros private by
importing them below `#pragma private` or from another package source file.
An explicit consumer `$(import ...)` continues to work, including without a
package import. Macro names retain their declared spelling; `as` and `with`
still affect package names, not macro names. Imports of a package by its own
sources are not re-exported.

The entry's direct, public `.xmacro` imports are the opt-in. Merely adding
`src/shapes.xmacro` is not: a previously absent optional file has no current
consumer dependency, so an incremental build could skip translation when it
appears. The authored import changes the tracked entry and makes the pack a
tracked dependency through the existing macro-import path. It also keeps
packages that have no export declaration unchanged.

## Spike evidence

- `Compiler.parse_import_declaration` collects the package before registering
  its alias. `Compiler.collect_package` selects its meta module and merges
  declarations; it intentionally does not merge macro definitions.
- `$(import "file.xmacro")` already runs in shallow collection and full parse,
  caches and deduplicates definitions, tracks the file in the depfile, and
  reports macro collisions and import cycles. Runtime forms contributed by
  its `meta` declarations go through `Compiler.meta_defs`.
- A throwaway package under `/tmp/x2c-package-macro-spike.WeIWUc` showed that
  `import "demo";` alone declines `$demo.plus1(7)`; an explicit import of
  `demo.xmacro` translates to `return 7 + 1;`; a second explicit import still
  succeeds. The pack's `meta int demo_helper(int)` also emitted a reached
  runtime helper when its macro used it. Placing `$(import "demo.xmacro")` in
  the package entry did not expose the macro to the consumer today.
- C* is the only current package with `src/<name>.xmacro`. Its examples use
  that pack directly, often without importing its runtime package. Preserve
  that macro-only path; do not require a package build for it.

These are focused translation and source observations, not a prototype of
the proposed export implementation or a whole-tree validation.

## Implementation boundary

1. During collection of a package entry, retain its direct `.xmacro` import
   paths from public segments as ordered export effects in that entry's
   existing process/interface record. A private or nested package import
   contributes no export. Do not scan file names or introduce a second macro
   registry.
2. After `collect_package` and alias registration at a consumer's import,
   replay those effects through the existing macro-import operation at the
   import token. It must run in both shallow collection and full parse, and
   append any imported runtime `meta` definitions to the same `meta_defs`
   path as explicit `$(import ...)`.
3. Keep canonical-path deduplication, source order, collision diagnostics,
   cycle reporting, translation dependencies, and package-module selection
   in their present owners. Check a package entry that imports its own pack
   during its build does not publish the pack twice to a consumer.
4. Update the package, macro, and language-reference chapters. Show a small
   package with a macro calling a native meta function and one consumer
   import; retain the separately documented explicit macro-only route.
5. Review and fix the authored diff for duplicate ownership and unnecessary
   checks, then run focused translation fixtures and the required final gate.

## Focused validation

Use one fixture package with a native meta function and a public `.xmacro`
import. Check cold collection and cached replay; a macro use after the
package import, a use before it, an `as` alias, two imports, an explicit
import of the same pack, a changed pack invalidating the consumer, and a
package without an export. A macro pack that contributes a reachable runtime
`meta` definition exercises `meta_defs`. Reuse the existing collision and
cycle fixtures; add a package-specific negative fixture only if the existing
diagnostic path misses a real wrong binding. Check C*'s macro-only examples
and its runtime-package consumers separately.

## Plan review

- The package entry and `#pragma private` already establish source position
  and public visibility; the consumer must not rescan a directory to infer
  them. The existing macro importer owns deduplication, collisions, cycles,
  Lisp state, and dependency tracking, so consumers should not recheck them.
- Reuse package collection's ordered entry record and the macro-import
  operation. The only new record is the public export path needed across
  cached collection; no registry, loader, or macro naming rule is added.
- The author writes one ordinary import in the package entry and the
  consumer writes one ordinary package import. No new language syntax or
  declaration representation is needed.
- No new validator or dedicated diagnostic is proposed. Existing macro
  collision, cycle, missing-file, and package errors protect the same public
  behavior. A focused fixture must show the effect reaches the right unit.
