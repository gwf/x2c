# Reading macro applications

These files recognize macro applications in each source position and turn their
arguments into capture rows. For decorators, they also parse and capture the
target before expansion.

Read `invocations.x`, `recognition.x`, and `captures.x` first. Then follow
statement/declaration applications into `targets.x` or expression applications
into `expressions.x`.

## Files

| File | Responsibility |
| --- | --- |
| [invocations.x](invocations.x) | Assembles invocation recognition, capture, target, and expression handling. |
| [recognition.x](recognition.x) | Publishes definitions and aliases, records/replays compile-time effects, looks up applications, and determines permitted positions. |
| [captures.x](captures.x) | Parses arguments by hole kind, retains source spans, handles scalar/sequence captures, and forwards captured syntax. |
| [targets.x](targets.x) | Builds applications in statement, declaration, and unit positions and stages decorated targets in a semantic transaction. |
| [expressions.x](expressions.x) | Distinguishes Macro names, explicit meta calls, template calls, expression macros, and expression decorators. |

## Related code

These files belong to [macros](../README.md). [Definition
reading](../definitions/reading.x) sets the signature kinds.
[expansion.x](../expansion.x) applies captures,
[parse/binding.x](../../parse/binding.x) binds applications, and [expression
resolution](../../expressions/resolution.x) resolves expression results.

[Source guide](../../README.md)
