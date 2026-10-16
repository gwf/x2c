# Compile-time compiler operations

This module answers syntax, type, source, and diagnostic queries made by
compile-time code. The active MetaContext connects each operation to the
expansion that requested it.

Read `meta-sdk.x` and `context.x` first. Then choose `syntax.x`, `types.x`, or
`sources.x` according to the operation you are tracing.

## Files

| File | Responsibility |
| --- | --- |
| [meta-sdk.x](meta-sdk.x) | Establishes the SDK module and its use of the active MetaContext. |
| [context.x](context.x) | Provides invocation locations, expansion access, diagnostics, and rejected-operation reports. |
| [types.x](types.x) | Answers type resolution, layout, field, protocol, parameter, and result queries. |
| [syntax.x](syntax.x) | Inspects and constructs bound syntax, converts expressions, creates names, and places generated code. |
| [rewrites.x](rewrites.x) | Converts rewrite and after-initialization registrations into compiler rule forms. |
| [sources.x](sources.x) | Recovers captured source text, describes source locations, and reads embedded text. |
| [primitives.x](primitives.x) | Installs supporting Lisp primitives for symbol sets, linked hashes, and native-target queries. |

## Related code

[lib/meta.x](../../lib/meta.x) declares the public operations.
[Macros](../macros/README.md) establishes the expansion context.
[Compiler](../compiler/README.md) and [parse](../parse/README.md) perform the
underlying binding and parsing work.

[Source guide](../README.md)
