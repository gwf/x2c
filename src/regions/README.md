# Storage lifetime analysis

This module detects values that outlive their allocating storage. It analyzes
typed forms before lowering, tracking storage identities and function effects
rather than inserting executable cleanup.

Start with the model in `regions.x` and the entry points in `analysis.x`.
Follow `walk.x` into `values.x` and `flows.x`; consult `runtime.x` for known
library operations.

## Files

| File | Responsibility |
| --- | --- |
| [regions.x](regions.x) | Defines regions, acquired values, facts, analysis state, and the lifetime model. |
| [runtime.x](runtime.x) | Records known allocation, storage, free, scope, pool, and ownership effects. |
| [values.x](values.x) | Tracks storage identities, allocation owners, borrowed addresses, and expression/binding facts. |
| [walk.x](walk.x) | Applies lifetime effects, opens and closes regions, follows assignments, and detects ended-storage reads. |
| [flows.x](flows.x) | Checks escaping values against destination lifetimes and constructs findings. |
| [analysis.x](analysis.x) | Computes function summaries to a fixpoint and exposes ordinary, meta, and audit analysis. |

## Related code

[Transform](../transform/README.md) runs analysis before rewriting.
[Cleanup](../cleanup/README.md) inserts executable cleanup. Ordinary lifetime
findings are warnings; meta-function findings are errors.

[Source guide](../README.md)
