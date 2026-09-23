# The Region Model

## The invariant

A value allocated inside a region must not be reachable after that region
ends. Four kinds of place outlive a region: the function's result, storage
declared outside the region (an outer local, an object a parameter points
at, or a static), an object owned by an outer or sibling region, and any
pointer whose target the compiler cannot identify, including a pointer that
a called function stores into for the caller.

A region is a `$scope()` block, a `Scope.retain` and `Scope.release` pair, a
`$scope(&slot)` push, a `Pool.open` bracket, an `$auto` local, the
storage of a `Scope` local that `Scope.destroy` ends, or the function's own
locals and parameters, whose storage ends when the function returns.
`src/regions.x` analyzes these forms before the transform driver lowers
them, so a region is still the call that opens it and the `defer` beside it
that closes it.

## Exemptions

The pass exempts these ways of leaving a region.

A `List` pool owns each canonical value, so ending a region never frees it.
`String`, `List`, and `Symbol` results therefore cross a region boundary
without a warning. A value consed inside a `Pool.open` bracket is the
exception: that bracket's pool frees it, so the pass tracks pool-born values
the same way it tracks scope-born ones. The exemption covers the List cells
alone. `cons(a, rest)` and `%($a)` store `a` in a cell that outlives every
region, so the pass reports a region-born `a` at that store.

`Scope.move` and `Context.export` change the storage's owner. After the
move, the region the pass was tracking no longer holds the allocation, so
the allocation survives the end of that region. The promote family -
`String.promote`, `List.promote`, and `Atom.promote` - hands the value to an
ancestor pool the same way and is exempt for the same reason. Moving into a
caller's slot is the ordinary way to return mutable storage, and the pass
stops tracking the value there. Moving into a `Scope` local of the same
function ties the
value to that local's storage, so a read after `Scope.destroy` reports.

A typed conversion copies. Assigning a `Block`, `Buffer`, or `Array` into a
`String` or `List` declaration produces a new canonical value with its own
owner, so the target does not inherit the region. The pass classifies the
assignment by the declared type through the compiler's `Var` tag for that
type, as the converter does. A `String *` or `List *` points at storage and
gets no exemption.

Every region a function opens ends before the function's own storage. The
address of a local can therefore be stored into another local, or into an
object of a region the function opens, without a warning. A reference
capture, `using &name`, moves the local into a cell of the active region, so
the closure holds that cell rather than the function's storage.

A store into a place that an earlier `defer` in the same block writes
back, as `$let` does, is undone before the block ends and is not reported.
A store made before that `defer` is reported, because a `return` between
them leaves the place holding the value.

A parameter that converts its argument by copying, such as a `List`
parameter given an `Array`, does not store the argument. A local C array
passed on, returned, or stored counts as the address of its first element.

## What the warnings do not cover

The check covers lexical regions and the storage it tracks. It does not
cover:

- storage from plain `malloc` or a C library;
- pointer arithmetic and casts through raw C types;
- values reached through a field of a stack `struct`, which the pass treats
  as one storage, so an address kept in a field of a struct that is copied
  out is not followed;
- callbacks and function pointers, including entry points a Lisp binding
  calls;
- `Scope.free` and `Scope.realloc`, whose effect on other aliases of the
  same allocation the pass does not track;
- `Context` regions, which are not modeled;
- `$auto` and `defer` cleanups other than the runtime's own `Array`, `Map`,
  `Block`, `Bytes`, `Buffer`, `Context`, and `Scope` cleanups;
- a release inside a branch, which leaves the region open for the
  statements after that branch.

Each of these can still produce a dangling pointer that translates without a
warning. The pass reports one pattern. A program without warnings is not
shown to be memory safe.

## How the check works

Each function gets one summary of two facts: whether its result is fresh
storage, and, for each parameter, where that parameter is sunk (returned,
into another parameter's object, into a static, or through an unknown
pointer). The summaries of a unit's functions are computed to a fixpoint,
because a caller's facts depend on its callees' facts. Each round walks every
body with a stack of open regions and a map from each binding to its known
facts: its parameter index, the region it was born in, the local a pointer
was taken from, and whether a free has already ended it. The first round
that changes no summary walked every body against final summaries, so its
warnings are the ones reported.

An address taken with `&` belongs to the storage it names. The address of a
local, a parameter, or a compound literal belongs to the function's own
storage. An address reached through a pointer, such as `&box->value`,
belongs to whatever that pointer holds, so an address inside a parameter's
object counts as that parameter in the summary. A caller of a function that
returns `&box->value` therefore sees its own borrow come back.

A `meta` function is walked the same way when it is defined, against the
summaries of the `meta` functions defined before it. A compile-time call
frees its locals when it returns, so a finding in a `meta` body is an error
that rejects the definition rather than a warning; see
[Meta Functions](meta-functions.md).

Summaries stay inside the unit. For a call into another unit, the pass uses
only a fixed table of runtime operations, such as a `Scope` allocator,
`cons`, `Array.push`, `Scope.move`, and `Array.list_free`. Summaries are not
written to the `.xi` interface. A dependent unit collects its includes before
those units are transformed, and parallel workers do not share transformed
units, so an interface summary would make a unit's warnings depend on input
order, the job count, and interfaces left by an earlier translation. As a
result, the pass reports no warning when a caller passes a region-born value
to a function in another unit that stores its argument into a static.

The whole-project answer is a separate run over the sources at once. The
`region-escapes` command of the `x2c-graph` tool walks every unit against the
summaries the other units proved, repeating until no summary grows, and then
reports. It finds the cross-unit store a translation cannot, and it changes
nothing about how a translation behaves.

## Where the design sits

The region check descends from the ML Kit and Cyclone. The ML Kit inferred
regions and a region-annotated program from an unannotated one. Cyclone made
regions part of the type system of a C-like language and checked pointer
lifetimes against them. From the ML Kit, x2c takes the idea that regions are
the unit of deallocation; from Cyclone, the idea that a C program can be
checked against them. The regions are the ones the author wrote with
`$scope` and the retain and release calls. The check adds nothing to the
program text and produces only warnings, except in compile-time code.

Rust and Swift put ownership and lifetime in the signature. Every call is
checked locally against a declared contract, and a violation is an error.
x2c has no lifetime annotations, so the check derives the same information,
and derived facts are weaker than a declared contract. As a result, existing
C-shaped code compiles unchanged, and ordinary code gets only warnings.

Go's escape analysis and Infer use the most similar methods. Go computes
per-function escape facts and uses them to choose between stack and heap
allocation. Infer computes per-procedure summaries and propagates them
across a program to report memory and lifetime defects. x2c's pass applies
Infer's method to Go's kind of fact: it computes summaries per function
within one unit and uses them for warnings.
