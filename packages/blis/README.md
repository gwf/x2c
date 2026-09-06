# BLIS client

This experimental package provides an x2c interface to the pinned BLIS 2.1
object API. Its entry point is `src/blis.x`; it builds matrices
and vectors from x2c values, gives `+`, `-`, `*`, and unary `-` real BLIS
meanings with automatic intermediate lifetimes, and reads results back into
x2c values in bulk.

```x2c
import "blis" with Blis, BlisObject;

BlisObject rank = BlisObject.copy_vector(seed, BLIS_DOUBLE);
for (; shift > 1e-15 && round < 100; round++) {
  Scope.retain();
  {
    defer Scope.release();
    BlisObject next = links * rank;
    next = next.scale(1.0 / next.dotv(ones));
    shift = (next - rank).normfv();
    rank.copy_from(next);
  }
}
```

`examples/page-rank.x` is the short application (`make short-example`). It
ranks a five-page link graph by power iteration: the algorithm is the one
operator expression above, the loop stops when the iterate stops moving, and
the output is a ranking.

```text
converged after 53 rounds, shift 7.9e-16
  index      0.3333
  guide      0.3056
  reference  0.2778
  download   0.0833
  blog       0.0000
```

`examples/risk-report.x` is the broader application (`make example`). It
copies named observation rows into single-precision native storage, centers
owner-backed column views with `dotv` and `axpyv`, and updates a risk matrix
with mixed-precision `gemm`.

## Operators and lifetimes

`protocol Blis(T)` maps `add`, `sub`, `mul`, and `neg` to `+`, `-`, `*`, and
unary `-`, and the protocol crosses the package boundary, so a consumer that
only says `import "blis"` gets the punctuation. Addition and subtraction are
elementwise over equal shapes and storage precision; multiplication is BLIS
matrix multiplication when the left column count equals the right row count.

An operator result is a BLIS descriptor over numerical storage the active x2c
Scope owns. It is valid only until that Scope is released and must never be
read, freed, or retained afterward. Use a narrow Scope inside an iterative
loop and `copy_from` the final temporary into an explicitly constructed,
owned object before releasing it. Explicitly constructed objects use BLIS
allocation and the adjacent `defer object.free()` contract.

Mixed storage precision and incompatible dimensions raise before an operator
allocates or mutates a result. `*` does not invent dot-product or tensor
semantics: named `dotv`, `axpyv`, `normfv`, `scale`, and `gemm` remain
available for vector, destination-mutating, mixed-precision, alpha/beta, and
explicit-computation work.

`scale(alpha)` returns a scaled copy with the same Scope-owned lifetime as any
other operator result, and `neg` is `scale(-1.0)`. It is what a power
iteration needs to stay in range when the matrix is not column-stochastic.

## Copy in, read out

`copy_rows` and `copy_vector` name the x2c-to-native copy explicitly, accept
either `List` or `Array`, and accept finite real numeric values only. Each
admitted integer, `float`,
`double`, or `long double` value crosses through `Var.convert(<f64>)` before
BLIS applies the selected single- or double-precision storage boundary.
Exceptional NaN and infinity values are rejected rather than read through an
exact-tag accessor. The `List` a caller passes is the literal the copy reads;
it is never adopted as storage.

`to_rows` and `to_values` are the reverse. `to_rows` returns an `Array` of
`Array`s and `to_values` returns one `Array` for a vector, matrix column, or
matrix row. Both read the numerical buffer directly through the object's own
strides and offsets, so a view, a submatrix, and a transpose read back
correctly. Every element is copied to an x2c `f64`; storage precision, native
layout, strides, offsets, and transposition are not preserved in the Arrays.

Packed `ArrayFloat` and `ArrayDbl` values are not part of this package surface.
The current applications are clearer with small literals and keyed report
data, and a public package method cannot name an optional typed-container
family in its generated header today. Adding packed overloads without an
application that improves would add parallel copy paths rather than simplify
either program.

The result is `Array` rather than `List` because it is a representation
rather than a literal, and because `cons` interns every cell: a
List-of-Lists read of a 400x400 double result costs 59 ns per element against
`Array`'s 9.4 ns, and leaves 160,000 numeric cells in the canonical pool. On
the tuned profile `to_rows` reads a 400x400 result in 0.0015 s against 0.0023 s
for the `gemm` that produced it; the same read hand-rolled over
`at(row, column)` costs 0.0033 s. Element access through `at` remains
available and is the right call for a handful of elements.

## Copy and view behavior

