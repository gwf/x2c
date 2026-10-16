# Compile-time declaration production

These files connect declaration-producing compile-time code to collection and
full parsing. They retain produced declarations, carry syntax between compiler
contexts, and select defaults after the file's declarations are known.

Read `declarations.x`, `production.x`, `portable-syntax.x`, and `defaults.x` in
that order.

## Files

| File | Responsibility |
| --- | --- |
| [declarations.x](declarations.x) | Assembles declaration production and declares forwarded-constructor diagnostics. |
| [production.x](production.x) | Runs source Lisp effects and unit declaration macros during collection, retains their results, and replays them during full parsing. |
| [portable-syntax.x](portable-syntax.x) | Freezes tokens, origins, bindings, cached literals, and macro syntax into portable rows, then restores them in another context. |
| [defaults.x](defaults.x) | Selects offered declarations whose names remain available and constructs forwarded parent constructors. |

## Related code

These files belong to the [compiler module](../README.md).
[Macros](../../macros/README.md) expands producers,
[parse/units.x](../../parse/units.x) binds their results, and
[collect/interfaces.x](../../collect/interfaces.x) stores portable
declarations.

[Source guide](../../README.md)
