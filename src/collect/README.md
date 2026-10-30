# Source and declaration collection

This module walks sources and includes in source order to collect visible
declarations. Cold walks, process-cache replay, and stored .xi interfaces
preserve the same ordering.

C macro expansion and macro-export replay run only for optional `--cpp`
translation or an explicit native REPL request. Ordinary collection keeps
directive text without constructing the expansion tables. Module and meta
discovery use authored syntax, including literal member paths.

Start with `collect.x` and `walk.x`, then read `cache.x` and `interfaces.x`.
Use `splice.x` for module files and `packages.x` for package imports.

## Files

| File | Responsibility |
| --- | --- |
| [collect.x](collect.x) | Defines collection state and shared diagnostics and assembles the module. |
| [walk.x](walk.x) | Walks the unit, prelude, directives, and includes; shallow-parses source segments and replays contributions in order. |
| [splice.x](splice.x) | Expands module member lists into one source text, retaining locations and per-file private-name prefixes. |
| [cache.x](cache.x) | Owns retained process-cache entries, canonical lookup roots, content hashes, and refresh/invalidation operations. |
| [interfaces.x](interfaces.x) | Locates, validates, reads, and writes .xi interfaces and their portable dependency and binding records. |
| [declarations.x](declarations.x) | Selects public declarations and types, supplies included function declarations, binds pending inline bodies, and records dependencies. |
| [packages.x](packages.x) | Locates package entries, collects exported surfaces, installs package names, and replays imports. |
| [providers.x](providers.x) | Validates linked meta providers and definitions and records their hashes, bindings, and types. |

## Related code

[Shallow parsing](../compiler/parsing/collection.x) handles grammar.
[preprocess.x](../preprocess.x) interprets directives,
[meta-native](../meta-native/README.md) runs native compile-time code, and
[sourceview.x](../sourceview.x) supplies bytes.

[Source guide](../README.md)
