# Literal syntax

This module parses literal forms into typed expressions and patterns. Stable
List cells and String segments use the compiler's literal cache; dynamic parts
remain ordered runtime work.

Start with `literals.x` and `atoms.x`, then choose quotations, strings, or
collections. Read `payloads.x` alongside exception syntax.

## Files

| File | Responsibility |
| --- | --- |
| [literals.x](literals.x) | Assembles the literal parsers and describes the cache/runtime boundary. |
| [atoms.x](atoms.x) | Parses scalar, character, Atom, and Symbol literals and checks numeric ranges and binder spellings. |
| [quotation.x](quotation.x) | Parses quoted Lists, insertions, splices, reader forms, and typed Match patterns; caches stable cells. |
| [strings.x](strings.x) | Splits interpolated strings into ordered text and insertion segments and decodes escapes and continuations. |
| [collections.x](collections.x) | Parses Array, Map, and SymbolSet literals, including map entries and duplicate SymbolSet members. |
| [payloads.x](payloads.x) | Parses raise payloads and catch-filter literals, including bare Symbol codes and detail keys. |

## Related code

[Literal caching](../compiler/literal-cache.x) owns cached values.
[lambdas.x](../lambdas.x) parses lambdas. [Collection
literals](../components/collection-literals.x),
[interpolation](../components/interpolation.x),
[try/catch](../components/try-catch.x), and [raise](../components/raise.x)
perform lowering.

[Source guide](../README.md)
