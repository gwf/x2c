# Shipped syntax rules

These files implement x2c language features using compile-time macros and
rewrite rules. Each file is an independent translation unit. The compiler
loads their declarations into its prelude and links their native meta code
into the compiler.

Most rules lower parsed, bound forms. Some also participate in resolution:
[delegate-members.x](delegate-members.x) searches delegate fields when a member
call cannot be resolved directly. The rules use ordinary compiler operations
to build replacement syntax, preserve evaluation order, and place supporting
declarations. The surrounding compiler parses and resolves the resulting forms.

For a small example, start with [raise.x](raise.x), then read
[string-switch.x](string-switch.x) or [interpolation.x](interpolation.x).
[try-catch.x](try-catch.x) and [lambda-functions.x](lambda-functions.x) show
features that need generated support and lifetime handling.

## Files

| File | Responsibility |
| --- | --- |
| [bracket-access.x](bracket-access.x) | Lowers indexed reads, stores, and updates through collection helpers or indexing members, evaluating operands once in order. |
| [delegate-members.x](delegate-members.x) | Searches delegate fields for members and supplies the access paths used by resolution. |
| [destructuring.x](destructuring.x) | Lowers flat List destructuring into extraction and binding operations. |
| [interpolation.x](interpolation.x) | Joins String text and insertion values in evaluation order. |
| [lambda-functions.x](lambda-functions.x) | Builds lambda functions, captured contexts, Func adapters, and shared reference cells. |
| [collection-literals.x](collection-literals.x) | Constructs Array and Map values from literal entries. |
| [pattern-match.x](pattern-match.x) | Lowers match statements, pattern tests, and capture bindings. |
| [dynamic-operators.x](dynamic-operators.x) | Lowers operations involving dynamic values through the runtime's operator functions. |
| [printf-format.x](printf-format.x) | Adapts Var arguments to printf-family conversions when the format is known. |
| [protocol-adapters.x](protocol-adapters.x) | Writes adapter functions and Var descriptors from resolved conformance forms. |
| [raise.x](raise.x) | Converts raise codes and payload values and checks detail types. |
| [string-switch.x](string-switch.x) | Lowers switches on Strings while preserving case and default behavior. |
| [try-catch.x](try-catch.x) | Lowers try, catch, and finally into exception handling and cleanup forms. |

## Related code

[grammar.x](../grammar.x) defines the source-form templates these rules match.
[Transform](../transform/README.md) invokes lowering and normalizes its results.
[Meta SDK](../meta-sdk/README.md) supplies compile-time compiler operations.

Some features have an earlier semantic owner: [lambdas.x](../lambdas.x)
resolves captures, [protocol](../protocol/README.md) resolves conformance,
and [expressions](../expressions/README.md) resolves calls and operators.
[collect/walk.x](../collect/walk.x) lists the prelude files. The generated
[linked-meta.x](../linked-meta.x) contains their compiled-in meta definitions.

[Source guide](../README.md)
