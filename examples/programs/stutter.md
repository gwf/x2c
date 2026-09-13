# Stutter in x2c

[stutter.x](stutter.x) implements Gary William Flake's `stutter.c` from
*The Computational Beauty of Nature*. It supplies its own reader, evaluator,
and garbage collector using ordinary x2c. It does not call x2c's Lisp reader,
interpreter, or standard library. Compare [literate-lisp.x](literate-lisp.x)
for a larger, different Lisp implemented independently in x2c.

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

The book corpus runs `sample.slp`, `demo.slp`, and `float.slp` unchanged,
covering symbolic lists, unary arithmetic, and the book's floating-point
implementation. Additional cases check scope, evaluation order, rebinding,
reader recovery, and collection with a small heap. The checker is optional
and adds no recurring validation requirement.
