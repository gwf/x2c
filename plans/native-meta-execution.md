# Native meta execution: staging user meta code and removing the Lisp lowering

> Status: spike in progress on gwf/native-meta-execution-b47d86. The
> author's full text was truncated in transfer after "The E1 probe on this
> branch"; the removal list and order of work are pending from Gary.

## Spike step 1 (in progress)

Pending group, `$` trigger, staging, and content-hash cache for bodied user
`meta` functions, loaded through `Compiler.load_native_module`. Proven on one
user unit that defines a bodied `meta` function and calls it with `$`.
Shipped meta code (builtins, linked meta) and all removals wait for the rest
of the plan.

## Design summary

See the mechanism as written by the author: group per unit in source order;
trigger in `_evaluate_meta_value` via `_bind_native_meta`; staging emits the
cumulative group as one C unit through the ordinary backend, compiles with
the meta-module toolchain flags, caches under the script cache root keyed by
group source, compiler stamp, and toolchain identity; `$f(x)` inside a meta
body means `f(x)`; `meta static` reset via `x2c_module_reset()`; raises reach
the existing catch; `check_meta_regions` stays.
