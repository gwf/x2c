# AST normalization

This module normalizes typed AST forms for C emission. It applies the shipped
lowering rules, preserves evaluation order, and integrates generated support
and cleanup.

Start with `transform.x` and `traversal.x`. Follow expressions into
`expressions.x`, operators into `operators.x`, and ordered construction into
`literals.x`.

## Files

| File | Responsibility |
| --- | --- |
| [transform.x](transform.x) | Introduces the normalizer, dependencies, and shared lowering diagnostics. |
| [traversal.x](traversal.x) | Drives normalization, dispatches lowering rules, handles functions and sequences, and integrates support and cleanup. |
| [expressions.x](expressions.x) | Rewrites typed expressions, including lambdas, indexing, slicing, casts, declarations, returns, and calls. |
| [operators.x](operators.x) | Lowers truth tests, dynamic operators, assignments, comparisons, and protocol-based updates. |
| [conditions.x](conditions.x) | Lowers `if` conditions and predicate values that contain pattern tests, placing each successful continuation inside the scope of its captures. |
| [literals.x](literals.x) | Lowers collection, List, and interpolation forms and preserves evaluation order for construction, calls, and raises. |

## Related code

[Components](../components/README.md) implements the shipped syntax rules.
[Callables](../callables/README.md) handles callable conversions,
[cleanup](../cleanup/README.md) handles exits, and [emit](../emit/README.md)
consumes the result.

[Source guide](../README.md)
