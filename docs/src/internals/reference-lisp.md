# Literate Lisp in x2c

[The reference interpreter][source]
implements x2c Lisp in one source file. It owns its reader, environments,
closures, special forms, native registry, and standard vocabulary. Evaluation
recurses over ordinary values; it never constructs a Lisp session, calls the
production evaluator, or uses its call-frame machinery.

Build it from the repository root:

```sh
./builds/0/x2c build --output /tmp/reference-lisp \
  examples/programs/literate-lisp.x
/tmp/reference-lisp --selftest
/tmp/reference-lisp -e '(map (lambda (x) (* x x)) (list 1 2 3 4))'
/tmp/reference-lisp examples/data/reference-lisp/showcase.xlisp
```

With no arguments it reads forms from standard input, prompting when attached
to a terminal. It accepts multiline input and continues after a failed form.
The executable needs no initialization file or repository-relative lookup.
The source also stands alone: its standard vocabulary is an ordinary quoted
List literal, evaluated by this interpreter at startup. An explicit `import`
reads the file requested by the Lisp program.

## Reading the source

View this example at 120 columns. Top-level block comments explain Lisp;
these comments stay within 75 columns and code within 79 columns. Terse line comments begin at
column 81 and explain x2c syntax, conversions, and lifetime rules beside their
uses. Notes beside the quoted standard library describe its runtime Lisp
forms. Block comments begin at the left edge.

Start with `Interp.eval`, then `Interp.special`. The first reads
like the evaluation rule: resolve an atom, return a literal, or evaluate a
call. The second matches the grammar directly: `(quote form)`, `(def name
form)`, `(lambda parameters body)`, and the other special forms. A matched
shape supplies its parts; separate error helpers describe rejected forms.
The small `$fail` statement macro constructs the ordinary `raise` syntax from
a cause, an operation, and the remaining field/value pairs. Each call keeps
its diagnostic details visible and preserves their value types and order.

`Interp.apply` receives values. Only `eval` decides which arguments to
evaluate: ordinary calls evaluate left to right, while a macro receives its
raw argument forms. Native argument marshalling lives with the native
operations, so it does not interrupt the evaluator's rules.

`Fn` is a closure: parameters, a body, captured values, and a macro flag. It
uses the ordinary `Var` value tag `lambda`, preserving sorting, type queries,
and native diagnostics. The record is defined entirely here; no
production `Lambda` object or protocol is used.

`Env` is a stack-local link and a Map of bindings. Call bindings are
freed when the call returns. Closure records and their capture Maps remain in
the session Scope. Capturing copies a Var, preserving the identity and
ownership of its referent. Ordinary String and List pools own canonical data.

These private records use plain structs. Class defaults would require extra
initialization and comparison methods for their Map fields; the evaluator
needs neither generic record boxing nor field comparison. `foreach` handles
element traversal. The remaining `for` loops follow environment links or keep
the parameter tail needed to bind a dotted rest argument.

Quasiquotation has two operations with distinct results: `quasiquote` returns
one value; `quoted_elements` builds a containing List from the values
contributed by its actual elements. An active `,@` can contribute several
elements. The nesting depth determines when an unquote becomes active.
`quoted_elements` walks siblings once, recursing only into nested forms. A bare
`unquote`, `unquote-splicing`, or `quasiquote` atom inside an element sequence remains
data; only a List headed by that name has quotation syntax. For example,
`` `(a unquote (+ 1 2)) `` returns `(a unquote (+ 1 2))`, and
`` `(a quasiquote ,(+ 1 2)) `` returns `(a quasiquote 3)`.

`Reader.scan` tokenizes one source batch. `Reader.read` returns successive
forms, using recursive descent for Lists and reader prefixes. End of input is
`void`; an unfinished or malformed form raises an error at its source
position. Token storage has its own temporary Scope, while the forms outlive
it. The REPL retains unfinished input and resumes from that form's start.
`Repl.read_line` handles prompts, line input, and EOF. `Repl.read_unit` calls
it when needed, then handles tokenization and parsing. It returns one form
or `void` when no form is ready, setting `done` at EOF. The `storage` scope owns
the tokens between forms and is released before the source buffer changes.
The single loop in `_repl` calls `read_unit`, passes the form to `Interp.eval`,
and prints the result. Evaluation errors are caught per form.

`_install_natives` is one table of Lisp names, `bind` spellings, and ordinary
x2c functions. A native whose Lisp name is `()` is available through `bind`
without being installed globally. Function conversion supplies fixed native
signatures; the small `$rest` macro states the shared convention for native
functions that take every argument as a List. These are compile-time x2c
facilities, not another runtime evaluator. The `lisp_*` strings are
compatibility names; their implementations belong to this file or ordinary
runtime modules.

