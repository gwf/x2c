# Landing-page gallery refresh

> Status: Implemented locally and verified, 2026-11-10.
> Publication to dev authorized; final validation in progress. Prior checkpoint: `4423d85f`.
> Reference: local site-update exploration at `522d8552d`.

## Layout

Adopt site-update's full-section-width carousel for Love, Power, and Magic.
Place each section heading and short introduction above its gallery. Within
its desktop slides, put explanatory copy on the left and code on the right,
using the reference's 0.8fr / 1.35fr proportions. Stack copy and code on phones;
keep code overflow inside the code panel. Reuse FeatureCarousel and the
existing example panels, controls, anchors, and detail links. Scope layout
changes to these three sections. Preserve the opening, header, and packages.

The larger copy area should explain the task, the useful language property,
and what to notice in the code. Do not fill it merely because space exists.
Keep navigation labels lowercase and retain existing section-title styling.

## Proposed lineup

### Love: ordinary work becomes pleasant

1. one value: current `examples/love/values.x`.
2. two kinds: reference `examples/love/two-kinds.x`, with a clearer equality
   demonstration before mutation and a corrected Map-key comment.
3. collections: reference `examples/love/collections.x`, replacing separate
   List, Array, and Map gallery slides.
4. literals: current `examples/love/literals.x`.
5. text: reference `examples/love/strings.x`, its concrete HTTP/path task.
6. names: current `examples/love/symbols.x`.
7. loops: reference `examples/love/loops.x`, focused on iteration and
   destructuring; omit its unrelated keyword-argument coda.
8. files: current `examples/love/files.x`.
9. memory: current `examples/power/scopes.x`, emphasizing scoped cleanup.

Leave your C and tools out. The opening already establishes C compatibility.
Preserve omitted standalone examples in the Examples browser.

### Power: small operations work together

1. classes: reference `examples/power/classes.x`.
2. protocols: reference `examples/power/protocols.x`, practical Set operations.
3. indexing: current `examples/power/indexing.x`, a document-word index.
4. matching: current `examples/power/match.x`, structural patterns and rebuilding.
5. iterators: current `examples/power/iterators.x`, lazy composition.
6. records: current `examples/power/derive.x`, generated record operations.
7. errors: current `examples/power/exceptions.x`, cleanup and caller handling.
8. packages: current `examples/power/imports.x`, PCRE2 under a chosen namespace.
9. threads: reference `examples/power/channels.x`, producer/consumer work.
10. typed collections: current `examples/power/generics.x`.

Use one matching slide, explaining capture and reconstruction together.
Keep Notes/service in Examples rather than expanding the homepage into an
application walkthrough. Do not copy historical speed benchmark claims.

### Magic: programs can change programs

1. compile time: current `examples/magic/compile-time.x`.
2. macros: current `examples/magic/macros.x`.
3. decorators: current `examples/magic/decorators.x`.
4. keywords: current `examples/magic/keywords.x`.
5. reflection: reference `examples/magic/fields.x`.
6. autodiff: current `packages/autodiff/examples/autodiff.x`; use the existing
   gallery excerpt so the full executable's assertion machinery stays hidden.
7. runtime Lisp: current `examples/magic/runtime.x`.

Leave self-host out. Omit reference code-is-data because it repeats Power's
simplifier; let the actual macro examples demonstrate syntax transformation.

## Correctness findings

- Current files and exceptions examples preserve source-relative fixture
  lookup. Current scopes preserves optional accounting guards. Do not replace
  these with older reference versions.
- Arrays can be equal in contents but distinct in identity. Demonstrate that
  before mutating one array in two-kinds. Boxed Array/Map keys use identity;
  remove the claim that all equal values are one object. See
  `docs/src/guide/collections.md`, Equality and identity are explicit.
- Remove the claim that every collection stores Vars: packed typed
  collections are a counterexample.
- Explain nested literal structure without promising identical memory layout.
- Describe protocols' actual `typedef Map Set`, not a Map inside a class.
- Describe reflection as the technique behind generated operations, not the
  claim that current `$derive` is twelve lines.
- Describe meta functions' demonstrated runtime facilities without promising
  the entire runtime in every compile-time execution mode.
- The suspected Atom/Symbol issue in reference loops did not reproduce:
  its unmodified program compiled and ran with the expected output.

## Verification completed

`make build-safe` passed in the dev worktree. Built and ran 19 current-dev
examples through `examples/check.sh check --one`, checking each tally for zero
failures and comparing checked-in stdout. These include all current-dev
standalone selections above, plus collection-indexing, threads, and
meta-functions as comparison candidates.

Translated, compiled, and ran eight reference examples against the current
dev compiler/runtime: two-kinds, collections, strings, loops, classes,
protocols, channels, and fields. All matched reference manifest stdout and
emitted no stderr. Their original source was read from the reference worktree;
no reference source was copied into the working tree.

Built and ran the current PCRE2 imports and autodiff examples using existing
package targets. Both matched checked-in expected output. Total: 29 passing
example executions. Logs: `debug/gallery-bootstrap.log`,
`debug/gallery-pcre2.log`, `debug/gallery-autodiff.log`, individual
`examples/build/*/log`, and temporary `/tmp/x2c-gallery-review/results.json`.
Compilation success does not validate prose claims; the corrections above
come from reviewing code and documented contracts.

## Implementation verification

After approval, update authoritative examples, slide Markdown, and gallery
mapping together; retain existing routes or redirects where slide names change.
Keep standalone examples available even when removed from the homepage.
Run changed examples and existing gallery correspondence checks. Build the
site and run its built-link check. Verify gallery navigation, selected slides,
and code overflow at desktop and phone widths in the browser. No new gate.

## Plan review

The compiler, runtime, docs, and existing executable fixtures own language
behavior; website copy does not add validation or reinterpret that contract.
Reuse the existing carousel, Markdown rendering, syntax highlighting, and
example links. Replace the narrow gallery layout and repetitive type slides;
add no carousel engine, cache, or parallel content representation. New source
examples come from reference programs already tested against current dev.
Keep source changes small and idiomatic. There are no proposed validators,
dedicated diagnostics, negative fixtures, or recurring process requirements.

## Implementation evidence

Selected 9 Love, 10 Power, and 7 Magic slides. Retained omitted slides in the
Examples catalog and mapped old homepage anchors to related selected slides.
Imported seven standalone sources with expected outputs; updated text and loops
and added the equality assertion. All nine focused example checks passed, as
did all 44 gallery mappings. Retained the existing energy-gradient autodiff
excerpt rather than replacing it with the longer three-mode program; built
and ran energy-gradient against its checked-in output successfully.

Site build and built-link checks passed. Browser checks exercised all 26 tabs
at 375px without horizontal page overflow; desktop galleries span 1098px at
a 1280px viewport. Existing carousel and package layout remain shared owners.
