# Iteration

x2c has two ways to walk a collection. `foreach(T name, collection)` is the
short form and covers most cases. An `Iter` walks one element at a time under
your control, and reports exhaustion separately from the element.

Neither one allocates iterator state on the heap. For an immediately
consumed call, x2c supplies stack storage. Name that storage yourself when
the iterator has to stay live between expressions. The
[storage convention](#the-storage-convention) covers both forms.

[The language reference](../reference/language.md) states the `foreach` rules,
and the [standard library overview](../library/overview.md) links to every
iterator operation.

## Foreach

The loop header declares the loop variable and names the collection:

```x2c
List values = %(10 20 30);
int total = 0;
foreach(int value, values)
  total += value;
printf("total = %d\n", total);
```

`break` and `continue` behave as they do in a C loop.

A single-binder loop over a `List`, `Array`, or `String` compiles to that
type's `try_next` cursor: a caller-owned index or cell pointer and one call
per element, with no `Iter` in between. Over an `Array` or a `String` it costs
what hand-written indexing costs, and over a `List` it is faster than a
hand-rolled `cdr` walk, which pays a `car` and a `cdr` call per cell. Prefer
`foreach` and let the lowering choose the step.

### What you can iterate

`List`, `Array`, `Map`, and `String` each provide an iterator adapter in their
own module, so all four work directly:

```x2c
Array scores = %[3, 4, 5];
foreach(int score, scores)
  printf("score = %d\n", score);

Map ages = %{"ada": 36, "alan": 41};
foreach(Var (name, age), ages)
  printf("%s is %d\n", name, age.int());

String word = "hi";
foreach(int ch, word)
  printf("char = %c\n", ch);

foreach(char ch, word)
  printf("char = %c\n", ch);
```

A `Map` yields its values, like every other collection. Two binders ask for
the key as well, and the loop reads both out of the table without
allocating. When you need an iterator there are three: `map.iter(&storage)`
yields the values, `map.keys(&storage)` yields the keys, and
`map.enumerate(&storage)` yields `(key value)` `List`s and is the only one
that allocates. The generated families in `lib/typed-map.x` publish the same
three, so a `MapIntInt` iterates as a `Map` does. `Map` traversal follows
internal slot order, so do not depend on the sequence, and do not insert or
delete entries while a traversal is live. Structural mutation invalidates
outstanding traversal state.

A `String` yields its bytes as numeric `Var` values. Declare the loop
variable as `int` when the byte is used numerically, or as `char` when it is
passed to a character-oriented C API. Both forms traverse bytes, and neither
decodes Unicode characters.

### Lazy String fields

`String` provides three ways to iterate over fields without first building a
`List`:

```x2c
~String text = "one two\nthree:four";
foreach(String word, text.words())
  printf("word=%s\n", word);

foreach(String line, text.lines())
  printf("line=%s\n", line);

foreach(String field, text.splits(":"))
  printf("field=%s\n", field);
```

`words()` coalesces runs of C whitespace, ignores leading and trailing
whitespace, and yields no empty `String`. `splits(sep)` treats every explicit
separator independently, so `%" a  b ".splits(" ")` yields empty fields
around and between the words. `lines()` recognizes LF, CR, and CRLF and
strips the endings.

These cursors allocate one scope-owned traversal descriptor. There is no
`List` and no object per field. Each yielded field is a canonical `String`.
After a field has been interned once, finding an equal field of at most 256
bytes needs no heap allocation. Distinct fields remain in the active `String`
pool. For a large input, use `String.pool_retain()` and
`String.pool_release()` to reclaim temporary fields, and promote the values
that must survive.

A `Var` is iterated through its descriptor, so a boxed `List` or `Array`
iterates the way the unboxed value does. A boxed value with no iterator
adapter produces an already-exhausted iterator, and the loop body runs zero
times. A receiver with a statically known type must have a visible `Iter`
conformance, from its own adoption or from the nearest typedef ancestor.
`typedef List Ast;` lets `foreach` over `Ast` reuse `List`'s conformance
without `protocol Iter(Ast);`. A type with neither is rejected as not
iterable.

An `Iter` is itself iterable, so `foreach` can consume a hand-built iterator.
That combination appears at the end of this chapter.

### What the loop variable's type means

The general `Iter` path yields a `Var`. The declared loop type names the
conversion applied to each element as it arrives. It does not filter, and it
does not claim anything about what the collection holds.
`foreach(int value, values)` means "unbox each element with `Var.int`" on
that path. Cursor-backed collections deliver their typed outputs directly.

The conversions available for a loop variable are the `Var` conversions:
`char`, `short`, `int`, `uint`, `long`, `ulong`, `float`, `double`,
`String`, `Symbol`, `List`, `Array`, and `Map`. Declaring the loop variable
as `Var` applies no conversion. Do that when the element type varies or when
the body dispatches on the tag:

```x2c
~List values = %(1 2 3);
foreach(Var item, values)
  printf("%s\n", item);
```

If you declare a loop type that has no `Var` conversion, such as one of your
own structs, x2c still translates the loop, and the C compiler reports an
incompatible assignment to the loop variable. When that happens, pick a
converting type or take a `Var` and convert in the body.

### What foreach guarantees

The collection expression's static type selects the traversal.
Cursor-backed collections use their typed `try_next` member. A `Var`
dispatches through its runtime descriptor, and an `Iter` is used as it
stands. Foreach stores the traversal state for you and converts each output
to the declared loop type. There is no heap allocation and nothing to clean
up.

## Iterators by hand

An `Iter` points to a small struct holding the object being iterated, one `Var`
of state, and a `next` callback that reports success separately from its
result. Advancing it calls `next`, which fills a `Var *out` and
returns 1, or returns 0 to report exhaustion. The callback is cleared at
exhaustion.

You read an iterator two ways:

- `iter.try_next(&out)` is the preferred form. It returns success separately
  from the payload, and writes `out` only when it returns nonzero.
- `iter.next()` returns the element directly
  and `void` at exhaustion. It is unambiguous because no iterator may yield
  `void` as an element.

An `Iter` is single-pass. There is no rewind, and the collectors below
consume their input, so build a fresh iterator for a second traversal.

`range` is the simplest source:

```x2c
struct Iter storage;
Iter counts = range(1, 4, 1, &storage);
Var value;
while (counts.try_next(&value))
  printf("%d\n", value.int());
```

That prints 1 through 4. A range is inclusive when the endpoint lies in the
step direction. `range(3, 1, -1, ...)` counts down 3, 2, 1. A step that
would cross the endpoint stops before it, so `range(0, 9, 2, ...)` yields
0, 2, 4, 6, 8. A range pointed the wrong way is empty, and a zero step is
rejected at construction.

You can write a source yourself by initializing storage with your own
callback. `Iter.init` takes the object, the callback, and the initial state,
and the receiver is the storage:

```x2c
~static int _powers_next(Iter iter, Var *out) {
~  long value = iter.state.long();
~  if (value > iter.obj.long()) return 0;
~  *out = (int) value;
~  iter.state = value * 2;
~  return 1;
~}
~
~int main(void) {
struct Iter storage;
Iter powers = Iter.init(&storage, 64, _powers_next, 1);
foreach(int value, powers)
  printf("%d\n", value);
~  return 0;
~}
```

Inside such a callback, write `iter->next` when you need the field.
`iter.next(...)` is receiver syntax and calls the method instead of the
stored callback.

## The storage convention

An `Iter` is a pointer to caller-owned storage. Each source and collection
adapter takes a final `Iter` destination internally, initializes it, and
returns the same pointer. The iterator's state is stored in that
`struct Iter`. There is no second state object and nothing to free.

Fluent code omits that destination when the iterator is consumed
immediately:

```x2c
int main(void) {
  Scope.retain();
  Array values = range(1, 8, 1).array();
  for (size_t i = 0; i < values.len(); i++)
    printf("%d\n", values[i].int());

  Scope.release();
  return 0;
}
```

x2c inserts a `struct Iter` compound literal for the missing final
destination. That object has automatic storage and remains alive through the
enclosing block. Completion applies only when the call is consumed
immediately by `try_next`, `next`, `list`, `array`, or `foreach`.

It does not apply when an iterator is assigned, returned, or passed as an
argument. Then declare the `struct Iter` yourself:

```x2c
~int main(void) {
struct Iter source_storage;
Iter source = range(1, 8, 1, &source_storage);

Var first = source.next();
// source remains available here.
~  return first is void;
~}
```

Storage must outlive every iterator that refers to it. Never return an `Iter`
built over local storage; take the destination storage as a parameter or
return a collected `List` or `Array`. One `struct Iter` holds one live
iterator, so reusing it overwrites the earlier one.

The iterators need no cleanup. A collected `List` or `Array` is scope-owned
data, so the program above brackets its work with `Scope.retain` and
`Scope.release`. See [scopes and lifetime](memory.md) for what that pair
does.

## Collecting

Constructing an iterator does not consume it. The collectors do:

```x2c
int main(void) {
  Scope.retain();
  List numbers = range(1, 4, 1).list();
  Array boxed = range(1, 4, 1).array();
  printf("%s and %s\n", numbers.str(), boxed.str());
  Scope.release();
  return 0;
}
```

`iter.list()` and `iter.array()` build a fresh `List` or `Array` under the
current scope, draining the iterator. `iter.unique(&storage)` is the one
lazy adapter: it yields the first occurrence of each element, using `Map`
equality and hashing for the seen set. `List.unique` is built from it.

For eager transformations, folds, and predicates over a collection, use the
`List`, `Array`, and `Map` operations described in
[collections](collections.md).

## Handing an iterator to foreach

An `Iter` is iterable, so `foreach` can consume one directly, including a
source written inline:

```x2c
int main(void) {
  foreach(int value, range(1, 10, 1))
    if (value % 2 == 0) printf("%d\n", value);
  return 0;
}
```

The compiler supplies stack storage before the loop starts pulling, and
nested `foreach` loops receive separate storage. Use the explicit form when
the same iterator must be paused and resumed outside one loop.

## Choosing between the two

Use `foreach` when the collection has an adapter, the element conversion you
want exists, and the loop body is the interesting part. It is shorter and it
cannot leak an iterator.

Drive an `Iter` by hand when:

- exhaustion status matters to the surrounding code, so you want `try_next`
  instead of a loop that ends silently;
- you are writing a new source with `Iter.init`;
- the traversal has to be paused, handed to another function, or resumed.
  The loop form cannot express that.

[Idioms](idioms.md) shows how iteration combines with other x2c features.
