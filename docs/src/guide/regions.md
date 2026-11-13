# The Region Model

The compiler checks that values allocated in a region do not remain reachable
after the region ends. This chapter states the invariant behind that check,
its exemptions and limits, and how it works.

## The invariant

A value allocated inside a region must not be reachable after that region
ends. Four kinds of place outlive a region: the function's result, storage
declared outside the region (an outer local, an object a parameter points
at, or a static), an object owned by an outer or sibling region, and any
pointer whose target the compiler cannot identify, including a pointer that
a called function stores into for the caller.

A region is an `auto` block, a `Scope.open` and `Scope.close` pair, a
`auto (&slot)` push, a `Pool.open` bracket, a local with initializer `auto`, the
storage of a `Scope` local that `Scope.destroy` ends, or the function's own
locals and parameters, whose storage ends when the function returns.
The compiler checks these forms before it lowers them, so a region is the call
that opens it and the `defer` beside it that closes it.

## Exemptions

The pass exempts these ways of leaving a region.

A canonical-value pool owns each canonical `String` and `List`, so ending a
`Scope` region does not free it. A value made inside a `Pool.open` bracket
belongs to that bracket's pool and is tracked like scope-born storage. This
includes `String.new`, `String.malloc`, and List cells returned by a helper.
`cons(a, rest)` and `%($a)` retain their arguments in the cell's pool: a value
from that same pool stays there, while a value from a shorter-lived region
reports at the store.

A container's `move_to`, `Scope.move`, and `Context.export` change the
storage's owner. After the move, the region the pass was tracking no longer
holds the allocation, so the allocation survives the end of that region.
`Scope.move` relinks only the allocation it is given. An `Array`, `Map`,
`Block`, or `Buffer` keeps its buffers in other allocations, so the pass
still ties a container given to `Scope.move` to its region; `move_to` moves
the whole container. The promote family - `String.promote`, `List.promote`,
and `Atom.promote` - hands the value to an ancestor pool the same way and is
exempt for the same reason. Moving into a caller's slot is the ordinary way
to return mutable storage, and the pass stops tracking the value there.
Moving into a `Scope` local of the same function ties the value to that
local's storage. After `Scope.destroy`, the pass reports the value when it
is returned or stored. It reports a plain read of it only in the optional
audit.

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
the closure holds that cell, which the active region owns.

A store into a place that an earlier `defer` in the same block writes
back, as `with` does, is undone before the block ends and is not reported.
A store made before that `defer`, or after a `defer` that runs on only one
branch, is reported, because a `return` between them leaves the place
holding the value.

A destination that converts its value by copying does not keep it: a `List`
parameter given an `Array`, or a `Var` given a C string, which it boxes as a
fresh `String`. A copy into a container is fresh storage of the active
region, and the pass tracks it. An `Array` given a `List` or an `Iter` makes
such a copy, and so does a conversion either way between a typed `Array` or
`Map` family and its boxed family. A local C array passed on, returned, or
stored counts as the address of its first element.

A number holds no address. A value of integer, floating-point, or enum
type, or a destination of such a type, carries nothing the pass tracks.
An address cast to `intptr_t` and then returned does not report, and a
pointer cast back from that number is not followed. The exception is a
`Var` given a `long`, `unsigned long`, `long long`, `unsigned long long`, or
`long double`. The `Var` boxes the number, and the pass tracks the box as
fresh storage of the active region.

## What the warnings do not cover

For an address into the current function's frame, a raw pointer store into
an unknown destination or a parameter's object is not an ordinary warning.
The store may register a temporary borrow that cleanup removes before
return. The pass does not prove that cleanup; the code must satisfy its C
lifetime contract. Returned addresses, static stores, known retaining
operations such as `Array.push`, and already ended regions keep their
checks. `x2c graph certify`, an experimental checkout command, keeps the
possible-escape finding, and meta functions keep the error.

The check covers lexical regions and the storage it tracks. It does not
cover:

- storage from plain `malloc` or a C library;
- pointer arithmetic and casts through raw C types;
- values reached through a field of a stack `struct`, which the pass treats
  as one storage, so an address kept in a field of a struct that is copied
  out is not followed;
- callbacks and function pointers, including entry points a Lisp binding
  calls;
- calls into functions defined in other units, except the runtime
  operations the pass handles; such a call is assumed to keep none of its
  arguments and to return no tracked storage;
