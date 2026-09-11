# torch package: the later items

> Status: active
> Gary authorized all five expansions on 2026-09-10. Implementation and
> focused macOS and final Linux checks, including native lifetime proof,
> are complete. Final repository publication proof and delivery remain.
> This plan stays active until the final evidence and delivery are recorded.

## Outcome and compatibility

Add MPS, Linux x86_64 CPU, Python Adam state interchange, x2c custom
first-order autograd, and ordinary Lisp training operations. Existing CPU
calls and optimizer archive `save`/`load` retain their behavior. No recurring
repository gate is added. The existing package checks and optional
verification targets establish the new contracts.

## MPS device

Reuse the generated `Tensor.to_device(String, dtype, non_blocking, copy)`;
add `Module.to_device`, `Tensor.device`, `Torch.mps_available`, and
`Torch.mps_synchronize`. Device strings are already the native ABI; no new
device enum or parallel tensor movement operation is needed. Module movement
precedes optimizer construction. MPS callers choose float32; float64 requests
raise the native error. Host-value export first copies to CPU.

The MNIST example trains and evaluates on the selected device, saves its
model, and evaluates a reloaded model. `TORCH_DEVICE=mps` and optional
`TORCH_EPOCHS` select that application path; the default remains one CPU
epoch. Unsupported MPS kernels raise their native errors. The shipped MPS
applications do not require a fallback.

Measured on the pinned macOS arm64 runtime: actual 60,000 training and
10,000 test images, two MPS epochs, 95.23% test accuracy and 95.23% after
checkpoint reload. The device test also passed int64 and float32 host copies,
model movement, an optimizer update, and float64 rejection. The bounded
`verify-mps` probe with fallback disabled records native
`aten::linalg_eig` as unavailable; no full generated-tier MPS claim is made.
A CPU-only host registers the MPS-specific test with `TestHarness_skip`.

## Linux CPU

Use the authorized local Docker lane, Ubuntu 24.04 with Clang 18, under
x86_64 emulation. `dependency-linux.json` pins the official 2.10.0 CPU
archive and its verified hash. The shared dependency framework prepares it;
the Makefile selects `.so`, libstdc++, and the prefix runtime search path.
This measures Linux correctness, not native Linux performance.

The final Linux snapshot passed all 14 recorded actions: package tests,
Python tensor exchange, 23 generated operators with zero disagreement, eight
TorchScript outputs, six Adam resume cases, custom derivative comparison,
native lifetime checks, fit-line, MLP, custom activation, Lisp training, real
MNIST training/reload, and an external import-only consumer. Package tests
reported 34 passes, one unavailable-MPS skip, and 267 assertions; the separate
MPS kernel probe also explicitly skipped. MNIST used all 60,000 training and
10,000 test images and reached 93.23% after one CPU epoch, unchanged after
reload. All 220 source hashes matched the host and were reverified after the
checks. Both owned Docker containers were stopped afterward.

Full commands, statuses, logs, dependency receipt, data and source hashes are
preserved in the `linux/final-acceptance` evidence directory below. This final
run includes the inference-mode callback and ordinary Python Adam scalar
option repairs.

## Python-readable Adam state

`Optimizer.save_python` and `load_python` preserve the standard
`state`/`param_groups` schema, including per-parameter step, first and second
moments, AMSGrad maximum, group ordering, and hyperparameters. Imported
moments move to the destination parameter's device. Parameter matching follows
optimizer order; incompatible shapes, dtypes, group sizes, duplicate IDs, or
unsupported Adam modes raise an Error. Parse and validate the whole imported
state before replacing the existing optimizer groups or moments.

Exact parity is required against the Python `LibtorchAdam` operation-order
control. Stock Python Adam remains a separately measured comparison with its
recorded arithmetic divergence accepted. This is an Adam-only interchange
surface; existing libtorch optimizer archives remain available separately.

`verify-interchange` passed native-to-Python resume, Python-to-native resume
with two parameter groups, empty-state resume, stock-default Adam state,
integer scalar options, and a scalar Tensor learning rate on macOS and Linux.
Every parameter, moment, group option, and step is compared. The final
macOS and Linux checks resume three updates and also prove malformed moment shape,
duplicate ID, negative learning rate, and fractional step are rejected
without changing those next three updates.
The separate benchmark runner owns the matched/stock workload measurements.

