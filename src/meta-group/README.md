# Compile-time groups

This module selects and emits the native code in a translation unit's
compile-time group. It can write that group for a project helper or build and
bind it for an in-process session.

Read `meta-group.x`, `selection.x`, `emission.x`, and `staging.x` in that
order. Use `loaded.x` when following access to a loaded program.

## Files

| File | Responsibility |
| --- | --- |
| [meta-group.x](meta-group.x) | Defines group configuration and shared toolchain state. |
| [selection.x](selection.x) | Collects meta functions, determines reachable group contents, preserves order, and checks unresolved calls. |
| [emission.x](emission.x) | Lowers group contents through the ordinary backend and creates exported targets and reset entries. |
| [staging.x](staging.x) | Writes groups for project helpers or builds and binds native groups for in-process sessions. |
| [toolchain.x](toolchain.x) | Resolves the meta C compiler and runtime headers and runs native compilation. |
| [loaded.x](loaded.x) | Exposes loaded entry points and generates accessors and snapshots for globals and aggregates. |

## Related code

[meta-project.x](../meta-project.x) orchestrates project helper builds. [Meta
native](../meta-native/README.md) binds and invokes targets.
[Generate](../generate/README.md) provides the ordinary backend.

[Source guide](../README.md)
