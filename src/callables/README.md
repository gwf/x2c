# Callable values and callbacks

This module turns functions and function pointers into callable values. It also
generates the adapters needed when x2c values cross a native callback boundary.

Start with `callables.x`, then follow `values.x` into `adapters.x`. For a C
callback conversion, start with `callbacks.x`.

## Files

| File | Responsibility |
| --- | --- |
| [callables.x](callables.x) | Declares the callable-lowering module and its dependencies. |
| [adapters.x](adapters.x) | Reads arguments through the FuncAdapter convention, converts parameters, calls the target, and boxes its result. |
| [values.x](values.x) | Lifts functions and function pointers into Func values, including captured pointer contexts and inline bridges. |
| [callbacks.x](callbacks.x) | Checks typed callback conversions and generates helpers for native functions and lambda arguments. |

## Related code

[Lambda functions](../components/lambda-functions.x) supplies lambda bodies.
[Adapter memoization](../adapter-memo.x) reuses generated helpers. The runtime
calling convention is in [lib/func.x](../../lib/func.x).

[Source guide](../README.md)
