# Declarations, types, and binding

This module parses declarations, types, declarators, and functions. It also
binds canonical syntax constructed by macros through the same operations used
for source syntax.

Start with `parse.x` and `units.x`, then follow declarations through
`declarations.x`, `declarators.x`, `types.x`, and `functions.x`. For
macro-produced syntax, start with `binding.x`.

## Files

| File | Responsibility |
| --- | --- |
| [parse.x](parse.x) | Declares shared diagnostics and assembles the module. |
| [units.x](units.x) | Dispatches top-level forms, imports, meta declarations, and interactive submissions; binds generated declaration bundles and aliases. |
| [declarations.x](declarations.x) | Parses declarations and typedefs, handles destructuring and initializers, and binds declarations in context. |
| [declarators.x](declarators.x) | Parses pointers, arrays, parameters, method names, and identifiers; installs bindings and completes template declarators. |
| [types.x](types.x) | Parses storage, qualifiers, attributes, type specifiers, fields, named types, and enumerators. |
| [functions.x](functions.x) | Parses and binds function definitions and bodies, including expression bodies and lifecycle signatures. |
| [binding.x](binding.x) | Binds constructed syntax by context, including statements, blocks, branches, loops, exception forms, match arms, and callable bodies. |
| [placement.x](placement.x) | Tracks enclosing constructs, places generated code, and completes managed declaration initializers. |

## Related code

[Compiler parsing](../compiler/parsing/README.md) owns unit iteration and
recovery. [statements.x](../statements.x) parses statements,
[expressions](../expressions/README.md) resolves expressions, and
[initializers](../initializers/README.md) handles brace initializers. Shared
diagnostics live in [parse-reports.x](../parse-reports.x).

[Source guide](../README.md)
