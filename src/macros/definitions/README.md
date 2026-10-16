# Reading macro definitions

These files read macro definitions and quotations into their stored
representation. They record typed holes, construct capture patterns, and
determine the private names each application needs.

Read `definitions.x`, `reading.x`, and `templates.x` first. `slots.x` handles
holes; `quotations.x` handles quoted syntax and code values.

## Files

| File | Responsibility |
| --- | --- |
| [definitions.x](definitions.x) | Defines the Definition working record and assembles its members. |
| [reading.x](reading.x) | Parses headers, signatures, result/target categories, bodies, and using clauses; announces definitions before reading bodies. |
| [templates.x](templates.x) | Finishes stored templates, replaces local identities with binders, derives private names and invocation patterns, and publishes definitions. |
| [slots.x](slots.x) | Parses named holes, Lisp slots, and computed calls and checks their kinds and sequence positions. |
| [quotations.x](quotations.x) | Parses anonymous and typed quotations, captures referenced locals, and constructs syntax or typed code values. |

## Related code

These files belong to [macros](../README.md). [Invocation
captures](../invocations/captures.x) supplies arguments.
[expansion.x](../expansion.x) applies stored templates,
[templates.x](../templates.x) evaluates slots, and
[parse/binding.x](../../parse/binding.x) binds the result.

[Source guide](../../README.md)
