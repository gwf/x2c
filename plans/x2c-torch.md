# x2c over libtorch: Scope finalizers, the `@` operator, and packages/torch

> Status: active
> Approved 2026-09-09 from the research spike in the budapest workspace.
> PR 1 (Scope finalizers) landed on `main` as 490070c. PR 2 (`@`) in
> progress. PR 3 (packages/torch) is being re-designed around reusing
> libtorch's nn, optim, data, and serialization through a C ABI shim and
> generated operator bindings; the section below is the superseded first
> draft until the evidence-based revision replaces it.

## Context

The spike in `.context/torch-spike/` proved an x2c layer over libtorch works
through a hand-owned `extern "C"` shim: `(x.matmul(w) + b * b).tanh().sum()`
with `backward()` runs from x2c and matches a C control. Two gaps stand
between that and a package that reads like PyTorch and is idiomatic x2c:

1. Operator temporaries hold C++-owned tensors and `Scope` cannot run a
   destructor when it reclaims a block. Every native-handle wrapper today
   pushes that onto the caller as a `defer x.free()` contract.
2. PyTorch spells matrix multiply `@`; x2c has no such operator, and BLIS
   overloads `*` as matmul, so `*` would mean different things in two packages.

Gary asked for general changes rather than torch-only hacks. Both fixes are
general: finalizers serve every native-handle wrapper (yyjson, sqlite, pcre2,
libcurl, blis, raylib, libuv), and `@` is one more protocol row that BLIS can
adopt.

Decisions taken here (routine, per the standing guidance):
- Shim is hand-written and pinned, about 80 functions; generation from the
  torch source tree is a later milestone if the surface proves too thin.
- nn.Module, optimizers, and data loading are written in x2c over Tensor
  ops, not wrapped from torch::nn's template-heavy C++.
- Dependency is the official libtorch zip, pinned in `dependency.json`,
  macOS arm64 CPU first. `TORCH_PREFIX` override follows the BLIS pattern.
- `*` on tensors is elementwise as in PyTorch; `@` is matmul.

## PR 1: Scope finalizers (`lib/scope.x`)

Public surface, above `#pragma private` (`lib/scope.x:53`), documented in
the style of `Scope.malloc` (`lib/scope.x:695-708`):

```c
void *Scope.malloc_finalized(size_t size, void (*drop)(void *));
void *Scope.malloc_finalized_in(Scope *slot, size_t size,
                                void (*drop)(void *));
```

`drop(ptr)` runs exactly once when the block is reclaimed by `Scope.free`,
`Scope.realloc(ptr, 0)`, `Scope.release`, `Scope.destroy`, thread release, or
`Scope_shutdown`. It survives `Scope.move` and `Scope.retain`; `Scope.realloc`
preserves it and `drop` receives whichever pointer is live. `drop == NULL`
raises `<bad-arg>`.

Representation: an extra 16-byte `ScopeFinalizer { drop; pad }` placed
*before* the public `struct ScopeAlloc` header, only for finalized blocks;
bit 0 of `next` marks a finalized block. `struct ScopeAlloc` (`lib/scope.x:30`)
and `PTR_ALLOC`/`ALLOC_PTR` are unchanged, payload stays 16-byte aligned,
`bootstrap/lib/scope.h` keeps its layout, `Scope.owner` (walks `prev` only)
is untouched. Rejected: growing every header (taxes every Var box and Block)
and a side registry (needs a lock and lookup per free, and `Scope.move` sync).

