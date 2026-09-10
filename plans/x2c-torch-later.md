# torch package: the later items

> Status: needs author scoping
> Written 2026-09-10 after `plans/x2c-torch.md` M0 to M3, the book chapter,
> and the matched comparison landed on `main`. Each item below is scoped
> and estimated; none is started. Gary picks the order.

## Outcome

Five capabilities the package plan deferred, each with the design it would
take, the effort measured against work already done in this package, and
the acceptance example that proves it. Estimates assume one implementer
with the package's current shim, generator, and verify targets.

## 1. MPS device (1 to 2 days)

libtorch's device is already an `int` at the C ABI. Add `Tensor.to_device`,
a device argument to the creation functions and `Module.to_device`,
`Torch.mps_available`, and a `XT_MPS` constant beside the dtype constants.
MPS has no float64, so the default dtype on that device is float32 and a
float64 request raises `<bad-state>` from libtorch. Coverage is the real
cost: individual ATen kernels are missing on MPS and fail at runtime, so
the acceptance example is the MNIST CNN training on MPS end to end, with
the test suite run once with `TORCH_DEVICE=mps` to list which generated
ops raise. Report that list; do not paper over it.

## 2. Linux (1 to 2 days, needs a Linux machine)

`dependency-linux.json` pinning `libtorch-cxx11-abi-shared-with-deps`,
`.so` names in the Makefile, `-lstdc++` for the shim, an `$ORIGIN` rpath,
and `libgomp` instead of `libomp`. The shim and generated C++ are portable
already. Every verify target must pass on Linux before the README claims
it; there is no Linux box in this workspace, so the plan's platform lane
records the absence until one exists.

## 3. Python-readable optimizer state (about 1 day)

Write the optimizer's state into the pickle dict in the layout
`torch.optim.Optimizer.state_dict()` produces: `state` keyed by parameter
index holding `step`, `exp_avg`, `exp_avg_sq` (and `max_exp_avg_sq` for
amsgrad), and `param_groups` with the hyperparameters and the index list.
Nested dicts of tensors, ints, and floats cross `pickle_save` today; the
work is matching the keys exactly and the reverse load. Acceptance:
`verify-python.py` resumes an x2c-trained Adam in Python and Python's in
x2c, and the next update agrees to the tolerance the comparison plan set,
allowing for the `lerp_` versus `mul_`/`add_` ulp difference already
recorded there.

## 4. `autograd.Function` from x2c (2 to 3 days, riskiest)

libtorch's custom node is a CRTP template, `torch::autograd::Function<T>`.
The shim defines one concrete subclass whose `forward` and `backward` call
C function pointers with tensor arrays and a context handle; x2c supplies
those as `Func` values through the existing func-landing thunks. Saved
tensors live in the node's context and are released with it, so the x2c
side must not hold them in a scope that ends first. Acceptance: an x2c
custom activation with a hand-written backward, trained in the MLP
example, agreeing with the same function written in Python.

## 5. Lisp surface (1 to 2 days)

A `$lisp.binding` group over Var-boxed tensors, modules, and optimizers,
installed by `TorchLisp.install` as the yyjson package does. The open
design question is lifetime: a Lisp value that holds a tensor outlives the
scope that made it, so the bindings must either create tensors in a named
scope the session owns or copy results out. Acceptance: `inline-lisp.x`
composing and training the fit-line model from a Lisp session.

## Sequencing

Items 3 and 1 stand alone and are the most useful first. Item 2 waits for
a Linux machine. Item 4 should follow item 3 so its example can checkpoint.
Item 5 last, once the value model for tensors in Lisp is decided.

## Plan review

- Each item reuses the shim's error boundary, the generated tier, and the
  verify targets; none adds a second implementation of anything libtorch
  owns.
- The only new mechanism is the custom-node subclass in item 4, justified
  because CRTP cannot cross a C ABI any other way.
- Validators are the existing verify scripts extended per item; no new
  gate. Missing MPS kernels are reported, not hidden.
