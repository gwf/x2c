# Project manifests and build plans

This module turns project manifests into dependency-ordered build requests. It
selects targets and profiles, expands sources, and leaves execution to the
build command.

Start with the records in `project.x`, then the orchestration in `planning.x`.
Read `manifest.x` for syntax and `sources.x` for file selection.

## Files

| File | Responsibility |
| --- | --- |
| [project.x](project.x) | Declares project, target, profile, dependency, and build-plan records. |
| [manifest.x](manifest.x) | Parses manifest sections and values, retaining source-line diagnostics. |
| [planning.x](planning.x) | Discovers manifests, selects targets and profiles, resolves dependencies, and constructs ordered requests. |
| [sources.x](sources.x) | Expands source patterns and exclusions in deterministic order, including source overlays. |

## Related code

[CLI](../cli/README.md) owns the request type. The [build
command](../../commands/build/build.x) executes those requests.
[sourceview.x](../sourceview.x) supplies source overlays.

[Source guide](../README.md)