Edits, all in `lib/scope.x`:
- New private macros after line 68: `IS_FINALIZED`, `NEXT`, `SET_NEXT`
  (preserving the flag on writes into a neighbor's header), `ALLOC_BASE`,
  `ALLOC_DROP`.
- `_malloc_in` (`:267-283`): add a `drop` parameter; `extra = drop ? 16 : 0`
  in the overflow check and `_data_malloc`; store `drop`; set the flag.
  `_calloc_in`/`_memdup_in` pass NULL.
- `_free_alloc` (`:302-312`): unlink through `NEXT`/`SET_NEXT`, then run
  `drop(ALLOC_PTR(old))` if finalized, then `free(ALLOC_BASE(old))`.
  Unlink-before-drop keeps the list consistent if `drop` re-enters.
- `_destroy_chain` (`:314-329`): pop-head loop (`scope.first = NEXT(alloc)`,
  re-tag the new head, drop, `free(ALLOC_BASE)`). Same head-first order as
  today, and anything `drop` allocates into the dying scope is reclaimed.
- `_allocation_count` (`:351-353`), `Scope.move` (`:845-862`),
  `Scope.realloc` (`:876-898`): route every raw `next` read/write through the
  macros; realloc uses `ALLOC_BASE` and subtracts `extra` in its overflow check.
- No change to `lib/common.x`; the `Scope` typedef there suffices.

Documented rules, not machinery: `drop` must not raise; it must not free or
observe the block being dropped; it may allocate into other scopes, and into
the dying scope only as scratch; it runs on the thread that frees the block.
No `disarm` operation: yyjson, sqlite, and libcurl already release-once-and-NULL
their native field (`packages/yyjson/src/yyjson.x:633`,
`packages/sqlite/src/sqlite.x:167`, `packages/libcurl/src/libcurl.x:392`), so a
wrapper's `drop` written as `if (self.native) { release; self.native = NULL; }`
makes an explicit `.free()` or `defer x.free()` a harmless no-op.

Tests, `unittest/test-scope.x` (register in `scope_suite`, `:331`; use
`$test.scoped()` and `Scope.stats()` deltas as at `:254-299`):
runs once on release; runs on `Scope.free` and `realloc(ptr, 0)` and not again
on release; survives `Scope.move` from head and middle positions mixed with
plain blocks; realloc preserves and passes the new pointer; reverse
allocation order; `drop` may allocate; null `drop` raises `<bad-arg>`.
`unittest/probes/scope-shutdown.x` + `run-scope-shutdown.sh` (`make
scope-probes`): modes `finalizer-shutdown` (process root, drop prints once,
no leak report) and `finalizer-thread` (worker root released on exit).

Docs: `docs/src/guide/memory.md` new subsection "Attaching a finalizer" after
"Moving a value out of a scope" (`:167-184`) plus one sentence beside
`Scope.free` (`:64-67`); `docs/src/guide/wrapping-c-libraries.md` "Ownership
and defer" (`:195-198`) gains the finalized-record shape and keeps `.free()`
as the idempotent early release.

Delivery: one PR: `lib/scope.x`, the two test files, the two docs, regenerated
`bootstrap/`. No src/lib/package caller uses `malloc_finalized` in this PR.
The gate must be ensured twice because `bootstrap/lib/scope.h` gains two
prototypes (two-round refresh).

## PR 2: the `@` operator (compiler and runtime)

`@` is a binary operator at multiplicative precedence, left-associative,
lowering to the protocol row `T T.matmul(T, T)` exactly as `*` lowers to
`mul`; `@=` is its compound form. `@` has no C meaning, so a use with no
protocol member is a type error. src/ and lib/ do not use `@` in this PR.

Ordered edits:
1. `lib/scan.x` `scan_operator` (`:262-264`): own `case '@'` returning 2 for
   `@=`, else 1. `lib/tokenizer.x:346` opchars already contains `@`.
2. `lib/tokenizer.x` `_lisp_tokens` (`:395-398`): in list mode, `@` followed
   by `=`, whitespace, `)`, or NUL tokenizes as a `<lit-atom>` (`@` or `@=`).
   `@name`, `@{`, `,@` keep their splice meaning. Today `%(op @ a b)` fails
   with `expected identifier after '@'` (`src/literals.x`
   `_parse_named_reference`), so match patterns need this. Test in
   `unittest/test-tokenizer.x` beside `:80-90`.
3. `src/ast.x` `compound_operators` (`:66-70`): `{ <@=>, <@> }`. This enrolls
   `@=` in assignment parsing, direct compound lowering via
   `protocol_update_helper` (`src/transform.x:887-903`,
   `src/protocol.x:1696`), and dynamic lowering (`src/transform.x:657`).
4. `src/expressions.x`: `_precedence` (`:625`) adds `<@>` to level 10.
   `_binary_expression` (`:1351`, after the `in` check) reports
   `operator '@' requires an implemented matmul member` with a
   `left type: ... right type: ...` note when neither operand is `Var`.
   `_binary_op_type` (`:869`) gets no `@` case so `int @ int` never types.
5. `src/protocol.x` `operator_members[]` (`:1353`): `{ <@>, <matmul>, 0 }`.
6. `lib/protocols.x` `protocol Var(T)` (`:60`): `T T.matmul(T, T);`.
7. `lib/common.x` `VarMethods` (`:167`): `matmul` after `mod` in the
   `VarBinaryFn` run. Boxed thunks are generated only for `VarMethods`
   fields (`src/protocol.x:1010`, `:2085`), so without this a boxed `@`
   can never reach a participant.
8. `lib/dispatch.x` `Var.try_dispatch_binary` (`:36-57`): `case <matmul>`.
9. `lib/varops.x`: `Var.matmul` beside `Var.mul` (`:547`) as
   `_protocol_arithmetic(lhs, <matmul>, <@>, rhs)`; `Var.binary` (`:604`)
   `case <@>`; `_update_operator` (`:441`) adds `<@>`;
   `_general_numeric_binary` (`:340-352`) raises `<bad-op>` for `<@>` so plain
   numbers never reach `_integer_binary`.
10. `make sym-update` (new `VarMethods.matmul`, `Var_matmul`, `<@>`, `<@=>`,
    protocol record in `etc/symbols.xlisp`); review the diff.
11. Docs: `docs/src/guide/protocols.md:293-303` punctuation table gains
    `@ -> matmul` and `@=`; `docs/src/reference/language.md` operator list
    (`:1686`), direct-update prose (`:1725-1729`), a precedence sentence, and
    the splice section (`:1330-1358`) noting that a bare `@` in `%()` is the
    operator atom. `make doc-generate` for varops and dispatch module pages.

Fixtures in `unittest/compiler-fixtures/`, shaped on
`protocol-boxed-operators.*` and `macro-generated-prototype-rejected.*`:
- `protocol-operator-matmul` (stdout, status): a `Mat` with `matmul`,
  `protocol Var(Mat)`; checks `a @ b`, `a @= b`, boxed `va @ vb`, `va @= vb`,
  left-associativity of `a @ b @ c`, and a `match` on `%(op @ ?l ?r)`.
- `protocol-operator-matmul-missing` (compile-status 1, diagnostics):
  `2 @ 3` and a struct without `matmul`.
- `var-matmul-numeric` (stdout): `Var.binary(2, <@>, 3)` caught as `bad-op`.

Not touched, by decision: `lib/array-generics.xmacro:52` and
`lib/typed-map.x:249` numeric container arithmetic; `etc/*.xlisp` and
`src/macros.x` enumerate no operators.

Follow-up after PR 2 lands (separate small PR): `packages/blis` switches `*`
to elementwise and adds `matmul` for `@`, so `*` means the same in both
numeric packages.

## PR 3: `packages/torch`

Layout follows `packages/AGENTS.md` and copies `packages/cstar/Makefile` for
the native object and `packages/blis` for the prefix override:

- `src/torch-2.10.h`: the pinned shim header (extern "C", opaque
  `xt_tensor`, `int64_t` shapes, `xt_last_error`). It is the raw API the
  package publishes; there is no C upstream header to include.
- `src/torch-shim.cpp`: the shim, compiled by a package Makefile rule with
  `$(CXX) -std=c++17 -I$(TORCH_PREFIX)/include
  -I$(TORCH_PREFIX)/include/torch/csrc/api/include` into
  `builds/torch-shim.o`, added to `PACKAGE_LINK` via `-Xlinker` with
  `-L$(TORCH_PREFIX)/lib -ltorch -ltorch_cpu -lc10 -lc++
  -Wl,-rpath,$(TORCH_PREFIX)/lib`, and `build: builds/torch-shim.o`.
  `x2c build` compiles only `src/*.c`, so the `.cpp` lives outside its scan.
- `src/torch.x`: `Tensor` record allocated with `Scope.malloc_finalized`
  whose `drop` releases the handle once; `protocol Torch(T)` rows `add sub
  mul div neg matmul compare`; `protocol Var(Tensor)`; creation
  (`of`, `zeros`, `ones`, `randn`, `arange`), shape/dtype queries, elementwise
  math and activations, reductions, `matmul`, `transpose`, `reshape`,
  `select`/`getindex`, `requires_grad`, `backward`, `grad`, `detach`,
  `no_grad` as a scoped flag, `item`, `to_values`/`to_rows`, and `native()`.
  Explicit `.free()` stays as the idempotent early release.
- `src/torch.xmacro` (optional, milestone B): `$torch.module` for a struct
  of parameters with a `forward` Func and parameter enumeration; `SGD` and
  `Adam` in x2c over the parameter List.
- `dependency.json`: source URL
  `https://download.pytorch.org/libtorch/cpu/libtorch-macos-arm64-2.10.0.zip`
  (77 MB), sha256 recorded at pin time, `root: libtorch`, no build steps,
  receipts `{prefix}/include/torch/torch.h` and `{prefix}/lib/libtorch_cpu.dylib`.
  `packages/tools/deps.py` `_extract` (`:245`) opens tar only; add a
  `zipfile` branch with the same root and path-safety checks. That is a
  small general change to the dependency tool and lands inside this PR.
  `dependency-linux.json` is a follow-up (cxx11 ABI zip).
- `LICENSES/`: PyTorch BSD-3 plus the bundled third-party notices from the
  archive.
- Examples: short `examples/fit-line.x` (linear regression by gradient
  descent, result more prominent than setup); broad `examples/mlp.x` (a
  two-layer MLP with `@`, tanh, SGD written in x2c, training loop with a
  narrow Scope so finalizers reclaim temporaries per step, and a bad-shape
  error caught as `<bad-state>`).
- Tests: `tests/test-torch.x` (creation, operators, autograd values against
  hand-computed gradients, finalizer reclaim via `Scope.stats`, shape error),
  `tests/test-raw-api.x` (the shim header directly).
- Lisp: `TorchLisp.install` over Var-boxed tensors via `$lisp.binding`
  groups as `packages/yyjson/src/yyjson.x:1006-1089` does; milestone B.
- Registration: rows in root `Makefile` `packages:` (`:121-130`) and
  `packages-check:` (`:136-144`); a table row and experimental note in
  `packages/README.md:8-24`; `packages/tools/check-linkage.py` is not used
  (torch links dynamically by design; say so in the README).

Milestone A is tensor plus autograd plus the short example and tests.
Milestone B is modules, optimizers, the broad example, and the Lisp surface.

## Verification

- PR 1: `make build`; `(cd unittest && ./test-all scope_suite)`;
  `make scope-probes`; `tools/gate-state.py ensure agent-pr-check` twice.
- PR 2: `make build`; `make test` (tokenizer suite); `make
  verify-fixtures-update`, review the diff, `make verify-fixtures`; `make
  sym-update && make sym-check`; `make doc-generate && make doc-check`;
  `tools/gate-state.py ensure agent-pr-check` (bootstrap regenerates).
- PR 3: `make -C packages/torch prepare build test run`; `make
  packages-check` after registration; both examples' real output in the
  README; `Scope.stats()` shows zero live allocations after the training loop.

## Plan review

- Facts established by producers: the finalizer flag is set only by
  `_malloc_in` and read only through the private macros; consumers do not
  recheck it. The `@` row is consumed by the same `operator_members` lookup
  as every other operator; no second table.
- Reused: `Scope.shutdown_hook` style for the function-pointer contract;
  `protocol_update_helper` and `_dynamic_binary_operator` derive `@=`
  behavior from the compound table with no new code path; cstar's native
  object rule and blis's prefix override for the package Makefile.
- Deleted or retired: after PR 1, package wrappers can drop their caller-side
  `defer x.free()` contracts one at a time; after PR 2, BLIS's overloaded `*`.
- New mechanism justified: the 16-byte pre-header exists only on finalized
  blocks, so the hot allocator pays nothing; the list-mode `@` atom rule is
  the minimum that makes `%(op @ ?l ?r)` patterns spell the operator.
- Diagnostics and negative fixtures: `<bad-arg>` for a null `drop` (documented
  input check); the `@`-without-`matmul` type error protects against emitting
  invalid C (`src/emit.x:1329` prints the operator verbatim); `<bad-op>` for
  numeric `Var @ Var` matches the existing floating-point default. Nothing
  else is validated.
