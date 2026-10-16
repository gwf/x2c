# Generated files

This module assembles a translation unit's C header, source, and interface. It
preserves declaration order and visibility while arranging initialization and
publishing the output files.

Start with `generate.x` and `output.x`, then read `projection.x`. Follow
initialization and dependency placement as needed. `definitions.x` is the route
for source/API inspection.

## Files

| File | Responsibility |
| --- | --- |
| [generate.x](generate.x) | Defines the module and shared file-initialization state. |
| [output.x](output.x) | Coordinates generation, adds guards and preludes, formats output, and publishes files together. |
| [projection.x](projection.x) | Separates header and source declarations while preserving conditional groups and visibility. |
| [initialization.x](initialization.x) | Builds once-only file initialization, entry guards, protocol setup, and shutdown registration. |
| [dependencies.x](dependencies.x) | Places required declarations and prototypes, then positions delayed function bodies. |
| [definitions.x](definitions.x) | Extracts authored function and type definitions for --dump-definitions. |

## Related code

[Emit](../emit/README.md) creates C tokens and [format.x](../format.x) prints
them. [cache.x](../cache.x) supplies literal-cache initialization. Expression
lowering belongs to [transform](../transform/README.md).

[Source guide](../README.md)
