# Compiler (`src/`)

Use the [agent directory](../agents/README.md) for task routing and relevant
technical references; the [root instructions](../AGENTS.md) own publication.

The compiler should demonstrate idiomatic x2c. Use `match` and
`match_replace` templates for direct structural rewrites. For parser
productions, AST consumers, and transforms, read
[replacing manual AST walks with Match](../agents/replacing-manual-ast-walks-with-match.md)
for recursive descent, captures, output templates, and transform recursion.

The fixed-point transform driver relies on Lists created through `cons`
having stable structural identity. Keep identity-dependent behavior within
that verified List representation.
