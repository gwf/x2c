# Translation state and shared services

This module holds the state of a translation unit and the operations shared by
declaration collection and full parsing. Related compiler instances share unit
identities and registries while keeping their own parse state.

Start with `compiler.x` and `lifecycle.x`, then [full
parsing](parsing/parse.x). The [parsing](parsing/README.md) and [declaration
production](declarations/README.md) directories are members of this same
module.

## Files

| File | Responsibility |
| --- | --- |
| [compiler.x](compiler.x) | Defines Compiler, pending declarations, source/module records, shared names, and other translation records. |
| [lifecycle.x](lifecycle.x) | Creates compiler instances, initializes tables, transfers unit state, routes child diagnostics, and releases unit meta bindings. |
| [names.x](names.x) | Allocates private emitted names and semantic identities for anonymous aggregates. |
| [binding-facts.x](binding-facts.x) | Reads emitted binding names and maintains optional-reference presence facts across paths and branches. |
| [literal-cache.x](literal-cache.x) | Interns constant values and cons cells into the unit cache, leaving dynamic values for runtime construction. |
| [patterns.x](patterns.x) | Recovers Match pattern values, identifies static patterns, discovers binders, and builds capture declarations. |
| [pending.x](pending.x) | Queues generated support declarations and file initialization, with checkpoint and restore operations. |
| [source-files.x](source-files.x) | Reads through SourceView, resolves canonical and portable paths, and records translation dependencies. |
| [source-locations.x](source-locations.x) | Records AST origins and declaration/reference ranges for diagnostics and inspection. |

## Related code

[symtab/symtab.x](../symtab/symtab.x) owns symbol tables, [sourceview.x](../sourceview.x)
supplies source bytes, and [diagnostics.x](../diagnostics.x) stores reports.
[Collect](../collect/README.md) walks sources; [parse](../parse/README.md)
implements shared grammar and binding.

[Source guide](../README.md)