- other aliases of storage that `Scope.free` or `Scope.realloc` ended; the
  pass ends only the local passed to the call, and it reports a free only
  of storage it can see is not from a Scope allocator: a literal, the
  function's own storage, or a pooled value;
- `Context` regions, which are not modeled;
- Initializer `auto` and `defer` cleanups other than the runtime's own `Array`, `Map`,
  `Block`, `Bytes`, `Buffer`, `Context`, and `Scope` cleanups;
- a release inside a branch, which leaves the region open for the
  statements after that branch.

Each of these can produce a dangling pointer with no warning. A program
without warnings is not proven memory safe.

## Optional lifetime proof

The lifetime proof is experimental and runs only from a source checkout:
`make install` and release payloads do not install `x2c-graph`. Build it in
the checkout with `make commands`.

`x2c-graph certify` checks selected entry points and the functions they can
call across the supplied source units. It applies the same region ownership
and parameter-effect rules as the compiler's local pass, then checks whether
every reachable memory effect is covered. A `proved` result establishes the
scoped lifetime invariant for those paths under the native effect assumptions
listed in the report. If a root hands storage to its caller or another owner,
the report lists the remaining release obligation.

The audit distinguishes a proven lifetime violation from an incomplete
proof. An unknown call, pointer cast or arithmetic, indirect storage access,
aggregate copy, or unmodeled scope ending is an obstacle, not a compiler
warning or error. A project may provide explicit native effect contracts to
the audit; they are assumptions of its result and do not change compilation.
The optional command and its contract format are described in the
[source graph reference](https://github.com/gwf/x2c/blob/main/commands/graph/README.md#conditional-lifetime-proof).
The proof concerns scoped ownership and lifetime. It does not establish
general C memory safety or correctness of emitted code.

## How the check works

Each function gets one summary of two facts: which of Scope and Pool storage
its result may use (possibly both), and where each parameter is sunk
(returned by identity, retained in the fresh result, placed into another
parameter's object or a static, or stored through an unknown pointer). The
summary distinguishes raw stores from known retaining operations so helper
calls preserve the ordinary, audit, and meta diagnostic boundary. The
summaries of a unit's functions are computed to a fixpoint because a caller's
facts depend on its callees' facts. Each round walks every
body with a stack of open regions and a map from each binding to its known
facts: its parameter index, the region it was born in, the local a pointer
was taken from, and whether a free has already ended it. The first round
that changes no summary walked every body against final summaries, so its
warnings are the ones reported.

An address taken with `&` belongs to the storage it names. The address of a
local, a parameter, or a compound literal belongs to the function's own
storage. An address reached through a pointer, such as `&box->value`, belongs
to whatever that pointer holds, so an address inside a parameter's object
counts as that parameter in the summary. A caller of a function that returns
`&box->value` therefore receives its own borrowed address as the result. An
argument to a reference parameter is the address of the object it names, so
`bind(object)` with `T &` is checked as `bind(&object)` with `T *`.

A `meta` function is walked the same way when it is defined, against the
summaries of the `meta` functions defined before it. A compile-time call
frees its locals when it returns, so a finding in a `meta` body is an error
and the definition is rejected; see
[Meta Functions](meta-functions.md). A native function outside the runtime table
described below takes a summary its signature implies; see
[Native modules](meta-functions.md#native-modules).

Summaries stay inside the unit. For a call into another unit, the pass uses
only a fixed table of runtime operations, such as a `Scope` allocator,
`cons`, `Array.push`, `Scope.move`, and `Array.list_free`. Summaries are not
written to the `.xi` interface. A dependent unit collects its includes before
those units are transformed, and parallel workers do not share transformed
units, so an interface summary would make a unit's warnings depend on input
order, the job count, and interfaces left by an earlier translation. As a
result, the pass reports no warning when a caller passes a region-born value
to a function in another unit that stores its argument into a static.

## Where the design sits

The region check is based on the ML Kit and Cyclone. The ML Kit inferred
regions and a region-annotated program from an unannotated one. Cyclone made
regions part of the type system of a C-like language and checked pointer
lifetimes against them. From the ML Kit, x2c takes the idea that regions are
the unit of deallocation; from Cyclone, the idea that a C program can be
checked against them. The regions are the ones the author wrote with
region `auto` and the `Scope.open` and `Scope.close` calls. The check adds
nothing to the program text and produces only warnings, except in compile-time code.

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

## Where to go next

- [Lifetime warnings](memory.md#lifetime-warnings) shows the warnings in
  ordinary code.
