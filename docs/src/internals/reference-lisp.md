# A recursive Lisp in x2c

[The reference interpreter][source]
implements x2c Lisp in one source file. It owns its reader, environments,
closures, special forms, native registry, and standard vocabulary. Evaluation
recurses over ordinary values; it never constructs a Lisp session, calls the
production evaluator, or prepares or executes word code.

Build it from the repository root:

```sh
./builds/0/x2c build --output /tmp/reference-lisp \
  examples/programs/reference-lisp.x
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

Start with `_eval`: atoms name values, scalars evaluate to themselves, and a
nonempty List calls its evaluated head with the remaining forms. `_apply`
distinguishes closures, special forms, and ordinary native functions. This is
the evaluator's entire execution model.

`Closure` stores parameters, a body, captured values, and whether it is a
macro. It uses the ordinary `Var` value tag `lambda`, preserving sorting, type
queries, and native diagnostics. The record is defined entirely here; no
production `Lambda` object or protocol is used. A macro receives raw arguments
and returns an expansion that runs in its caller.

`Environment` is a stack-local link and a Map of bindings. Call bindings are
freed when the call returns. Closure records and their capture Maps remain in
the session Scope. Capturing copies a Var, preserving the identity and
ownership of its referent. Ordinary String and List pools own canonical data.

The reader uses ordinary x2c tokenization, then recursively constructs values
and Lists. `_natives` binds ordinary operations through `Func`, which owns
native argument conversion and arity checks. The `lisp_*` strings in this Map
are compatibility names accepted by `bind`; their targets are independent
functions in this source file. The quoted `_standard` List supplies macros
and higher-order functions in Lisp itself.

The source uses ordinary runtime collection and pattern operations, including
`List.match` and replacement. Those operations retain their normal runtime
implementation; this example replaces Lisp evaluation, not x2c's collection
or pattern engine.

## Compatibility

The reference follows x2c Lisp, including behavior that differs from Scheme:

- Only the empty List is false; zero and the empty String are true.
- Ordinary arguments run left to right. Macros receive unevaluated forms.
- Special forms are callable identities, so aliases and shadowing work.
- A closure captures local names found by flattening its List body, including
  quoted and nested forms. Its own parameters and reserved names are excluded.
  A scalar body captures nothing. Lookup continues through caller environments
  for names absent from the call's bindings and captures.
- `def` writes globals. `eval` evaluates its supplied expression globally.
- `apply` consumes evaluated values and rejects macros and special forms,
  except for the built-in `apply` itself.
- `bind` looks up a fixed native registry; repeated lookup preserves identity.
- Completed effects remain when a later form fails to read or evaluate.

Native calls use x2c's existing checked `Func` boundary. Deliberate Lisp
signature and form errors remain in the evaluator. No additional syntax
validation or compiler-specific protection of `x2c.*` names is introduced.

The reference targets language behavior, not the embedding APIs, AUTO
instrumentation, word-code introspection, or native stack capacity of the
production runtime. Calls consume native stack: sufficiently deep recursion
can exhaust it. Callable addresses are process-specific, as they are in the
production implementation. This is a tested reference, not a proof that every
possible program behaves identically.

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
python3 examples/programs/check-reference-lisp.py --build
```

The corpus covers ordinary values, arithmetic, macros, capture, shadowing,
reader failures, native errors, file imports, optional Lisp libraries, and
REPL recovery. It avoids printing opaque addresses and performs no output
normalization. Run it when changing this interpreter or the production Lisp
semantics; it is not an additional publication gate.

[source]: https://github.com/gwf/x2c/blob/main/examples/programs/reference-lisp.x
[demo]: https://github.com/gwf/x2c/blob/main/examples/data/reference-lisp/showcase.xlisp
