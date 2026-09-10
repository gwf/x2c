# x2c over libtorch: Scope finalizers, the `@` operator, and packages/torch

> Status: active
> PR 1 (Scope finalizers, 490070c) and PR 2 (`@`, 1316cf0) landed on `main`
> 2026-09-09, followed by two converter fixes the package needed: mixed
> operands convert for handle typedef participants, and a package's
> converter resolves under its `pkg__` spelling. Gary approved the four
> tradeoffs under PR 3 the same day. M0 of `packages/torch` (tensors,
> autograd, `fit-line.x`, tests, pinned libtorch zip) is landing; M1 to M3
> follow the milestones below.

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

## PR 3: `packages/torch` (revised 2026-09-09 on bridge evidence)

Principle: x2c owns the language interface and the glue; libtorch owns the
math, the modules, the optimizers, and the serialization. Nothing that
libtorch already implements is rewritten in x2c.

### Evidence (`.context/torch-arch/`, reproduced)

- A shim-side `ComposedModule : torch::nn::Module` with no forward of its
  own, whose children are `register_module`d by name, is enough for a model
  composed outside C++: parameters enumerate with Python-identical names,
  `torch::optim::Adam` over `parameters(true)` trains them, and the state
  serializes. The forward `l2(tanh(l1(x)))` lives in C and never enters C++.
- Training agreement with Python from the same init and data, Adam lr 0.05,
  200 steps: losses identical to 8 digits at steps 0, 100, and 200; max
  parameter divergence 5.4e-07 (float32, same kernels, unpinned reduction
  order). Reload delta 0.
- Checkpoint interoperability, measured: `torch::jit::pickle_save` of a
  `Dict<string, Tensor>` reads in Python with `torch.load` (needs
  `weights_only=False` or an allowlist of `torch.jit._pickle.restore_type_tag`);
  Python `torch.save(dict(sd))` reads with `pickle_load`; Python's raw
  `OrderedDict` state_dict does not; `torch::save` archives read in Python
  only through `torch.jit.load`.
- The wheel ships no `native_functions.yaml`; `include/ATen/ops/` has 1,818
  public op headers (1,189 after dropping `_`-prefixed and backward ops).

### Architecture

Three layers, each with one owner:

1. `src/torch-shim.cpp` + `src/torch-2.10.h`: the hand-written C ABI core.
   Opaque handles `xt_tensor`, `xt_module`, `xt_optim`, `xt_scheduler`,
   `xt_jit_module`, `xt_generator`. Thread-local last-error string; every
   entry catches. Thread-local no-grad and inference-mode guard stacks with
   push/pop. `ComposedModule` with `register_module`, `named_parameters`,
   `named_buffers`, `train/eval`, `to(device)`, `zero_grad`. Constructors
   for `Linear`, `Conv1d/2d`, `BatchNorm1d/2d`, `LayerNorm`, `Dropout`,
   `Embedding`, `LSTM/GRU`, `Sequential`; functional losses. Optimizers
   `SGD`, `Adam`, `AdamW`, `RMSprop`, `Adagrad`, `LBFGS` (closure via a C
   thunk over an x2c `Func`) with param groups and per-group LR get/set;
   `StepLR` and `ReduceLROnPlateau`. Serialization: pickle dict save/load
   (package format), `torch::save/load` archive (C++ path), `torch::jit::load`
   plus IValue-crossing `forward`. Tensor creation, dtype/device/shape
   queries, `select/slice/index_select/masked_select/index_put` for indexing,
   `data_ptr` copy in/out.
2. `tools/gen-ops.py` + `generated/`: operator bindings generated from the
   pinned `native_functions.yaml` at pytorch tag v2.10.0 (second pinned
   source in `dependency.json`, verified against `ATen/ops/*.h` by
   compiling). Copies the tch-rs conventions: `xt_<op>_<overload>` names,
   out-param arrays for tuple results, every body caught into the
   thread-local error, every returned handle new. Tier 1 is the ~1,189
   non-private non-backward ops without `SymInt`, `Dimname`, or `out=`
   overloads, roughly 1,400 to 1,900 C functions; tier 2 adds `out=`,
   in-place, and the `linalg`/`fft`/`special` namespaces. Generated x2c
   wrappers land in `src/torch-ops.x` as `Tensor.<op>` methods.
