# Collection and full-parse orchestration

These files drive shallow declaration collection and full parsing over the same
compiler state. They also handle script assembly, token movement, and facts
about completed top-level forms.

Read `parsing.x`, `parse.x`, `collection.x`, and `tokens.x` in that order.
`scripts.x` explains script policy; `definitions.x` explains checks spanning
multiple forms.

## Files

| File | Responsibility |
| --- | --- |
| [parsing.x](parsing.x) | Groups parsing members and declares shared token, script, and definition diagnostics. |
| [tokens.x](tokens.x) | Initializes tokenization, retags keywords, scans conditionals, advances tokens, tracks braces, and records completion positions. |
| [collection.x](collection.x) | Runs shallow parsing, publishes declarations and inline bodies, and skips unneeded bodies. |
| [parse.x](parse.x) | Resets full-parse state, processes top-level forms, recovers after malformed forms, and finishes the AST. |
| [scripts.x](scripts.x) | Separates script declarations and statements, assembles implicit main, and checks conflicts with explicit main and script locals. |
| [definitions.x](definitions.x) | Records definitions, prototype contracts, spans, and static-initializer dependencies; reports incompatible or duplicate definitions. |

## Related code

The parent [compiler module](../README.md) supplies state.
[parse/units.x](../../parse/units.x) handles individual top-level forms;
[statements.x](../../statements.x) handles statement grammar.
[collect/walk.x](../../collect/walk.x) chooses source segments for collection.

[Source guide](../../README.md)
