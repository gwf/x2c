# x2c REPL research spike

A runnable local adapter over the ordinary compiler and its existing
compile-time lowering. It retains one compiler, binding scope, Lisp session,
and unit Context across submissions. It does not replay accepted source or
previous effects. This is research code, outside the CLI and repository gates.

Started from `origin/dev` at `f3aa43a5f1dcc3f9860496a9a7cf7080c6edec89`.
The second iteration adds an optional submission boundary to the compiler
parser and fixes its parameter/block cleanup paths. Runtime and comptime
coverage, bootstrap, and validation targets are unchanged. Comptime coverage
is being developed separately.

## Run

From the repository root, after the ordinary fresh-worktree setup:

```sh
mkdir -p debug
make build-safe >debug/bootstrap.log 2>&1
make build >debug/repl-session-compiler.log 2>&1
tools/repl-spike/run
```

The launcher builds a small compiler archive from stage 0 objects excluding
`main.o`, then compiles the adapter. It keeps products under
`unittest/build/repl-spike/`. A ready worktree with the current stage 0 compiler only needs the last
command. This local branch changes parser sources without refreshing bootstrap;
`make build` is needed after the initial bootstrap build.

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

Parse and lowering rejection roll back semantic bindings. The compiler's
`parse_submission` operation restores parameter capture and scope depth;
parameter and block parsers also unwind their scopes at their own boundaries.
The terminal no longer manipulates parser fields.

A declaration publishes only after all its initializers succeed. For example,
`int a=next(), b=1/0;` publishes neither `a` nor `b`, but any effect `next()`
made on an existing variable remains. Provisional cells are removed before
rollback allows their binding IDs to be reused. Both names may then be
declared again. Runtime failures in ordinary statements likewise preserve
completed effects on existing values.

The unit Context stays alive until exit because lowered lambda syntax and
values may borrow its canonical storage. Lisp owns its evaluated allocations.
Adapter scratch Arrays, tokenization containers, and outer transaction copies
are freed after each call. Lowering scratch maps have their own short lifetime.
Canonical syntax, compiler caches, lexical maps, and Lisp allocations remain
session-lived. General
per-input reclamation requires explicit compiler/Lisp root ownership; wrapping
submit in a temporary Context would leave dangling references.

Direct tests close and reopen three used sessions and compare them with three
empty frontend sessions. No scopes remain open, and post-close allocation
growth matches the measured empty-frontend baseline. Collection alone adds ten
live allocations per round in this checkout; this reproduces without parsing
or REPL use. Its cause is not diagnosed here. These tests do not claim complete
memory stability.

## Submission API

`session.x` is reusable without the terminal. The caller first opens a
`ParsedUnit` with the normal frontend and initialized macro session (the
launcher's seed is `$(begin)`), then keeps it open while using results:

```c
ReplSession session = ReplSession.new(unit.compiler);
ReplResult result = session.submit("int n = 10;");
result = session.submit("n + 2;");
// result.status == <value>, result.value == 12
```

`ReplResult.status` is one of:

| Status | Meaning |
| --- | --- |
| `incomplete` | More source may complete the candidate; no bindings publish. |
| `rejected` | Syntax, type, adapter policy, or lowering rejection. |
| `defined` | A function definition was installed; `name` identifies it. |
| `executed` | Initialization or statements completed without a displayed value. |
| `value` | Execution completed with the expression's typed `value`. |
| `failed` | Execution failed; `cause` records the evaluator error. |

Results include ordinary compiler `diagnostics`, their `source` text, an
adapter `message`, and optional tracing data (`syntax`, `lowered`). `submit` prints nothing and does
not retain a pending prefix. Values borrow the unit Context until `unit.close`.
The terminal selects `result.source` as `compiler.text` while rendering its
diagnostics. The adapter restores the compiler's previous tokenization state
before returning; retained results can be inspected after later submissions.

`Compiler.parse_submission(end_position)` operates on the current token
stream. It owns single-item parsing, supplied-input boundaries, and parser
scratch restoration. The caller owns the semantic transaction so publication
can wait for successful initialization. The terminal is now a client of
`ReplSession.submit`; `api-check.x` is a separate direct API client.

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

Lexical incomplete input comes from `Tokenizer.status`. Parser operations
that require another token call `Compiler.require_input`; reaching the optional
supplied-input boundary raises `incomplete`. Ordinary files leave that boundary
unset and keep their usual diagnostics. The adapter no longer inspects error
messages or guesses completeness from a diagnostic's category and position.
Semantic and evaluation failures are not reclassified as incomplete.

The hooks cover operands, types, field names, required delimiters, and
declaration endings used by this subset. Custom macro/type/import/enum and
some `with`/catch grammar paths have not been completed for incremental input.
This remains a subset API. It cannot infer that a following line intends to
extend an already complete `if`; put such a construct in a block.
Statement diagnostics include the synthetic wrapper's extra line.

## Sustained sessions

[The retention experiment](retention.md) compares eight workloads and records
before/after evidence. Giving outer transaction copies a temporary Scope
reduces fixed-update peak RSS from 155.5 to 62.2 MiB at 1,000 inputs. All eight
workloads complete 5,000 inputs. Full submissions still retain other storage;
this is not bounded-memory execution.

```sh
python3 tools/repl-spike/retention.py 5000
```

The session requires source-fact collection to be disabled because those
records retain temporary map identity. Ordinary compiler callers keep the
existing transaction behavior.

## Evidence and architecture review

`check.py` runs the direct API client and 18 terminal recovery/subset checks,
then compiles the same three function examples natively and compares results:
`15`, `32`, `499500`. The direct client checks 22 submission outcomes across
three fresh sessions, including failed multi-binding initialization and ID
reuse. The interpreted comparison reports 20 Lisp calls, 7 word-machine
entries, and zero machine errors.

The shared parser changes also pass `make verify-fixtures`: 747 compiler
fixtures and 1,746 expected artifacts, plus that target's existing probes.
Expected artifacts were not rewritten.

Warm-process startup is approximately 170 ms on this checkout. The latest
1,002-input batch took roughly 330 ms, about 0.16 ms per input after subtracting
startup. These exploratory wall times include process/input/output overhead.
Logs are under `debug/repl-session-build.log`, `debug/repl-session-check.log`,
and `debug/repl-parser-fixtures.log`.

The session adapter composes these owners:

| Responsibility | Source |
| --- | --- |
| Prelude, shared macro libraries, unit lifetime | `src/frontend.x` |
| Tokenization, semantic transactions, required-input signal | `src/compiler.x` |
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

**Recommendation: continue with lifetime ownership and upstream comptime
integration.** The structured session, explicit parser boundary, and failed
initializer policy now work. Fine-grained reclamation needs a real ownership
boundary; function replacement remains a separate semantic decision. Consume
comptime improvements from the other session and rerun native/interpreted
comparisons rather than implementing those features here. This work remains
local; bootstrap refresh and full publication validation have not been run.

The [long-session assessment](long-session.md) records the latest ownership
fixes, 50,000-input mixed sessions, retained-result checks, and the remaining
design decisions before production integration.
