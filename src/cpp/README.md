# C preprocessing

This module supplies optional C macro expansion for existing C compatibility.
`--cpp` enables expansion and conditional evaluation before parsing; ordinary
x2c builds do not use the engine. Explicit native REPL macro processing also
uses it. Module and meta discovery read authored x2c syntax without this pass.
The language rules are in
[Preprocessing](../../docs/src/reference/language.md#preprocessing).

Start with `cpp.x`, which defines the `Cpp` state, then `expand.x`, whose
`Compiler.expand_macros` runs the pass over a scanned token array.

## Files

| File | Responsibility |
| --- | --- |
| [cpp.x](cpp.x) | Defines the preprocessor state, its macro table and open groups, and the tokens of an expansion. |
| [macros.x](macros.x) | Applies `#define`, `#undef`, and `#include`, and reads `-D` and `-U`. |
| [conditions.x](conditions.x) | Opens, changes, and closes conditional groups and evaluates `#if` expressions. |
| [expand.x](expand.x) | Expands macro uses with substitution, `#`, `##`, and rescanning, and records each expansion. |

## Related code

[preprocess.x](../preprocess.x) hides the arms this module decides C never
takes and reads the directives before each form.
[Collect](../collect/README.md) threads the state through a file's segments
and records each file's exported macros in its entry.

[Source guide](../README.md)
