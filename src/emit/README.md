# C token emission

This module turns normalized AST forms into C token lists. It handles C syntax
and precedence. Generate assembles the files; format prints the resulting
tokens.

Start with `emit.x` and `dispatch.x`. Then follow the kind of form into
expressions, declarations, or initialization.

## Files

| File | Responsibility |
| --- | --- |
| [emit.x](emit.x) | Defines emission state and precedence constants. |
| [dispatch.x](dispatch.x) | Traverses normalized forms and assembles tokens for statements, control flow, directives, and shared syntax. |
| [expressions.x](expressions.x) | Emits expressions, calls, identifiers, operators, and literals with the required parentheses. |
| [declarations.x](declarations.x) | Emits types, declarators, parameters, functions, aggregates, enums, and native aliases. |
| [initialization.x](initialization.x) | Emits initializer choices and runtime local-static storage, including captured source initializers. |

## Related code

[Transform](../transform/README.md) supplies normalized forms.
[Generate](../generate/README.md) assembles files. [format.x](../format.x)
prints the token lists.

[Source guide](../README.md)
