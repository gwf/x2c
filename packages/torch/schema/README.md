# Pinned operator schema

`native_functions-2.10.0.yaml` is the second pinned artifact of this package,
beside the libtorch archive in `dependency.json`. It is the input
`tools/gen-ops.py` reads to produce `generated/xt_ops.h`,
`generated/xt_ops.cpp`, and `src/torch-ops.x`.

| field | value |
| --- | --- |
| source | `https://raw.githubusercontent.com/pytorch/pytorch/v2.10.0/aten/src/ATen/native/native_functions.yaml` |
| tag | `v2.10.0` |
| sha256 | `29c55ccb397ea85a392eed7e176813a781dde1925bfc0f6c0a1fda635a421a83` |
| bytes | 618114 |

Verify with:

```sh
shasum -a 256 packages/torch/schema/native_functions-2.10.0.yaml
```

A libtorch bump replaces this file at the matching source tag and reruns
`make -C packages/torch gen-ops`; the generated files are outputs and are
never hand-edited.

## Tier 1, as measured

Counts come from `make gen-ops` over this file after the hand-written unit
reached its M1 surface, not from an estimate. The generated C compiles to
1194 exported `xt_*` functions and the generated x2c unit translates to 1182
wrappers.

| outcome | operators |
| --- | --- |
| entries parsed | 2666 |
| selected | 1193 |
| private name (`_` prefix) | 585 |
| `out=` overload | 538 |
| `*_backward*` | 147 |
| `Dimname` argument | 74 |
| x2c name already taken and no free overload suffix | 53 |
| out or aliased non-`self` argument | 41 |
| unmappable argument kind | 17 |
| unsupported return kind | 16 |
| C or protocol reserved name | 2 |

The unmappable arguments are `float[]?` (8), `Tensor?[]` (3), `Scalar[]` (2),
`Storage` (2), `Stream` (1), and a required `MemoryFormat` (1). The
unsupported returns are `ScalarType` (5), `SymInt` (4), `(Tensor, Tensor[])`
(3), `QScheme` (1), `SymBool` (1), a five-element tuple (1), and
`(Tensor, Tensor, float, int)` (1).

Of the selected operators, 1006 are bound as `at::<name>` free functions and
187 as `self.<name>(...)` methods, which is how the schema's `variants: method`
operators such as `expand` and `repeat` are reached. 153 carry a `SymInt`
argument and are bound through the int64 overload. 103 leave a `generator`,
`layout`, `memory_format`, or `pin_memory` argument at the ATen default; each
one is named in the comment above its binding. 47 renamed themselves with an
overload suffix because `src/torch.x` or an earlier overload already owned the
plain name, so `sum.dim_IntList` is `Tensor.sum_dim`. The 53 collisions with
no free suffix keep the hand-written signature in `src/torch.x`.

This is a function count, not a measure of practical coverage. Tier 1 leaves
out, among others: every `out=` form, named tensors, the sparse and quantized
constructors that take `Storage` or `Scalar[]`, custom autograd functions,
`Dimname` overloads, the `_foreach_*` batched family, and everything the
private `_`-prefixed operators reach. Modules, optimizers, losses, and
serialization are the hand-written shim's territory, not this generator's.