`BlisObject` is the only ordinary wrapper. `new` allocates through BLIS.
`column`, `part`, and `transpose_view` allocate only a small x2c wrapper and
return a mutable non-owning BLIS descriptor. A view records its root owner and
observes mutations made through either the owner or another view. A view must
not be freed: `free` rejects it, while freeing the owner invalidates every
view. The current slice does not resize or reallocate an owned object. Any
future operation that replaces a buffer must advance the owner's generation
before replacement so existing views become invalid.

`at(row, column)` copies one real element to `double`; it is not a mutable
alias. Negative scalar indexes and negative column indexes use x2c's shared
index normalization. `part` checks the complete requested rectangle before
calling BLIS, so BLIS cannot silently truncate an out-of-range view.

## Shape, mutation, and precision

The ordinary slice admits `BLIS_FLOAT` and `BLIS_DOUBLE` real storage.
Dimensions, vector orientation, storage compatibility, and owner liveness are
checked before `axpyv` or `gemm` mutates a destination. `orientation`,
`row_stride`, `column_stride`, `row_offset`, `column_offset`, `transposed`,
and `is_view` expose the facts needed to inspect an application-visible
object without reading `obj_t` fields.

`native()` returns the borrowed `obj_t *` for raw BLIS calls. The pointer is
valid only while the owner remains live; callers must not free the descriptor
or its buffer.

`set_computation_precision` changes BLIS's computation-precision property on
the destination object. The risk report deliberately copies decimal input to
single-precision storage, then performs `gemm` into double storage with
double-precision computation. Its output shows the single-precision rounding
at the collection boundary.

## No Lisp surface

Opaque native objects stay inside the x2c wrappers or on the raw path. A
`BlisObject` owns a contiguous buffer from `bli_obj_create`; `List` is only
the literal `copy_rows` walks while filling that buffer, never a
representation. A Lisp binding would have to convert in and out on every call,
discarding the contiguity and the retained descriptor that are the reason to
link a BLAS at all. This package therefore has no Lisp bindings.

## Native API and deliberate limits

`src/blis-21.h` includes the real configured upstream `blis.h`, rejects the
wrong BLIS release, and rejects profiles with BLAS or CBLAS compatibility
enabled. The complete admitted object, typed, metadata, kernel, packing,
context, and control APIs remain present under their upstream names; there is
no copied declaration list or set of forwarding declarations. The generated
`builds/blis.h` includes the vendored header, so a consumer reaches all of it
through `import "blis"` alone.

Complex and mixed-domain objects, attached or caller-owned buffers, packing,
blocked algorithms, custom kernels, contexts, addons, control trees, and
threading remain raw.

The admitted build is BLIS 2.1 configured `firestorm`, static,
single-threaded, with BLAS and CBLAS compatibility disabled. `firestorm`
selects the tuned Apple silicon microkernels; the portable `generic`
configuration it replaced ran the same 400x400 double `gemm` in 0.0071 s
instead of 0.0024 s. Threading stays disabled because BLIS's own threading
alongside x2c `Thread` in one process is a question nobody needs answered yet.
`dependency.json`, `PROFILE.json`, and `LICENSES/` record the exact source,
configuration, linkage, and incorporated notices.

x2c preserves imported C qualifiers and rejects conversions that silently
drop them. `bli_info_get_version_str` returns `const char *`;
`Blis.version` copies that result into `String`. Raw callers must retain the
upstream qualifiers. [Foreign C qualifiers](../FOREIGN-C-QUALIFIERS.md)
describes the compiler behavior and its earlier limitation.

## Build and test

`make prepare` downloads, verifies, and builds the pinned static profile in
the shared integration cache. `make build` produces `builds/libblis.a` and the
generated package headers after `verify-profile` passes. `make run`
and `make test` prepare the dependency automatically when absent and reuse it
when present. Set `X2C_DEPS_DIR` to move the shared cache, or set
`BLIS_PREFIX` to diagnose another compatible installation.

```sh
make test
make run
make verify-provenance
```

`verify-profile` checks the upstream header hash, the four license texts, the
archive's member count, and the exact set of symbols the archive leaves
undefined; `verify-linkage` checks that no built program acquired a dynamic
dependency outside the system libraries. Both checks run during `build` and
`run`.

The client, tests, and applications are licensed under
[Apache-2.0](../../LICENSE). BLIS and its incorporated sources retain the terms
reproduced under `LICENSES/`. See `../LICENSE-POLICY.md` for the project intake policy.
