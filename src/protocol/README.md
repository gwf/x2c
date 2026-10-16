# Protocol declarations and conformance

This module parses protocols and resolves what each adoption must provide. It
presents completed conformance to the lowering code that writes adapters and
descriptors.

Read `protocol.x`, `declarations.x`, `registry.x`, and `resolution.x` first.
Follow a selected member through `lookup.x` and a completed conformance through
`adapters.x`.

## Files

| File | Responsibility |
| --- | --- |
| [protocol.x](protocol.x) | Introduces protocol processing and assembles its members. |
| [declarations.x](declarations.x) | Parses protocol definitions and bodyless adoptions, including associated types and member templates. |
| [registry.x](registry.x) | Stores protocol and adoption rows, visibility, ownership, locations, and representations. |
| [resolution.x](resolution.x) | Matches conformance signatures and type variables and records requirements and member status. |
| [lookup.x](lookup.x) | Finds adopted members, resolves generated ownership and collisions, and supplies conformance inspection. |
| [adapters.x](adapters.x) | Presents native aliases or conform forms and prepares descriptor, default, and thunk information. |
| [call-helpers.x](call-helpers.x) | Generates forwarding wrappers, update helpers, and wrappers that discard selected temporary arguments. |

## Related code

[Protocol adapters](../components/protocol-adapters.x) writes bodies from the
resolved conform forms. [operator-ledger.x](../operator-ledger.x) maps
operators to protocol members. [Expressions](../expressions/README.md) selects
these operations at call sites.

[Source guide](../README.md)
