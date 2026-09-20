# x2c REPL research spike

A runnable local adapter over the ordinary compiler and its existing
compile-time lowering. It retains one compiler, binding scope, Lisp session,
and unit Context across submissions. It does not replay accepted source or
previous effects. This is research code, outside the CLI and repository gates.

Started from `origin/dev` at `f3aa43a5f1dcc3f9860496a9a7cf7080c6edec89`.
All authored changes are in this directory. Production compiler, runtime,
bootstrap, and validation targets are unchanged.

## Run

From the repository root, after the ordinary fresh-worktree setup:

```sh
mkdir -p debug
make build-safe >debug/bootstrap.log 2>&1
tools/repl-spike/run
```

The launcher builds a small compiler archive from stage 0 objects excluding
`main.o`, then compiles the adapter. It keeps products under
`unittest/build/repl-spike/`. A ready worktree only needs the last command.

```sh
tools/repl-spike/run < tools/repl-spike/demo.txt
tools/repl-spike/run --dump < tools/repl-spike/demo.txt
tools/repl-spike/run --build-only
python3 tools/repl-spike/check.py
```

`--dump` shows the typed AST and lowered Lisp. `--stats` reports Lisp/word
machine counters at exit. Build output precedes the session in the launcher;
the built executable can be run directly with its seed file:

```sh
unittest/build/repl-spike/repl unittest/build/repl-spike/seed.x --stats
```

One declaration or function is submitted at a time. Executable input may
contain several statements. Semicolons are required. `:cancel` discards a
pending multiline input; `:quit` exits. EOF with pending input exits with
status 1. Rejected or failed individual inputs report an error and continue.

## Demonstrated result

The checked demo submits these lines successively, including the multiline
function and malformed declaration:

```c
int total = 10;
total += 2;
total;                         // => 12
int plus(int x) { return total + x; }
plus(3);                       // => 15
int twice(int x) {
  return plus(x) * 2;
}
twice(4);                      // => 32
int broken = ;                 // parse error
twice(4);                      // => 32
total = 20;
twice(4);                      // => 48
```

The final expression of an executable input prints its typed value with
`Var.repr`. Assignment/update statements print `ok`. Defined functions print
`defined NAME`. Other statements run through the same lowering and print
`ok`; a void function currently returns the lowering's zero sentinel.

## Binding, value, and lifetime decisions

Top-level declarations create file-scope bindings in the persistent compiler
scope. This is a REPL policy; ordinary x2c script hoisting is a different
context. Parameters and function locals retain their ordinary lexical scope.

Each initialized simple binding becomes a typed assignment thunk, executed
once. Existing `C.gread`/`C.gwrite` operations use stable compiler binding IDs
in the session's `C._globals` map. Later functions observe the current value
when called. Initializers can call earlier functions and perform effects.
Top-level declarations without initializers or with declarator modifiers are
outside this spike.

Scalar conversion uses existing comptime lowering and `Var.convert`: for
example, `unsigned char c = 258; (int)c;` answers 2. Tags remain visible in
printing: the byte itself prints as a character and lengths may print with
an unsigned suffix. Mutable Arrays preserve their identity across inputs.

Redeclaration of a user value or function is rejected; use assignment to
update a value. Function replacement and mutually recursive forward
prototypes are outside the spike. Self recursion and calling earlier
functions work. Names beginning `__repl_` are reserved by the adapter.

Parse and lowering rejection roll back semantic bindings. The adapter also
restores parameter capture and scope depth: ordinary one-shot parsing leaves
these behind on some malformed function paths. Runtime failure keeps effects
that already happened. Declarations commit before initialization: after
`int y = 1/0;`, `y` exists and reads the current lowering's unwritten-global
zero until assigned. This is an explicit prototype policy, not a proposed
language guarantee. A production REPL needs a decision on failed declaration
initialization and whether an uninitialized binding may be read.

The unit Context stays alive until exit because lowered lambda syntax and
values may borrow its canonical storage. Lisp owns its evaluated allocations.
Inputs, failed parse attempts, and transient thunks accumulate storage for
the session lifetime. Long-running reclamation is unresolved.

