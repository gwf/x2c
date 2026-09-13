# Stutter in x2c

[stutter.x](stutter.x) implements Gary William Flake's `stutter.c` from
*The Computational Beauty of Nature*. It supplies its own reader, evaluator,
and garbage collector using ordinary x2c. It does not call x2c's Lisp reader,
interpreter, or standard library. Compare [literate-lisp.x](literate-lisp.x)
for a larger, different Lisp implemented independently in x2c.

[stutter-min.x](stutter-min.x) is a separate, minimal implementation of the
same interpreter. It keeps the readable version's behavior, including heap
limits, collection diagnostics, malformed-input handling, and CLI output.
It contains the whole interpreter; it does not include the readable version
or delegate to x2c Lisp.

[tiny-lisp.x](tiny-lisp.x) takes a different target: a minimal Turing-complete
Lisp, without Stutter compatibility. Its eight forms are `quote`, `if`,
`lambda`, `def`, `car`, `cdr`, `cons`, and `eq`. Constants appear directly in
the reader and evaluator; x2c supplies native Strings, Lists, Maps, and `match`.
The source header points to a [runnable example](../data/tiny-lisp.slp) with
unary arithmetic and conversion in both directions between unary lists and
decimal digit lists. All arithmetic and conversion functions are written in
the tiny Lisp. Build and run it with:

```sh
./builds/0/x2c build examples/programs/tiny-lisp.x --output /tmp/tiny-lisp
/tmp/tiny-lisp < examples/data/tiny-lisp.slp
```

`(decimal (fact (unary '(4))))` returns `(2 4)`: internally, factorial still
produces a list of 24 `t` atoms. The example also computes 12 times 3 as
`(3 6)`. `unary` accepts nonnegative decimal digit lists, including leading
zeros; `decimal` emits canonical digits, with `(0)` for the empty unary list.

Tiny Lisp uses dynamic scope, with no captured closures. `def` binds a name
in the current environment; calls evaluate arguments in the caller's
environment, then copy it and bind the parameters. Only `()` is false, and
`car` and `cdr` of `()` return `()`. `eq` compares atoms and lists structurally,
returning `t` or `()`. Names have no numeric meaning in the interpreter. The
reader supports proper lists, quote shorthand, and semicolon comments. Invalid input
terminates with `error` and status 1. Allocations live in the session's x2c
pools; this version has no bounded heap or independent garbage collector.
Unbounded lists, conditionals, and recursive calls suffice to encode a
two-counter machine; native memory and stack still limit actual runs.

The Stutter-compatible minimal file uses code-golf formatting and single-letter
names. Its `q(expression)` keyword expands to `return expression`; `$d`
expands to `fprintf(stderr, ...)`. The cell class supplies pointer identity
and `Var` conversions; its constructor owns the bounded heap. These are
ordinary x2c facilities, with no Lisp evaluation in the interpreter. Source
size is measured in raw bytes, including the copyright notice, complete CLI help,
and diagnostics. The readable file remains the explanation of the language.

The minimal version uses each atom's head as its current dynamic binding.
Calls evaluate their actual arguments first, then save and replace bindings
in reverse parameter order. Restoring forward preserves the first duplicate
parameter's precedence. The existing root Array retains argument values and
saved bindings, so environment Maps and frame traversal disappear. One
numeric dispatch handles all eight primitives, and one selector implements
both `car` and `cdr`. File-static state serves the executable's single session.

Both versions keep iterative flat-list reading and marking; the size reduction
does not trade away supported list length for additional native recursion.

From the repository root:

```sh
./builds/0/x2c build --output /tmp/stutter examples/programs/stutter.x
/tmp/stutter < examples/data/stutter.slp
/tmp/stutter -heap 128
```

The [example](../data/stutter.slp) builds unary arithmetic and factorial,
then maps a function over symbols. Input comes from standard input; `-help`
describes the options. Every expression produces a result. Redirected input
also echoes each parsed expression, matching the book interpreter.

Stutter has exactly eight primitives:

| Primitive | Meaning |
| --- | --- |
| `car`, `cdr` | Head or tail of a proper list; both return `nil` on `nil`. |
| `cons` | Prepend a value to a proper list. |
| `set` | Assign an evaluated atom in its nearest dynamic binding. |
| `equal` | True only for two references to the same atom. |
| `quote` | Return an unevaluated expression; `'x` reads as `(quote x)`. |
| `lambda` | Construct a function from parameter names and one body. |
| `if` | Evaluate only the selected branch; only `nil` is false. |

Numbers and double-quoted text are atom names. There are no native numeric
operations, string literals, dotted pairs, variadic parameters, or closures.
For example, `((lambda (x) ((lambda () x))) 'local)` returns `local` because
lookup searches the active callers. A returned lambda retains no bindings.
`nil`, `t`, and primitive names can all be rebound.

Compatibility includes the original's permissive argument rules: missing
lambda arguments become `nil`, extra arguments are ignored without being
evaluated, and the first duplicate parameter wins. Value primitives evaluate
two arguments even for `car` and `cdr`. Errors print and return a hidden
sentinel; the original's `if` treats that sentinel as true, and `equal` can
compare two error sentinels equal. A call with a non-callable head returns
its original form. These rules are deliberately retained.

The heap defaults to 10,240 cells and uses mark-and-sweep. Maps hold interned
names and dynamic call frames; an Array roots temporary values during
allocation. Since bindings no longer consume cons cells, collection timing
and the minimum heap needed for a program differ from the C implementation.
Atom names persist for the session. Native recursion can exhaust the stack.
The reader preserves the original 255-byte input chunks, including their
effect on long names and comments.

Invalid heap counts are rejected instead of allowing the original's unsafe
allocations. Missing input in otherwise crashing forms is handled as `nil`;
undefined C crashes are not a compatibility requirement. Help text describes
the actual collector rather than the original's mistaken stop-and-copy claim.

The optional differential checker compares transcripts and exit status with
an independently built original. Collector timing and help prose may differ.
With the book source at `~/Git/CBofN`:

```sh
cc -std=gnu89 -D__dest_os=1 -D__mac_os=2 \
  -Wno-deprecated-non-prototype \
  ~/Git/CBofN/src/stutter.c ~/Git/CBofN/src/misc.c -lm \
  -o /tmp/stutter-original
python3 examples/programs/check-stutter.py \
  --reference /tmp/stutter-original --executable /tmp/stutter \
  --book ~/Git/CBofN
```

For strict comparison of the two x2c versions, including garbage collection
and error output (only the executable name in CLI diagnostics is normalized):

```sh
./builds/0/x2c build --output /tmp/stutter-min examples/programs/stutter-min.x
python3 examples/programs/check-stutter.py --exact \
  --reference /tmp/stutter --executable /tmp/stutter-min --book ~/Git/CBofN
```

The book corpus runs `sample.slp`, `demo.slp`, and `float.slp` unchanged,
covering symbolic lists, unary arithmetic, and the book's floating-point
implementation. Additional cases check scope, evaluation order, rebinding,
reader recovery, and collection with a small heap. The checker is optional
and adds no recurring validation requirement.
