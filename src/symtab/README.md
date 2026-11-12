# Symbol table

This module holds one compiler's declarations as a stack of scopes searched
from inner to outer; its lowest scopes hold file-scope declarations. It issues
the binding identity of each declared name, resolves typedef chains and
aggregate fields, and records which file-scope names are private. A `SymTxn`
stages the rows a macro binds, so a failed expansion leaves the table as it
was.

Read `symtab.x` first for `Sym`, its diagnostics, and the type grammar of its
rows. Follow a declaration through `declarations.x` and `bindings.x`, and a
macro expansion through `transactions.x`.

## Files

| File | Responsibility |
| --- | --- |
| [symtab.x](symtab.x) | Defines `Sym` and its undo rows, symbol diagnostics, and the row type grammar, and assembles the members. |
| [scopes.x](scopes.x) | Creates and resets the table, pushes and pops scopes, presents symbol maps, and keeps local macros. |
| [bindings.x](bindings.x) | Defines aliases, globals, and enumerators, and looks up current and global bindings. |
| [declarations.x](declarations.x) | Declares names, issues binding identities, tracks file statics, and checks reserved spellings. |
| [namespaces.x](namespaces.x) | Records declaration privacy and spells module, package, and imported names. |
| [types.x](types.x) | Resolves typedef chains, local and numeric types, Var tags, and aggregate fields. |
| [transactions.x](transactions.x) | Records each semantic write so a transaction can commit or roll it back. |

## Related code

[Compiler](../compiler/README.md) owns the table through its translation
state. [Expressions](../expressions/README.md) reads bindings and types at
use sites.

[Source guide](../README.md)
