# cstar

Experimental. Annotate selected x2c functions with contracts, loop
invariants, intermediate assertions, and proof steps, then check them with
`cstar-verify`, which reports the obligations that remain at their source
locations. The annotations cost the compiled program nothing: they leave no
code, no declarations, and no linked verification runtime.

The backend is [C*](https://cstarlang.org) 0.5.7 -- its symbolic executor, its
HOL Light prover server, and the MIT proof libraries that ship with
`cstar_examples`. This package writes no symbolic executor, theorem kernel,
or assertion language of its own; assertions are terms in C*'s logical
syntax.

Milestones 2 to 5 of [the plan](../../plans/x2c-cstar-verification.md).

## The applications

```sh
make -C packages/cstar prepare build tool run test verify
```

- [examples/abs.x](examples/abs.x): bounded absolute value. One contract, one
  branch.
- [examples/twice.x](examples/twice.x): two counted loops. `twice` needs only
  its invariant and one intermediate assertion. `product` multiplies by
  repeated addition, so its back edge needs one ring identity the entailment
  prover will not find; the companion helper in
  [examples/twice.proofs.x](examples/twice.proofs.x) supplies it.
- [examples/swap.x](examples/swap.x): exchanging two owned `int` cells, with
  ghost parameters naming the caller's values.
- [examples/scale.x](examples/scale.x): one verified function calling
  another. The engine uses the callee's contract, never its body.
- [examples/clear.x](examples/clear.x): clearing an `int` buffer and a `char`
  buffer with the same four proof steps.
- [examples/fill.x](examples/fill.x): the same steps again, writing a chosen
  value instead of zero. Nothing in the proof library changed to accept it.

Four more examples must not verify, and `make verify` checks their exit
codes: [abs-unbounded.x](examples/abs-unbounded.x) drops the `INT_MIN`
exclusion and leaves the overflow obligation (1);
[swap-unowned.x](examples/swap-unowned.x) asks for only one of the two cells
and the engine refuses the second read (3);
[clear-offbyone.x](examples/clear-offbyone.x) loops to `i <= n` and stores
one cell past the array the contract owns (3); and
[fill-falseinv.x](examples/fill-falseinv.x) states an invariant the loop
never establishes (3).

Each example is also an ordinary program. `make run` builds and runs all ten
with no package archive and no verification runtime linked.

## The annotation surface

Import the macros from wherever the package sits relative to the annotated
file; a compile-time import resolves against the importing file's directory,
not the `--x-include-dir` list.

```x2c
$(import "../src/cstar.xmacro")
```

- `$cstar.verify(pre, post)` decorates a function, outermost. Both
  arguments are complete assertions.
- `$cstar.verify_with(ghosts, pre, post)` adds logical ghost parameters,
  written as one list such as `"a_v:int, b_v:int"` or `"xs:(int)list"`.
- `$cstar.invariant(text)` decorates a `while` with a pure proposition.
- `$cstar.invariant_sl(text)` decorates a `while` with a complete
  separation-logic assertion.
- `$cstar.assert(text);` cuts the state at any statement position.
- `$cstar.proof(step, args...);` runs one of the session's own proof steps.
- `$cstar.helper(name, args...);` runs a helper from the companion file.

`pre` and `post` are complete assertions in the pinned backend's syntax:
`fact(...)` for pure facts, `**` and `data_at` for ownership, `__return` for
the result.

The two invariant forms are different assertions, not two spellings of one.
`$cstar.invariant` takes a *pure proposition* over program variables: each
variable named there contributes its own ownership frame automatically,
`<name>_v` is its value at that point, and `<name>__pre` is its value on
entry. That is C*'s `mk_simple_invariant` form, and it suits the scalar
examples. `$cstar.invariant_sl` takes the assertion itself, including its
`exists` binders and every `data_at` and `fact` it owns, and cuts the state
only partially, so the surrounding frame survives. The array examples need
that form, because an array's contents are a ghost list the invariant has to
rewrite on every iteration.

`$cstar.verify` must be the outermost decorator. A decorator applied after it
rewrites a body the record no longer describes, and `cstar-verify` refuses
the file rather than proving something about code the compiler did not keep.

### Proof steps and companion helpers

`$cstar.proof` names a method on the session. The package ships six, the
reusable steps of a left-to-right array fill, implemented as C* in
[proof/x2c_array_helpers.c](proof/x2c_array_helpers.c) and reached from x2c
through [src/cstar.x](src/cstar.x):

- `fill_entry`: the length is nonnegative, and the whole array is the
  cursor form at index 0.
- `fill_before_store`: the index is in range, and its cell is a literal
  `data_at` a plain assignment can write.
- `fill_after_store`: the written cell is re-folded, the functional cursor
  advances, and the bounds hold for `i + 1`.
- `fill_index_bound`: the index half of `fill_before_store`, without
  opening a cell.
- `fill_advance`: the cursor half of `fill_after_store`, without closing
  one.
- `fill_exit`: at `i = n` the cursor form collapses to the finished list.

One term argument, `Tint` or `Tchar`, selects the element type; every
list-level step is shared between them. `clear.x` and `fill.x` are the same
four calls with a different value term.

`$cstar.helper` names an ordinary function in the companion file
`<stem>.proofs.x` beside the annotated unit. It receives the session first
and its logical terms after:

```x2c
static void twice_step(Cstar cstar, String claim) {
  cstar.add_fact(cstar.int_arith(claim));
}
```

The two annotations exist because x2c cannot define a method on a type an
`import` supplies: `void Cstar.twice_step(Cstar cstar, ...)` in a consumer
unit is a parse error. A companion helper is therefore a plain function that
takes the session, and `$cstar.helper` passes it.

The annotated unit needs no declaration of a helper and no declaration of the
annotation marker: `$cstar.verify` erases every marker, so nothing reaches C.
[src/cstar-annotations.x](src/cstar-annotations.x) declares the marker
anyway, and including it turns an annotation written outside a verified
function into a link error naming `cstar_marker` rather than an
implicit-declaration compile error.

## The verified subset

Anything outside this list stops the file with `unsupported: <what> at
<file>:<line>`. Nothing is skipped silently.

- Types: `void`, `int`, `unsigned`, `char`, `unsigned char`, and pointers
  to those.
- Expressions: constants, locals and parameters, arithmetic and
  comparisons, conversions, address-of and dereference, indexing.
- Statements: declarations, assignment through a name or an index,
  `i++`/`i--`/`++i`/`--i` written as a whole statement, blocks, `if`/`else`,
  `while`, and early `return`.
- Calls: direct calls to a function verified earlier in the same file.

An increment inside an expression stays unsupported, because its place in the
evaluation order is not part of the admitted subset. Structs, floating point,
function pointers, recursion, `goto`, `break`/`continue`, allocation,
`defer`, lambdas, Scope and Context operations, Error transfers, protocols,
and container literals are all outside it.

## Running a check

```sh
X2C=../../builds/0/x2c X2C_PACKAGES=.. CSTAR_HOME=$PWD/deps \
  ./builds/cstar-verify examples/clear.x
```

`cstar-verify` parses the file with the real compiler frontend, reads the
records the macros left in the compile-time Lisp session, proves that each
recorded body is the body the compiler kept, renders the admitted subset as a
proof program, builds that program with the ordinary x2c driver, and runs it
against its own prover session in a fresh directory. Nothing is cached: a
result describes that run, not the file.

| Option | Effect |
| --- | --- |
| `--emit` | print the generated proof program and stop; needs no prover |
| `--port N` | use an already running server instead of starting one |
| `--keep` | keep the run directory |
| `-I DIR` | an extra x2c include directory |

`CSTAR_PORT` is the environment form of `--port`. Without it, each run starts
its own `hol_light_server` on a port derived from the driver's pid, waits for
its log line, and kills it afterwards; a cold start costs about 14 seconds,
so reusing one server is much faster for repeated runs. Readiness comes from
the log line and never from a port probe, because macOS Control Center also
listens on the default port 7000.

- `0` verified: every requested function was fed completely and no
  obligation remains.
- `1` obligations remain; each is printed with its source line.
- `2` unsupported, or the record does not match the compiled body. Nothing
  was proved.
- `3` not completed: a build failure, a prover failure, a timeout, a step
  the engine refused, or fewer functions processed than requested.

An empty report is not enough on its own. The generated program records each
function's completion and refuses success when the inventory is short, which
is what distinguishes 3 from 0.

With a warm server a scalar example takes about 0.4 s end to end and an array
example about 1.5 s. About 0.2 s of every run is the cost of linking the
array proof objects, which the package links uniformly; the array *theory*
costs about 0.7 s more to build, so a session loads it only when the file
uses an array step.

## Prerequisites and the dependency

`make prepare` downloads the pinned artifacts and builds the proof-library
objects the package links. The prepared prefix is about 230 MB and stays in
the shared cache; preparing it from an already downloaded archive takes about
13 seconds. macOS arm64 only, and tested there.

| Source | Pinned |
| --- | --- |
| C* release, darwin-aarch64 | v0.5.7, sha256 `f8fb646d` |
| cstar_examples | commit `32d61571` |
| cstar_stdlib | commit `7e8662b8` |

`dependency.json` holds the full hashes and URLs.

From the release the prefix keeps `include/`, `lib/libcstar.a`,
`lib/libsac.dylib`, `lib/clang/` and `bin/{cstarc,cst_clang,hol_light_server}`.
`cst_clang` is 165 MB and cannot be replaced by the host clang: it is the
only preprocessor that understands `#cst_include`, and `cstarc` needs it plus
the `lib/clang` resource directory to build the proof libraries. `cst_clangd`
and `cstar_mcp` are not installed.

Twelve MIT proof objects are built with `cstarc verify --cl` and initialized
in this order: `proof_user`, `proof_sl`, `proof_backward`,
`proof_backward_sl`, `proof_symexec`, `userlib/qcp/veriftime`,
`tutorial/common` (for `mk_simple_invariant`),
`userlib/operational/operational`, then the array theory
`array/lib/{list,array_core,index,array}`. `proof/x2c_array_helpers.c` is
this package's own C* source, so the Makefile builds it rather than the
dependency manifest; `cstarc` resolves every `#require` against its project
root, so it runs in the prepared `cstar_examples` tree and reads the package
file by absolute path.

The release objects are built for a newer macOS than the current SDK targets,
so linking a proof program prints `built for newer 'macOS' version` warnings;
they are expected.

The C* core release ships no LICENSE file and states no terms. Gary made the
explicit project decision on 2026-09-09 to proceed anyway, for an
experimental package that downloads the release into a local dependency cache
and redistributes none of it. [LICENSES/NOTICE](LICENSES/NOTICE) records that
decision and the MIT terms of everything else.

## What is trusted, and what is not proved

A successful check establishes partial correctness and the backend's safety
obligations for each explicitly selected function, under its precondition and
the admitted target model (macOS arm64, 8-bit bytes, 32-bit `int`, 64-bit
pointers, little endian). It does not prove termination, the correctness of
arbitrary callers, or anything about an entire executable. Nothing outside an
annotated function is checked, including the `main` each example ships.

Trusted: HOL Light and its baseline theory, the C* symbolic executor
(`libsac`) and its report, the MIT proof libraries, this package's array
proof library and AST adapter, x2c itself, and the C toolchain. Process
separation from the prover is not a defense against native proof code
corrupting its own in-process executor or report.

## Layout

- [src/cstar-0.5.7.h](src/cstar-0.5.7.h): the pinned plain-C surface. x2c
  cannot parse the upstream headers, which reach a C++ `constexpr` region, so
  this shim restates the declarations. One rename: `range` collides with an
  x2c name and is `cst_range` here.
- [src/cstar.x](src/cstar.x): `Cstar`, the proof session -- entry and exit,
  term parsing, program assertions, the arithmetic rules helpers use, the
  array proof steps, per-function completion, and the verdict.
- [src/cstar.xmacro](src/cstar.xmacro): the annotations and their records.
- [proof/x2c_array_helpers.c](proof/x2c_array_helpers.c): the array-fill
  proof steps, written in C* and compiled by `cstarc`.
- [tools/adapter.x](tools/adapter.x): the admitted subset as builder calls.
- [tools/cstar-verify.x](tools/cstar-verify.x): the command.
