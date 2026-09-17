# The Region Model

## The invariant

A value allocated inside a region must not be reachable after that region
ends, and the four kinds of place that outlive a region are the function's
result, storage declared outside the region (an outer local, an object a
parameter points at, or a static), an object owned by an outer or sibling
region, and any pointer the compiler cannot name, including one a called
function stores into on the caller's behalf.

A region is a `$scope()` block, a `Scope.retain` and `Scope.release` pair, a
`$scope(&slot)` push, a `List.pool_retain` bracket, or an `$auto` local.
`src/regions.x` reads these forms before the transform driver lowers them,
so a region is still the call that opens it and the `defer` beside it that
closes it.

## Exemptions

Three ways of leaving a region are not violations, and each is sound for a
different reason.

A canonical value is owned by a `List` pool, not by a `Scope`, so ending a
region never frees it. `String`, `List`, and `Symbol` results therefore
cross a region boundary unremarked. The exception is a value consed inside a
`List.pool_retain` bracket, which that pool does free, so the pass tracks
pool-born values exactly as it tracks scope-born ones.

`Scope.move` and `Context.export` change the storage's owner. After the
move, the region the pass was tracking no longer holds the allocation, so
the region ending says nothing about it. The pass stops tracking the value
at the move and reports nothing later, which is why moving into a caller's
slot is the ordinary way to return mutable storage.

A typed conversion copies. Assigning a `Block`, `Buffer`, or `Array` into a
`String` or `List` declaration produces a new canonical value with its own
owner rather than an alias, so the target does not inherit the region. The
pass treats the declared type as the deciding fact, the same way the
converter does.

## What the warnings do not cover

The check reads lexical regions and the storage it can name. It makes no
claim about:

- storage from plain `malloc` or a C library;
- pointer arithmetic and casts through raw C types;
- values reached through a field of a stack `struct`, which the pass sees as
  one storage rather than as separate fields;
- callbacks and function pointers, including entry points a Lisp binding
  calls;
- `Scope.free` and `Scope.realloc`, whose effect on other aliases of the
  same allocation is invisible here;
- `Context` regions, which are not modeled.

Each of these can still produce a dangling pointer that translates in
silence. The pass is a report on one pattern, and calling a program memory
safe on its evidence would mean ignoring this list.

## How the check works

Each function gets one summary of three facts: whether it allocates into the
caller's active region, whether its result is fresh storage, and, for each
parameter, where that parameter is sunk (returned, into another parameter's
object, into a static, or through an unknown pointer). A unit's functions
reach a fixpoint over those summaries, since a caller's facts depend on its
callees'. Reporting runs once afterwards, when every summary is final, and
walks each body with a stack of open regions and a map from binding to what
is known about it: its parameter index, the region it was born in, the local
a pointer was taken from, and whether a consuming call has already ended it.

A summary that is not empty is published in the unit's `.xi` interface as a
`("region-summary" NAME)` contribution, beside the signature, and a
dependent unit reads it from its symbol table the way it reads a type. The
consequence is that a change inside one function can surface a warning in a
different unit: teaching a callee to store its argument into a static makes
every caller that hands it a region-born value report. That is the intended
behavior for a summary-based check, and it is the reason the interface
format version moves when the summary shape changes.

## Where the design sits

The ancestors are the ML Kit and Cyclone. The ML Kit inferred regions and a
region-annotated program from an unannotated one; Cyclone made regions part
of the type system of a C-like language and checked pointer lifetimes
against them. x2c keeps the ML Kit's idea that regions are the unit of
deallocation and Cyclone's idea that a C program can be checked against
them, but infers nothing into the program text and rejects nothing: the
regions are the ones the author wrote with `$scope` and the retain and
release calls.

Rust and Swift make the opposite choice about where the information lives.
Both put ownership and lifetime in the signature, which lets every call be
checked locally against a declared contract and makes a violation an error.
x2c has no lifetime annotations, so the same information has to be derived,
and the derived facts are weaker than a declared contract. The trade is that
existing C-shaped code compiles unchanged and the check can only warn.

Go's escape analysis and Infer are the closest relatives in method. Go
computes per-function escape facts and uses them to choose between stack and
heap allocation rather than to report anything to the author. Infer computes
per-procedure summaries and propagates them across a program to report
memory and lifetime defects. x2c's pass is the second shape used for the
first kind of fact: summaries per function, carried between units through
the same artifact that carries signatures, and spent on warnings rather than
on an allocation decision.
