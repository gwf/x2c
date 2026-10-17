# Brace initializers

This module converts brace initializer values for the subobjects selected by C
initialization order. It can describe selections whose array bounds or native
layouts are only known to the C compiler.

Read `initializers.x`, then follow `convert_initializer` in `conversion.x`
into `initializer_rows` in `subobjects.x`.

## Files

| File | Responsibility |
| --- | --- |
| [initializers.x](initializers.x) | Assembles brace-initializer handling and defines its boundary with ordinary value conversion. |
| [subobjects.x](subobjects.x) | Walks fields, indices, designators, and native bounds to determine each value's destination and selection conditions. |
| [conversion.x](conversion.x) | Converts selected values, handles alternative native destinations and compound literals, and supplies needed native types. |

## Related code

[Expression conversions](../expressions/conversions.x) converts individual
values. [parse/declarations.x](../parse/declarations.x) binds declaration
initializers. [type.x](../type.x) and [symtab/symtab.x](../symtab/symtab.x) describe types
and fields.

[Source guide](../README.md)
