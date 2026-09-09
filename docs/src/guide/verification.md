# Verifying Functions with C*

The optional `cstar` package lets a program annotate selected functions with
contracts, loop invariants, and calls to proof helpers, then check those
functions with the [C*](https://cstarlang.org/) symbolic executor and HOL
Light. Ordinary compilation ignores the annotations. The compiled program
contains no proof code and links no verification runtime.

This is an experiment over a small C-like subset of the language. It does
not verify the runtime, callers of the annotated functions, or termination.
Package prerequisites, the pinned C* release, and its licensing situation
are in `packages/cstar/README.md`.

## Annotating a function

An annotated unit imports the annotation macros and decorates a function
with its precondition and postcondition, written in C*'s assertion syntax.
Parameter names in a contract denote entry values; `__return` names the
result.

<!-- ignore: needs the cstar package and a running prover. -->
```x2c,ignore
$(import "../src/cstar.xmacro")

$cstar.verify("fact(x >= --2147483647i)",
              "fact(x >= 0i && __return == x || x < 0i && __return == --x)")
int absolute(int x) {
  if (x >= 0) return x;
  return -x;
}
```

Inside a verified body, five statement forms record proof positions:

- `$cstar.invariant("...")` decorates a `while` loop with a pure
  proposition over program variables. Each variable named there contributes
  its own ownership frame, `<name>_v` is its value at that point, and
  `<name>__pre` is its value on entry.
- `$cstar.invariant_sl("...")` decorates a `while` loop with a complete
  separation-logic assertion, including its `exists` binders and every
  `data_at` and `fact` it owns. It cuts the state only partially, so the
  surrounding frame survives. An array loop needs this form, because the
  array's contents are a ghost list the invariant rewrites each iteration.
- `$cstar.assert("...");` records an intermediate assertion.
- `$cstar.proof(step, "term", ...);` runs one of the session's own proof
  steps with logical term arguments.
- `$cstar.helper(name, "term", ...);` runs a helper from the companion
  file.

A function with pointer parameters names its logical ghost values with
`$cstar.verify_with("a_v:int, b_v:int", pre, post)`; the contract then
describes ownership with `data_at`. An array's contents are a ghost list,
written `"xs:(int)list"`.

## Array loops

The package ships the reusable steps of a left-to-right array fill, so a
clearing loop is four `$cstar.proof` calls around an ordinary store:

<!-- ignore: needs the cstar package and a running prover. -->
```x2c,ignore
$cstar.proof(fill_entry, "int_array p__pre", "n__addr:addr", "n__pre:int",
             "xs:(int)list", "0i:int");
$cstar.invariant_sl("exists i_v. ...")
while (i < n) {
  $cstar.proof(fill_before_store, "Tint", "p__pre:addr", "i_v:int",
               "n__pre:int", "xs:(int)list", "0i:int");
  p[i] = 0;
  $cstar.proof(fill_after_store, "Tint", "p__pre:addr", "i_v:int",
               "n__pre:int", "xs:(int)list", "0i:int");
  i++;
}
$cstar.proof(fill_exit, "i_v:int", "n__pre:int", "xs:(int)list", "0i:int");
```

One term argument, `Tint` or `Tchar`, selects the element type. Writing a
chosen value instead of zero changes only the value term. The steps
themselves are C* source in the package, not x2c, because they build HOL
theorems; `packages/cstar/README.md` lists all six.

Every annotation expands to a marker call while the function is parsed.
The `$cstar.verify` decorator records the function, erases the markers, and
returns the ordinary body, so the generated C differs from an unannotated
function only by empty statements. `$cstar.verify` must be the outermost
decorator: a later decorator that rewrites the body is refused, because the
recorded body would no longer be the compiled one.

## Proof helpers

A proof helper is an ordinary x2c function in the companion file
`<unit>.proofs.x`, next to the annotated unit. `$cstar.helper` passes it the
proof session first and the logical terms after, and it uses the package's
proof API to prove a fact and install it in the symbolic state:

<!-- ignore: needs the cstar package and a running prover. -->
```x2c,ignore
void twice_step(Cstar cstar, String claim) {
  cstar.add_fact(cstar.int_arith(claim));
}
```

The helper's name resolves when the generated proof program is compiled,
so the annotated unit needs no declaration of it. A missing or misused
helper is an ordinary compile error there.

A helper is a plain function rather than a method on `Cstar` because x2c
cannot define a method on a type an `import` supplies. The package's own
steps are methods, which is why `$cstar.proof` and `$cstar.helper` are
separate annotations.

## Running a verification

`cstar-verify` parses the unit with the compiler, reads the annotation
records, renders the admitted subset as a proof program, builds that
program with the ordinary driver, and runs it against a fresh prover
session. Each run uses a new temporary directory and its own
`hol_light_server`; nothing is cached, and a result describes that run.

```sh
make -C packages/cstar prepare tool
make -C packages/cstar verify        # the shipped examples
./packages/cstar/builds/cstar-verify path/to/unit.x
```

The command prints one line per requested function and exits with:

| Exit | Meaning |
| --- | --- |
| 0 | every requested function verified with no remaining obligation |
| 1 | at least one verification condition remains; each is printed with its source line |
| 2 | the unit was refused before any proof ran: an unsupported construct, a mismatched body, or no annotations |
| 3 | the run did not complete: a build failure, prover failure, timeout, a step the engine rejected, or a short function inventory |

A successful exit requires all of: every requested function was fed to the
engine, a complete final report, and empty `verification_conditions`,
`axioms`, and `strategies` arrays. A remaining axiom or strategy is a trust
obligation and never becomes a pass.

## What the subset admits

Verified bodies may use `void`, `int`, `unsigned`, `char`, `unsigned char`,
and pointers to those; constants, locals and parameters, scalar arithmetic
and comparisons, casts, address and dereference, and array indexing;
declarations, assignment through a name or an index, `i++` and `i--` as
whole statements, blocks, `if`, `while`, and `return`; and direct calls to
functions verified earlier in the same unit. The first construct outside
that set stops the run with its source location. Nothing outside the set is
treated as having no effect.

The trusted base is HOL Light and its theory, the C* symbolic executor and
proof runtime, the pinned proof libraries, the package's array proof
library, the adapter that renders x2c syntax as engine segments, x2c
itself, and the C toolchain.
