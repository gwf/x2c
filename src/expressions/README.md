# Expression parsing and resolution

This module parses expression grammar and resolves expression nodes into typed
operations. It selects calls, members, operators, and conversions before later
lowering.

Read `expressions.x`, `syntax.x`, and `resolution.x` first, then the
operation-specific member. Use `conversions.x` when following an incompatible
operand or assignment.

## Files

| File | Responsibility |
| --- | --- |
| [expressions.x](expressions.x) | Defines shared resolution state and printf metadata and assembles the module. |
| [syntax.x](syntax.x) | Parses precedence, assignments, casts, postfix forms, primary expressions, and composites. |
| [resolution.x](resolution.x) | Dispatches expression shapes, resolves deferred expressions and macro applications, and assigns resulting types. |
| [identifiers.x](identifiers.x) | Resolves names to bindings and types, handles lambda captures and template free names, and reads bound references. |
| [access.x](access.x) | Resolves indexing, slicing, fields, and methods; checks addressability and supplies postfix completion candidates. |
| [calls.x](calls.x) | Resolves calls and arguments, adapts receivers and Func calls, completes iterator chains, and extracts static printf formats. |
| [operators.x](operators.x) | Types unary, binary, postfix, and conditional operations and selects protocols and operand conversions. |
| [conversions.x](conversions.x) | Converts values, promotes strings, boxes/unboxes Var, adapts callable values, and checks reference/native crossings. |

## Related code

[type.x](../type.x) supplies semantic types, [symtab/symtab.x](../symtab/symtab.x) supplies
bindings, and [protocol](../protocol/README.md) selects protocol
implementations. Aggregate traversal belongs to
[initializers](../initializers/README.md). Diagnostics live in
[expressions-reports.x](../expressions-reports.x).

[Source guide](../README.md)
