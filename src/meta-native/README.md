# Native compile-time calls

This module binds and calls compiled meta functions. It connects definitions to
compiler-linked implementations, project helpers, or explicitly selected native
modules.

Start with `meta-native.x`, `functions.x`, and `calls.x`. For an external
target, follow `bindings.x` into `modules.x`. For a shipped definition, read
`linked.x`.

## Files

| File | Responsibility |
| --- | --- |
| [meta-native.x](meta-native.x) | Introduces native meta binding, process state, and diagnostics. |
| [functions.x](functions.x) | Installs bodied meta functions and helper/session stubs, including collected project advertisements. |
| [bindings.x](bindings.x) | Records bodyless native declarations, selects suppliers, checks signatures, and derives lifetime summaries. |
| [calls.x](calls.x) | Executes explicit meta calls and converts returned values into expressions or statements. |
| [modules.x](modules.x) | Loads selected native modules and package extensions, checks their stamps, and retains target tables. |
| [linked.x](linked.x) | Reuses compiler-linked definitions when provider text and signatures agree. |

## Related code

[Meta groups](../meta-group/README.md) emits and stages code.
[meta-helper-client.x](../meta-helper-client.x) calls project helpers.
[linked-meta.x](../linked-meta.x) is generated code containing compiler-linked
definitions.

[Source guide](../README.md)