3. `src/torch.x` (+ `torch.xmacro`): the language interface. `Tensor`
   records allocated with `Scope.malloc_finalized`, so operator temporaries
   die with their scope and a training step is one `Scope.retain/release`
   pair; protocol rows `add sub mul div neg matmul compare getindex`
   (`*` elementwise, `@` matmul); `Module` with named children, an x2c
   `forward` as a `Func` or a `$torch.module` decorated struct, parameter
   and buffer enumeration returning Lists of named tensors; `Optimizer`,
   `Scheduler`, `Checkpoint.save/load` over the pickle-dict format; errors
   raised through `lib/error-macros.xmacro` with the first line of the
   torch message.

Reimplemented in x2c, each justified:
- Batching and shuffling (a dozen lines: `randperm` + `index_select`). The
  C++ `DataLoader` is a template over a compile-time `Dataset` concept and
  cannot cross a C ABI without a callback adapter per element type.
- Learning-rate schedules other than `StepLR` and `ReduceLROnPlateau`, which
  are the only two libtorch ships; the rest are arithmetic on a group's LR.
- Nothing else. Modules, optimizers, losses, autograd, serialization, and
  every tensor kernel are libtorch's.

### Milestones and acceptance examples

- M0, platform: `dependency.json` pins the official macOS arm64 CPU zip
  (`deps.py` gains a `zipfile` branch with the tar path-safety checks);
  Makefile rule compiles the shim with `$(CXX) -std=c++17` into `builds/`
  and links `-ltorch -ltorch_cpu -lc10 -lc++` with an rpath; `TORCH_PREFIX`
  override as BLIS. Tensor creation, arithmetic, reductions, autograd, and
  `fit-line.x` (linear regression by gradient descent) with tests.
- M1, training and checkpoints: `mlp.x` composes `Linear` children under a
  `Module` with an x2c forward, trains with `Adam`, saves a checkpoint, and
  `tests/verify-python.py` loads it in the pinned Python torch and reproduces
  the loss; reload from the checkpoint; indexing (`t[i]`, `select`, `slice`,
  `index_select`, boolean mask); dtype conversion and device query;
  `train/eval`, `no_grad` as a scoped pair.
- M2, generated operators: tier 1 generated from the pinned yaml, compiled,
  and spot-tested against Python for 20 ops with shape, dtype, and error
  cases; `sym-update`-style regeneration target documented.
- M3, coverage: `Conv2d/BatchNorm/Dropout/Embedding`, `CrossEntropyLoss`,
  `StepLR` plus x2c cosine and warmup schedules, `datasets::MNIST` through
  the shim for `mnist.x`, an inference example loading a TorchScript model
  exported from Python (`jit-infer.x`), optimizer state save/load through
  the C++ archive, `set_num_threads`.
- Later: MPS device (an int in `TensorOptions`, gated by a training example),
  Linux (cxx11 ABI zip and `dependency-linux.json`), Python-readable
  optimizer state (tensor-by-tensor), `autograd.Function` custom nodes, a
  Lisp surface.

### Explicit gaps

- `torch.compile`, Dynamo, Inductor, `torch.jit.script/trace` of x2c code:
  structurally unavailable, they capture Python. x2c loads and runs
  TorchScript; it cannot produce it.
- The Python ecosystem: torchvision, HuggingFace, Lightning, numpy, ONNX.
- Bit-exact agreement with Python: float32 tolerance is the promise.
- Checkpoint format rules Python users must follow: save `dict(sd)`, not the
  `OrderedDict`; allowlist `restore_type_tag` for `weights_only=True`.

### Tradeoffs for Gary

1. Dynamic linking only: `libtorch_cpu.dylib` is 213 MB and static linking
   needs whole-archive registration. An x2c program using torch is not
   self-contained, unlike every other x2c artifact.
2. One pinned torch version per release; a bump recompiles the shim and
   regenerates tier 1. Generation adds a second pinned artifact (the yaml
   at the matching source tag).
3. Per-op handle allocation (one heap block per result); noise at kernel
   sizes, visible in tight loops over tiny tensors.
4. libtorch brings its own OpenMP thread pool into the process.
5. Optimizer state is not Python-interoperable in M1; module state is.

## Verification

- PR 1: `make build`; `(cd unittest && ./test-all scope_suite)`;
  `make scope-probes`; `tools/gate-state.py ensure agent-pr-check` twice.
- PR 2: `make build`; `make test` (tokenizer suite); `make
  verify-fixtures-update`, review the diff, `make verify-fixtures`; `make
  sym-update && make sym-check`; `make doc-generate && make doc-check`;
  `tools/gate-state.py ensure agent-pr-check` (bootstrap regenerates).
- PR 3: `make -C packages/torch prepare build test run` per milestone;
  `tests/verify-python.py` against the pinned Python torch for M1 and M2;
  `make packages-check` after registration; every example's real output in
  the README; `Scope.stats()` shows zero live allocations after a training
  loop.

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