## Custom first-order autograd

`Tensor.custom(forward, backward, inputs)` supplies one output and a borrowed
`AutogradContext`; the callbacks use ordinary `Func` values. The native graph
owns saved tensor references. Each callback enters an isolated x2c Context,
and errors are copied out and re-raised only after returning through C++.
The native capsule never destroys an x2c allocation.

`Tensor.backward_callbacks` temporarily disables libtorch autograd engine
multithreading through its thread-local state. Both CPU and MPS callbacks
execute on the invoking thread, which must be the graph's creating thread.
The thread and invocation checks precede x2c entry. Nested backward/custom
calls are rejected; ordinary `backward` is not the callback entry point.
This boundary supports first-order, one-output, out-of-place functions.
Forward input version checks reject mutation of tensors with version
counters, including inputs not saved for backward. Inference tensors do not
have counters; in-place mutation remains unsupported for those tensors but
is not diagnosed by this check. Return one gradient or Null per input. Callback
`Func` values and their captures remain borrowed and must outlive the graph on
that thread.

The final CPU/MPS tests passed derivative, saved-value, error containment,
ordinary-backward rejection, nested-backward rejection, and caller-thread
checks, including unsaved-input mutation, inactive-input gradient selection,
and invocation from another thread. Inference-mode evaluation and normal-input
mutation rejection under that guard also passed (49 assertions on macOS,
25 on Linux). The custom swish MLP example trained from loss 3.099022 to
0.003990 in 300 steps on both CPU and MPS.
`verify-custom` also passed on CPU and MPS against both a Python custom
Function and ordinary autograd for swish values and squared-loss gradients.

## Lisp surface and lifetime

`TorchLisp.install` installs tensor creation and inspection, linear modules,
SGD/Adam, forward, loss, backward, updates, arithmetic/activations, checkpoints,
and explicit `torch-free`. The existing Lisp session owns boxed wrappers;
`torch-free` releases native storage immediately but does not collect the
wrapper. Session destruction reclaims the session. This deliberately reuses
existing Lisp semantics and adds no garbage collector or training executor.

`inline-lisp.x` defines a normal Lisp step and composes the fit-line model
from those operations. In 200 measured steps, loss fell from 11.871755 to
zero at displayed precision. Scope allocations grew from 386 to 4367;
that count includes Lisp values and wrappers, not only tensors. Long-lived
sessions should free native temporaries per step and periodically recreate
the session if that wrapper growth matters.

The optional `verify-lifetimes` builds separate instrumented native objects
and uses the existing handle counters. It checks per-step native cleanup,
custom graph cleanup, and native handle return to baseline at session
destruction. The macOS and Linux proofs passed: 64 custom graphs returned
native handles to baseline after each graph, and 128 Lisp steps retained four native
handles throughout. Scope allocations grew from 355 to 2159; session
destruction returned native handles to baseline. Its counter build does not
replace the package's ordinary objects or extend any recurring gate.

## Remaining delivery

- Fresh matched and stock benchmark outputs are recorded separately in
  `packages/torch/benchmarks/MATCHED.md` and `REPORT.md`. The control passes;
  stock explicit tabular loss remains over tolerance as accepted.
- Complete final repository publication proof, delivery, and public
  documentation verification. Archive this plan with the closing revision
  and evidence only after those pass.

Implementation logs remain under `debug/`; the parent closure task preserves
Linux evidence under
`/Users/gary/Documents/x2c-evidence/closeout-20260910/linux`.

## Plan review

The design reuses generated tensor movement, native optimizers and pickle,
Lisp session ownership, the existing C error boundary, and handle counters.
The custom-node subclass is necessary to cross libtorch's C++ template API;
the callback guard is necessary to keep x2c execution on a proven thread and
prevent Errors crossing native frames. Imported optimizer validation protects
external state replacement; callback shape, thread, reentrancy, and mutation
checks protect native graph execution. Their focused negative tests exercise
those same boundaries. No second optimizer, allocator, device representation,
or training framework is introduced.
