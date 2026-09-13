# Tiny Lisp in x2c

Three independent versions implement the same small language:

- [tiny-lisp.x](tiny-lisp.x): compact source with a runnable example in its
  header.
- [tiny-lisp-min.x](tiny-lisp-min.x): code golf, with only a copyright comment.
- [tiny-lisp.max.x](tiny-lisp.max.x): formatted source with explanations of
  the reader, evaluator, dynamic scope, and memory ownership.

All three supply their own reader and evaluator. x2c supplies ordinary
Strings, Lists, Maps, Buffers, and `match`; none calls x2c's Lisp interpreter,
reader, or standard library. C string literals promote to x2c values where
the receiving type requires them.

Build and run the annotated version, or substitute either other source:

```sh
./builds/0/x2c build examples/programs/tiny-lisp.max.x --output /tmp/tiny-lisp
/tmp/tiny-lisp < examples/data/tiny-lisp.slp
```

The [example program](../data/tiny-lisp.slp) defines arithmetic and conversion
between unary lists and decimal digit lists entirely in Tiny Lisp:

```lisp
(decimal (fact (unary '(4))))              ; (2 4)
(decimal (mul (unary '(1 2)) (unary '(3)))) ; (3 6)
```

Internally, 24 is still a list of 24 `t` atoms. `unary` accepts nonnegative
decimal digit lists, including leading zeros; `decimal` emits canonical
digits, with `(0)` for the empty unary list.

The eight forms are `quote`, `if`, `lambda`, `def`, `car`, `cdr`, `cons`, and
`eq`. Functions use dynamic scope, with no captured closures. Calls evaluate
arguments from left to right in the caller's environment, then copy it and
bind the parameters. Later duplicate parameter names replace earlier ones.
`def` binds a name in the current environment and returns that name.

Only `()` is false. Both `car` and `cdr` of `()` return `()`. `cons` requires a
proper-list tail. `eq` compares atoms and lists structurally, returning `t`
or `()`. Names have no numeric meaning in the interpreter. The reader supports
proper lists, quote shorthand, and semicolon comments. Reader and evaluation
errors terminate with `error` and status 1.

The minimum version uses `V` for `Var`, `Z` for `void`, and a `q` keyword that
expands to `return`. It shares primitive dispatch paths and uses the native
truth test after restricting values to nonempty atom names and proper lists.
The other versions spell out these operations.

Strings and Lists live in x2c's interning pools until process exit; temporary
mutable containers are released at their scope exits. There is no bounded
heap or independent garbage collector. Unbounded lists, conditionals, and
recursive calls suffice to encode a two-counter machine; native memory and
stack still limit actual runs.