## Subset and completeness

Focused checks establish integer arithmetic and narrowing, assignments,
conditionals, for loops, self recursion, cross-submission function calls,
String values and length, List literals/indexing, and Array construction,
mutation, and indexing. Other constructs are accepted only when the existing
lowering can execute them; this is not a claim of general C execution parity.

Known boundaries:

- `goto` and many native operations are declined by existing lowering.
  The empty Map initializer `{}` was also declined in a probe.
- Native pointer/ABI operations, arbitrary C libraries, aggregates,
  typedefs, imports, protocol definitions, user macro/meta definitions,
  preprocessor directives, and direct Lisp escapes are outside the spike.
- `const` and `volatile` are rejected: a probe showed that the current
  compiler/lowering composition allowed a write to a const binding, whose
  rejection ordinarily depends on native compilation.
- Untyped identifier references are rejected by the adapter. The compiler
  can defer native name resolution, but the lowering otherwise reads such a
  name as an unwritten global and incorrectly answers zero.
- The existing lowering maps `Var void` to Lisp nil, losing its distinction
  from an empty List. General reference/lifecycle parity is not established.
- A one-million-step Lisp call budget interrupts a runaway loop and leaves
  prior values usable. Native callbacks are not a preemptible sandbox.

Lexical incomplete input comes from `Tokenizer.status`. Otherwise the
adapter attempts ordinary parsing and retains input when a parse diagnostic
occurs at the source boundary. `expected scalar type` at that boundary also
means more tokens may complete a parameter list. It never treats evaluation
failure as incomplete input. This is a parser-based heuristic: the compiler
has no dedicated complete/incomplete/error submission API, and an unrepaired
prefix may keep prompting until `:cancel`. It cannot decide that a following
line intends to extend an already complete construct such as an `if`.
Statement diagnostics include the synthetic wrapper's extra line.

## Evidence and architecture review

`check.py` passes 18 focused recovery/subset checks, then compiles the same
three function examples natively and compares results: `15`, `32`, `499500`.
The interpreted comparison reports 20 Lisp calls, 7 word-machine entries,
and zero machine errors. Separate recovery checks cover malformed bodies and
parameter lists, unknown identifiers, unsupported lowering, runtime division
by zero, duplicate names, and the runaway-loop budget.

On this macOS checkout, the latest warm-process startup median was 171.2 ms
across seven runs. A batch of 1,002 submissions took 338.1 ms, about 0.167 ms
per input after subtracting the startup estimate. These are exploratory wall
times including process/input/output overhead, not a performance benchmark.
Logs are under `debug/repl-build.log` and `debug/repl-check.log`.

The 238-line adapter is enough to demonstrate composition. It uses these
existing owners:

| Responsibility | Source |
| --- | --- |
| Prelude, shared macro libraries, unit lifetime | `src/frontend.x` |
| Tokenization and semantic transactions | `src/compiler.x` |
| Ordinary declarations, function bodies, typing and binding | `src/parse.x`, `src/expressions.x` |
| Typed AST to Lisp | `Compiler.lower_comptime`, `src/comptime.x:1873` |
| Persistent global table and scalar conversions | `etc/comptime.xlisp` |
| Session evaluator and automatic word-machine execution | `lib/lisp.x` |

Design review: use direct `lower_comptime` plus Lisp evaluation. The ordinary
`install_comptime` path has provisional installation and a filename/name
cache unsuitable for interactive definition replacement. Keep stable binding
IDs instead of rebuilding the unit or remapping globals. Reuse typed AST
expressions for initializer thunks and result returns. The extra unresolved
identifier check prevents a reproduced wrong result; it is not a replacement
binder. Keep the spike's policy checks at the adapter boundary.

**Recommendation: continue.** No new evaluator is required for a useful
value-oriented x2c REPL. The next bounded step should establish a supported
submission API with explicit completeness and parser-state recovery, then
resolve failed initialization and type/value parity at native-dependent
boundaries. Definition replacement and memory reclamation need separate
lifetime decisions. Full-language execution should not be promised from this
prototype. This work is local-only; publication and production integration
have not been validated or authorized.
