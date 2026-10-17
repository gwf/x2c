# Macros and compile-time Lisp

This module turns macro definitions and invocation captures into canonical
syntax, then binds that syntax where the invocation appears. It also manages
compile-time Lisp sessions, quoted code values, and registered rewrites.

Start with `macros.x`, then [definition reading](definitions/reading.x),
[stored templates](definitions/templates.x), [argument
capture](invocations/captures.x), and `expansion.x`. The nested
[definitions](definitions/README.md) and [invocations](invocations/README.md)
guides describe those parts.

## Files

| File | Responsibility |
| --- | --- |
| [macros.x](macros.x) | Assembles the macro subsystem, including definitions and invocations. |
| [diagnostics.x](diagnostics.x) | Declares macro diagnostics and adds definition, path, and Lisp-failure notes. |
| [expansion.x](expansion.x) | Matches captures, creates private names, fills templates, checks recursive expansion, and binds the result. |
| [lisp.x](lisp.x) | Creates Lisp sessions, imports and evaluates source forms, shares library sessions, and installs builtins and native operations. |
| [templates.x](templates.x) | Evaluates template slots and meta values, rebuilds decorated syntax, and lands quotations with their holes and private names. |
| [values.x](values.x) | Represents first-class Macro values, captures environments, handles patterns, and binds carried code and effects. |
| [rewrites.x](rewrites.x) | Registers and selects rewrite rules and binds/lowers replacements while retaining carried values and effects. |

## Related code

[parse/binding.x](../parse/binding.x) binds expansion output. [Meta
SDK](../meta-sdk/README.md) exposes compiler operations;
[meta-native](../meta-native/README.md) executes native meta code.
[lib/macrovalue/macrovalue.x](../../lib/macrovalue/macrovalue.x) defines Macro values.
`definitions/templates.x` builds stored templates; this directory's
`templates.x` evaluates and lands them.

[Source guide](../README.md)