The static `_stdlib` List supplies the remaining macros and higher-order
functions in Lisp itself. x2c hoists its initialization; it needs no accessor
function. Native definitions appear only in the table, rather than being
declared again in this List. The few text adapters that return `Var` preserve
signatures printed in Lisp error messages.

The source uses ordinary runtime collection and pattern operations, including
`List.match` and replacement. Those operations retain their normal runtime
implementation; this example replaces Lisp evaluation, not x2c's collection
or pattern engine.

## Compatibility

The reference follows x2c Lisp, including behavior that differs from Scheme:

- Only the empty List is false; zero and the empty String are true.
- Ordinary arguments run left to right. Macros receive unevaluated forms.
- Special forms are callable identities, so aliases and shadowing work.
- Closures capture local values where they are made. Calls resolve parameters,
  captures, globals, and reserved names, without
  searching caller locals. Globals remain visible after rebinding.
- `def` writes globals. `eval` evaluates its supplied expression globally.
- `apply` consumes evaluated values and rejects macros and special forms,
  except for the built-in `apply` itself.
- `bind` looks up a fixed native registry; repeated lookup preserves identity.
- Completed effects remain when a later form fails to read or evaluate.

Native calls use x2c's existing checked `Func` boundary. Deliberate Lisp
signature and form errors remain in the evaluator. No additional syntax
validation or compiler-specific protection of `x2c.*` names is introduced.

Production closures also retain local names that mutable global or unknown
callables may later read from current data. Captured local special identities
keep quote opacity, quasiquote depth and nested parameter binding. Captures
belong to the session; borrowed values keep their original owners and must
remain live. The reference uses the same conservative capture rule: stable
local special identities control quotation and binding, while global,
parameter and computed callables retain possible local reads from their data.
This can retain local values and their referents longer than their immediate
use would require; it does not copy or promote borrowed objects.

The reference targets language behavior, not the embedding APIs or native
stack capacity of the production runtime. Calls consume native stack: sufficiently deep recursion
can exhaust it. Callable addresses are process-specific, as they are in the
production implementation. This is a tested reference, not a proof that every
possible program behaves identically.

## Production execution

The production evaluator runs each call recursively, except a call in tail
position, which reuses the frame of the call it ends. A self-recursive loop
written in tail position therefore runs in constant native stack. Other
recursion consumes native stack, and the evaluator reports `<call-stack>`
before it runs out. Free names resolve through the Lambda's captures and
then the session globals and reserved names, never through caller locals.
The production step budget and interruption flag stop evaluation through
`<call-stack>` and `<interrupt>`. These shared Error causes allow catches,
but reject returning `ignore`, `log`, or `collect` policies. A later public
entry opens a fresh budget; the session owner clears its interruption flag.

## The showcase and comparison

[The Lisp demonstration][demo]
differentiates `x*x + 3*x` using recursive pattern matching, simplifies the
result, evaluates both expressions at `x = 5`, and maps a captured offset over
a List. Its result is:

```text
((+ (* x x) (* 3 x)) (+ (+ x x) 3) 40 13 (11 12 13))
```

The example is listed in `examples/manifest.txt`, so `make examples` checks
its output alongside the existing examples. The optional differential checker
builds both implementations and compares exit status, stdout, and stderr:

```sh
x2c script examples/programs/check-reference-lisp --build
```

The corpus covers ordinary values, arithmetic, macros, capture, shadowing,
reader failures, native errors, file imports, optional Lisp libraries, and
REPL recovery. It avoids printing opaque addresses and performs no output
normalization. Run it when changing this interpreter or the production Lisp
semantics; it is not an additional publication gate.

## Basic benchmarks

The optional runner compares the recursive interpreter with the production
Lisp shell in `examples/programs/lisp.x`. Run it from the repository root:

```sh
python3 examples/programs/benchmark-reference-lisp.py --build
python3 examples/programs/benchmark-reference-lisp.py --repeat 10
python3 examples/programs/benchmark-reference-lisp.py --case fibonacci --show-source
```

The five workloads cover startup, recursive Fibonacci, map/fold operations,
captured closures, and runtime Lisp macros. Each sample verifies an expected
result. The runner alternates execution order and reports median milliseconds
from fresh processes, including startup, library initialization, reading,
evaluation, and output. These measure complete CLI
runs; they do not isolate evaluator speed. The startup baseline is reported
separately, without subtracting it from the other measurements.

[source]: https://github.com/gwf/x2c/blob/main/examples/programs/literate-lisp.x
[demo]: https://github.com/gwf/x2c/blob/main/examples/data/reference-lisp/showcase.xlisp
