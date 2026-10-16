# Cleanup on control transfers

This module puts cleanup operations on paths that leave a region. It also
preserves the local storage that must survive exception landings.

Read `cleanup.x` and `transfers.x` first. Follow `defer.x` for finalizers,
`statics.x` for runtime initialization, and `preservation.x` for exception
storage.

## Files

| File | Responsibility |
| --- | --- |
| [cleanup.x](cleanup.x) | Defines cleanup regions and shared storage-preservation state. |
| [defer.x](defer.x) | Converts defer bodies into regions and builds finalizers with captured locals. |
| [statics.x](statics.x) | Finds runtime static initializers and protects their blocks against entering jumps. |
| [transfers.x](transfers.x) | Tracks region ancestry and inserts cleanup before returns, breaks, continues, and outgoing jumps. |
| [preservation.x](preservation.x) | Finds locals and pointees needed after exception landings, adding volatile or escaped storage. |

## Related code

[Transform](../transform/README.md) invokes cleanup lowering.
[Try/catch](../components/try-catch.x) supplies exception landing forms.
[Regions](../regions/README.md) analyzes lifetimes; it does not insert cleanup.

[Source guide](../README.md)
