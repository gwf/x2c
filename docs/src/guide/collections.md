# Strings, Lists, Arrays, and Maps

C gives you `char *`, `struct`, and `malloc`. x2c keeps all of that and adds
four runtime data types: `String`, `List`, `Array`, and `Map`. Much of the
compiler and runtime is built with these four types.

Three ideas run through everything below:

- **Percent is the quoting sigil.** A following delimiter selects which
  literal grammar reads the contents: `%"..."`, `%(...)`, `%[...]`,
  `%{...}`, or `%<<...>>`.
- **Dollar unquotes.** Inside quoted `List`, `String`, `Array`, or `Map`
  content, `$name` or `${expression}` returns to ordinary x2c expression
  grammar for one value.
- **`String` and `List` are immutable and canonical**: equal values share
  storage. **`Array` and `Map` are mutable**: each object has its own identity,
  even when its contents equal another's.

All four are represented by C pointers and can be boxed into `Var`, so they
can share a heterogeneous container. See [Values and Var](values.md) for
boxing and conversion.

## Percent literals

In operand position, `%` followed by a literal delimiter is the quoting
sigil. The delimiter selects both the result type and the grammar used
inside it. "Quoted" means a literal grammar is reading the contents. It does
not mean every percent form holds unevaluated symbolic data.

| Form | Builds | Element syntax |
| --- | --- | --- |
| `%"text"` | `String` | quoted text, with `$name` / `${expr}` unquote |
| `%(a b c)` | `List` | quoted symbolic content; bare names are `Atom`s |
| `%<<a b c>>` | `SymbolSet` | quoted literal `Symbol`s only |
| `%[a, b, c]` | `Array` | quoted comma-separated values |
| `%{k: v, k: v}` | `Map` | quoted key/value pairs |

The empty forms are `%""`, `%()`, `%<<>>`, `%[]`, and `%{}`.

```x2c
List codes = %(200 301 404);
Array queue = %[10, 20, 30];
Map status = %{200: "ok", 404: "missing"};
String greeting = "hello, world";

printf("%s %s %s %s\n",
       codes.repr(), queue.repr(), status.repr(), greeting.repr());
```

```text
(200 301 404) [ 10, 20, 30 ] { 200: "ok", 404: "missing" } "hello, world"
```

The four forms print differently. `repr` is the readable representation for
each type, and the `List` form round-trips through the same reader the Lisp
showcase uses.

### Quoted data and x2c expressions

Inside `%(...)`, `%[...]`, and `%{...}`, a bare spelling is an **`Atom`**,
an exact, case-sensitive name. Use `$name` to insert one identifier expression
or `${expression}` to insert any other x2c expression.

```x2c
int radius = 3;

List named = %(radius);      // one Atom whose text is "radius"
Array named_too = %[radius]; // the same Atom in an Array
Array valued = %[$radius];   // one element holding the number 3
List inserted = %($radius);

printf("%s %s %s %s\n", named.repr(), named_too.repr(),
       valued.repr(), inserted.repr());
```

```text
(radius) [ <radius> ] [ 3 ] (3)
```

These forms quote symbolic data such as ASTs, patterns, and configuration
trees, where the names are the content. A short `Atom` uses the compact
`Symbol` representation; a longer one retains its exact spelling in an
`<lsym>`. To put an x2c value in that quoted content, unquote it with `$name`
or `${expression}`.

Bare `(...)`, `[...]`, and `{...}` nest `List`, `Array`, and `Map` data inside
any of these collection forms. Bare `"..."` is an x2c `String`, with the same
interpolation and escape rules as `%"..."`. `${"..."}` instead inserts an
ordinary C string expression. Arrays and Maps have no splice form.

### Inserting and splicing into List literals

`%()` supports four insertion forms:

- `$name` inserts one value named by an identifier.
- `${expression}` inserts one value from an arbitrary expression.
- `@name` splices a `List`'s elements into the surrounding `List`.
- `@{expression}` splices the `List` an expression produces.

```x2c
String name = "quartz";
List tail = %(3 4);

List one = %(mineral $name);
List computed = %(len ${name.len()});
List spliced = %(1 2 @tail);
List reversed = %(1 2 @{tail.reverse()});

printf("%s\n%s\n%s\n%s\n",
       one.repr(), computed.repr(), spliced.repr(), reversed.repr());
```

```text
(mineral "quartz")
(len 6)
(1 2 3 4)
(1 2 4 3)
```

`$` leaves `List` grammar, parses and evaluates one x2c expression, converts
the result to one `List` value, and returns to `List` grammar. `@` makes the
same crossing and splices the evaluated `List`'s elements instead of inserting
one value. The identifier forms are the short versions of the braced
expression forms.

### Lisp reader prefixes in List literals

A `List` passed directly to `Lisp.eval` can use the familiar reader prefixes
instead of spelling out their names:

```x2c
~int main(void) {
~Lisp lisp = Lisp.new();
~defer lisp.destroy();
lisp.set_global("tail", %(3 4));
List result = lisp.eval(%(`(1 ,(+ 1 1) ,@tail)));
~return result == %(1 2 3 4) ? 0 : 1;
~}
```

That literal constructs the same data as
`%(quasiquote (1 (unquote (+ 1 1)) (unquote-splicing tail)))` and evaluates
to `%(1 2 3 4)`. `'` is `quote` the same way, so `%('foo)` is
`%(quote foo)`. A `List` literal reads these prefixes as Lisp source does, and
the evaluator decides what a form means. `$` and `@` are x2c interpolation
and splicing, performed while constructing the `List`.

Braces delimit the x2c expression being unquoted. Nested calls, indexing,
assignments, conditional expressions, and other parentheses stay part of
that expression:

```x2c
String name = "quartz";
String source = "feldspar";
int count = 0;
List called = %(result ${name.upper().len()});
List assigned = %(result ${count = source.len()});
```

Inside `%()`, `$name(...)` reads differently. `$name` inserts one value, and
the following `(...)` is a nested symbolic `List`. Write `${name(...)}` when
the unquoted expression is a runtime call. Inside `%""`, parentheses after
`$name` are text, so the same runtime call is again `${name(...)}`.

Nested `(...)` in `%()` stays quoted `List` data. Bare `"..."`, `[...]`, and
`{...}` switch to `String`, `Array`, and `Map` literals. All four retain quoted
data syntax, and `String` takes `$` unquote the way `%"..."` does:

```x2c
String source = "quartz";
List shapes = %(
  (nested symbolic list)
  "len=${source.len()}"
  [${source.len()}, 2]
  {name: $source}
  ${source.upper()}
);
```

Do not repeat the `%` sigil on those. A bare `%` inside `%()` is an `Atom`, so
`%(k %"txt")` is the three elements `k`, `%`, and `"txt"`. Write
`%(k "txt")`.

### Atom spellings inside Lists

A bare name in `%()` is an `Atom` and preserves its exact bytes, however long.
The `Atom` is a compact `Symbol` when the encoding reproduces those bytes, and
the private `<lsym>` representation otherwise. Do not write `<ready>` inside
a `List`. `ready` produces the same compact value, and a long bare name keeps
its full spelling.

A C preprocessor macro name is a bare name too. The preprocessor never sees
the inside of a literal, so after `#define ROWS 64` the List `%(ROWS 4)` is
`(ROWS 4)`, and reading its first element as a number yields the `Symbol`'s
numeric value rather than 64. Unquote a typed value, `%(${(long) ROWS} 4)`,
to insert the macro's value; the bare `$ROWS` has no x2c type either,
because the preprocessor's text never reaches the type checker. The
compiler warns when a bare name in a literal matches an
object-like `#define` it has already passed in the same unit; macros from
included C headers are not seen and get no warning.

Angle brackets quote text that `List` syntax would read as another kind of
value. `1` is an integer, `<1>` is the `Symbol` `1`, and `<"a b">` quotes a
`Symbol` containing a space. The escaped bare `Atom` spellings `\x31` and
`a\ b` produce those same `Symbol`s. An angle spelling that does not fit the
compact encoding is rejected instead of becoming an `<lsym>`. `<"">` is the
empty `Symbol`, which has no bare `Atom` spelling.

```x2c
List names = %(ready VeryLongExactName 1 <1>);
printf("%s %s\n", names.getindex(0).tag().str(),
                   names.getindex(1).tag().str());
```

```text
symbol lsym
```

[Symbols and Atoms](symbols.md) covers the two representations and when to
use each.

### Ordered Symbol sets

`%<<...>>` declares a closed, immutable set of compact `Symbol`s. Its source
order is also its dense numeric order, starting at zero:

```x2c
SymbolSet colors = %<<red green blue>>;

printf("%d %d %d\n",
       colors.index(<green>),
       colors.contains(<blue>),
       colors.index(<orange>));
```

```text
1 1 -1
```

Bare entries are `Symbol`s, so write `%<<red green blue>>` rather than
`%<<<red> <green> <blue>>>`. Angle brackets still spell a `Symbol` explicitly.
A member whose spelling is not a bare word is quoted, and the quotes may hold
the `>>` that would otherwise end the literal:

```x2c
SymbolSet assignments = %<<"+=" "<<=" ">>=">>;
```

Interpolation and splicing are not supported. Every member must be known
when the file is compiled. Two spellings that encode as the same `Symbol` are a
compile-time duplicate error.

`index` maps a `Symbol` to its source-order integer and returns `-1` for a
nonmember. `contains` is the corresponding membership test. `getindex` maps an
integer back to its `Symbol`, accepts negative indexes, and returns zero when
out of range. A `SymbolSet` also supports `foreach(Symbol value, colors)` in
source order.

The compiler generates a perfect hash and the ordered `Symbol` table as one
read-only byte string. A lookup computes one candidate index and checks the
`Symbol` stored there. It does not allocate, initialize a runtime table, or
search the set. The byte string has static lifetime, so a literal is valid in
file-static declarations and public inline code.

### String interpolation

`%"..."` quotes text. `$name` and `${expression}` unquote one value when its
type converts to `String`.

```x2c
String who = "world";
String greeting = %"hello, $who";
String shouted = %"${who.upper()}!";
printf("%s %s\n", greeting, shouted);
```

```text
hello, world WORLD!
```

Supported native numeric expressions interpolate directly:

```x2c
String who = "world";
printf("%s\n", %"$who has ${who.len()} bytes");
```

```text
world has 5 bytes
```

An already-boxed `Var` carries no presentation format. Extract its native
value or call `str()`:

```x2c
Var answer = 42;
printf("%s\n", %"answer=${answer.integer()}");
printf("%s\n", %"boxed=${answer.str()}");
```

```text
answer=42
boxed=42
```

`${...}` unquotes one x2c expression inside a quoted `List`, `String`, `Array`,
or `Map`. In ordinary x2c code, `$(...)` enters compile-time Lisp. Nesting
them inserts a compile-time Lisp result into a quoted collection:

```x2c
List generated = %(${$(+ 40 2)});
Array generated_array = %[${$(+ 40 2)}];
```

The outer `${` unquotes from `List` grammar into x2c. The inner `$(` is read
in x2c and enters compile-time Lisp. `$macro(...)` is a macro invocation in
x2c. None of these parser meanings change Lisp `quote` or `quasiquote`. `%!`
is still the lambda-literal prefix, and `%` between two operands is still
modulo.

Percent strings are byte strings. They may span physical lines, and their
`\x`, `\u`, and `\U` escapes consume one or two hexadecimal digits instead
of C's fixed escape widths. C `"..."` literals keep C rules. The escape table
is in [the language reference](../reference/language.md).

### File-static literals

A file-static x2c object can keep its literal beside its declaration:

```x2c
static String endpoint = %"$scheme://example.test";
static String scheme = "https";
static List labels = %(service $scheme $endpoint);
static Array routes = %[$endpoint];
static Map route_by_name = %{default: $endpoint};
static Var boxed_labels = %(boxed $scheme);
```

The compiler builds these values once in the translation unit's guarded
initializer. Cached immutable pieces are ready before the assignments, and
referenced file-static objects are assigned before their dependents, so a
forward reference such as `endpoint` to `scheme` is valid. A referenced
object without `static`, or a cycle among the declarations, is diagnosed at
compile time.

## Immutable versus mutable

### List and String are canonical

`cons` canonicalizes `List`s: constructing the same head and tail twice returns
the *same cell*. `String.intern` canonicalizes non-empty `String`s the same
way. Equal content means an identical pointer, and equality is a pointer
compare.

```x2c
List literal = %(1 2 3);
List built = cons(1, cons(2, cons(3, NULL)));
printf("same cell: %d\n", literal == built);
printf("nil is the null pointer: %d\n", %() == NULL);
```

```text
same cell: 1
nil is the null pointer: 1
```

`List` and `String` operations do not mutate their input. They return new
canonical structure, sharing whatever they can:

```x2c
List x = %(1 2 3);
List longer = x.append(%(4));
printf("x=%s longer=%s\n", x.repr(), longer.repr());
```

```text
x=(1 2 3) longer=(1 2 3 4)
```

You can hand a `List` or `String` to any function without copying it, store it
in several places, and use it as a `Map` key. Nothing can change it under
you.

### Array and Map are objects

`Array.new`, `Map.new`, `%[]`, and `%{}` each produce a **fresh allocated
object** with its own identity. Two separately written empty literals are two
different `Array`s. Assigning one to another variable aliases it.

```x2c
Array a = %[1, 2, 3];
Array alias = a;
Array copy = a.copy();
alias.push(4);
printf("a=%s alias=%s copy=%s\n", a.repr(), alias.repr(), copy.repr());
printf("distinct empty literals: %d\n", %[] === %[]);
```

```text
a=[ 1, 2, 3, 4 ] alias=[ 1, 2, 3, 4 ] copy=[ 1, 2, 3 ]
distinct empty literals: 0
```

Mutating operations mutate in place and return the same object, so
`array.sort()` is not a sorted copy:

```x2c
Array numbers = %[5, 3, 9, 1];
Array sorted = numbers.sort();
printf("numbers=%s  same object=%d\n", numbers.repr(), sorted === numbers);
```

```text
numbers=[ 1, 3, 5, 9 ]  same object=1
```

`Array.reverse` behaves the same way. `Array.copy`, `Array.concat`,
`Array.map`, and `Array.getslice` return new `Array`s. The generated
[Array reference](../library/modules/array.md) says which operations mutate
and what identity each returns.

### Empty values are not all alike

```x2c
String empty = "";
List nil = %();
Array none = %[];
Map blank = %{};
printf("empty String is null: %d  nil is null: %d\n",
       empty == NULL, nil == NULL);
printf("empty Array allocated: %d  empty Map allocated: %d\n",
       none != NULL, blank != NULL);
```

```text
empty String is null: 1  nil is null: 1
empty Array allocated: 1  empty Map allocated: 1
```

The empty `String` and the empty `List` *are* the null pointer. An empty
`Array` or `Map` is an allocated object. `Null` is not a valid empty `Array` or
`Map` value, and boxing a null pointer with either tag breaks an invariant.

Emptiness tests follow from that. A bare condition on `String`, `List`,
`Array`, or `Map` uses its `truth` protocol member, so every empty collection
is false even when an empty `Array` or `Map` owns storage. Compare the pointer
when you are asking about the allocation instead of the content:

```x2c
Array none = %[];
Var boxed = none;
printf("pointer test: %d   boxed truthiness: %d\n",
       none != NULL, boxed ? 1 : 0);
printf("static truthiness: %d   len test: %d\n",
       none ? 1 : 0, none.len() == 0);
```

```text
pointer test: 1   boxed truthiness: 0
static truthiness: 0   len test: 1
```

### Equality and identity are explicit

```x2c
Array left = %[1, 2];
Array right = %[1, 2];
printf("array structural: %d  identity: %d\n",
       left == right, left === right);

Map a = %{k: 1};
Map b = %{k: 1};
printf("map structural: %d  identity: %d\n", a == b, a === b);
```

```text
array structural: 1  identity: 0
map structural: 1  identity: 0
```

`Array.equal` and `Map.equal` compare contents, and `==`/`!=` call them.
`===`/`!==` are the identity operators for typed objects and boxed `Var`
values. Boxed `Array` and `Map` hashing is identity-based, so they make poor
`Map` keys:

```x2c
Map by_list = %{};
by_list[%(1 2)] = "found";
printf("List key, rebuilt: %s\n", by_list[cons(1, cons(2, NULL))].repr());

Map by_array = %{};
by_array[%[1, 2]] = "found";
printf("Array key, equal contents: %s\n", by_array[%[1, 2]].repr());
```

```text
List key, rebuilt: "found"
Array key, equal contents: void
```

Key your `Map`s with `String`s, `Symbol`s, `Atom`s, numbers, or `List`s. Those
compare by content.

## Working with Lists

A `List` is a canonical cons chain, as in Lisp. `car` gives the head, `cdr`
gives the tail, `nil` is `NULL`, and the composed accessors `cadr`, `caddr`,
`cddr`, and the rest are available.

```x2c
List form = %((op add) (args 1 2) (flag on));
printf("head: %s\n", form.car().repr());
printf("second: %s\n", form.cadr().repr());
printf("args value: %s\n", form.assoc(%(args).car()).repr());
printf("length: %d\n", form.len());
```

```text
head: (op add)
second: (args 1 2)
args value: 1
length: 3
```

`List.assoc` treats the `List` as an association list of `(key value ...)`
pairs and returns the `cadr` of the first matching pair. `List.get` dispatches
on the key: integers index, anything else does an `assoc` lookup.

The functional `List` operations take `Func`. A fixed nonvariadic function or
function pointer converts automatically, and you can pass a capturing lambda
directly. Each element is supplied as a value. A callback with a reference
parameter is rejected when the first element is invoked, and it never
receives an alias into `List` storage. Empty inputs do not invoke or
arity-check the callback. The
[language reference](../reference/language.md#lambdas) has the conversion and
lifetime rules.

```x2c
List numbers = %(1 2 3 4);
List doubled = numbers.map(%!(x) => x * 2);
List big = numbers.filter(%!(x) => x > 2);
Var total = numbers.foldl(0, %!(a, b) => a + b);
printf("%s %s %s\n", doubled.repr(), big.repr(), total.repr());
```

```text
(2 4 6 8) (3 4) 10
```

Transformations and folds keep the callback's `Var` result. The predicates
`List.filter`, `List.find`, `List.any`, and `List.all` apply `Var`
truthiness, so they accept more than an `int` result. Direct functions,
function-pointer values, and capturing lambdas all use the same methods.

The other operations are `reverse`, `concat`, `last`, `index`, `contains`,
`sort`, `unique`, `head`, `tail`, `flatten`, `flatten_all`, `sublis`,
`array`, and `str` / `repr`. `List.len` walks the chain, so it is O(n). Do
not call it inside a loop over the same `List`.

You cannot write through a `List` index; see
[Indexing and slicing](#indexing-and-slicing) below. For scratch state you
mean to mutate, use an `Array`.

[Pattern Matching](match.md) takes `List`s apart using the same `%()` notation,
with `?binder` and `*binder` holes naming the parts.

### Typed cons chains

`typed-list.x` declares seven `List`s whose car always carries one known tag:
`ListChar`, `ListShort`, `ListInt`, `ListFloat`, `ListDbl`, `ListString`, and
`ListSymbol`. They are typedefs of `List` sharing its canonical pool, so a
typed chain and the plain literal that spells it are the same cells, and `%()`
builds one when that is the declared type. An element of the wrong tag raises
`<no-convert>`.

They give you typed methods, not more speed. `cons` is still a pool probe.
Use `typed-array.x` for indexing or bulk numeric storage, and these for
sharing, canonical identity, or a chain.

```x2c
#include "typed-list.x"

int main(void) {
  ListInt values = %(4 5 6);
  printf("car=%d last=%d\n", values.car(), values.last());

  int total = 0;
  for (ListInt cursor = values; cursor; cursor = cursor.cdr())
    total += cursor.car();
  printf("total=%d\n", total);

  ListString words = %("alpha" "beta");
  List widened = values;
  printf("first=%s widened=%s\n", words.car(), widened.str());
  return 0;
}
```

```text
car=4 last=6
total=15
first=alpha widened=( 4 5 6 )
```

`car` and `last` return the element type. The structural methods inherited
from `List` return `Self`, so `cdr`, `reverse`, `sort`, `append`, `head`,
`tail`, and the slices keep the typed spelling without generated wrappers,
and a walk never reconverts. `car` of `nil` is the element's zero, not `void`.
There is no `long` family, because `Var.box_long` allocates a `Scope`-owned box:
a cell would outlive its car and every `cons` would miss the pool.

These types adopt no `protocol Var`, so they have **no bracket indexing**.
`values[0]` does not compile. Use `car` and `nth_cdr`. Predicate-only
`filter` keeps the typed spelling, since it cannot replace an element.
Operations such as `map`, whose callbacks can produce new values, need a
widening assignment to `List`, as above.

## Working with Strings

A canonical `String` is an interned `char *`. It is NUL-terminated, so it
passes straight to `printf("%s", ...)` and to any C function that wants a
string. Every operation works on **bytes**: lengths, indices, slices,
padding, case conversion, and iteration. `String` does not decode Unicode
characters.

```x2c
String line = "  name = x2c  ";
String trimmed = line.strip(NULL);
List halves = trimmed.partition(" = ");
printf("[%s] -> %s\n", trimmed, halves.repr());
printf("upper=%s find=%d startswith=%d\n",
       trimmed.upper(), trimmed.find("="), trimmed.startswith("name"));
```

```text
[name = x2c] -> ("name" " = " "x2c")
upper=NAME = X2C find=5 startswith=1
```

`strip`, `lstrip`, and `rstrip` take a C string of characters to remove, or
`NULL` for the default whitespace set. `partition` returns a three-element
`List` of before/separator/after. `split` and `split_lines` return `List`s of
`String`s. Use `words()`, `lines()`, or `splits(sep)` when the fields should
stream directly through `foreach` instead. `String.join` is the inverse of
eager `split`, with the separator as the receiver:

```x2c
List parts = %"a:b:c".split(":");
printf("%s -> %s\n", parts.repr(), %"-".join(parts));
```

```text
("a" "b" "c") -> a-b-c
```

Numeric parsing reports success separately from the result:

```x2c
long value;
if (%"42".try_long(&value)) printf("parsed %ld\n", value);
if (!%"abc".try_long(&value)) printf("rejected abc\n");
if (!%"4x".try_long(&value)) printf("rejected 4x\n");
```

```text
parsed 42
rejected abc
rejected 4x
```

`try_long` requires the whole string to be the number. Leading and trailing
whitespace are allowed, and any other unconsumed character fails, so `4x` is
rejected instead of read as 4. It accepts a sign and recognizes `0x`, `0o`,
and `0b` radix prefixes as well as C's leading-zero octal.
`String.try_double` is the floating counterpart on the same terms.

Concatenation with `+` produces a canonical `String`. Comparing a `String`
with a C string literal using `==` or `!=` promotes the literal to `String`
and compares their contents:

```x2c
String built = %"hello" + %", world";
printf("%s  %d\n", built, built == "hello, world");
```

```text
hello, world  1
```

The literal may appear on either side and may be parenthesized. A `char *`
variable or another C pointer expression keeps native pointer comparison;
convert it to `String` explicitly when you want content comparison. The
identity operators `===` and `!==` also keep pointer comparison and do not
promote literals.

### Building text

Canonical `String`s are immutable, so repeated `+` in a loop allocates and
interns at every step. There are two better tools.

`String.malloc` creates a *transient mutable buffer*. It is not a canonical
`String`. Bracket assignment on a `String` is rejected, because writing through
a canonical `String` would corrupt every equal `String` that shares its
storage. Bind the buffer to a `char *` to write it with native indexing, then
finalize it with `String.intern_free`:

The byte count includes room for the terminating NUL, and nothing writes that
NUL for you. `String.intern_free` measures the buffer with `strlen`, so an
unterminated buffer is read past its end.

```x2c
String buf = String.malloc(6);
char *bytes = buf;
for (int i = 0; i < 5; i++) bytes[i] = 'a' + i;
bytes[5] = '\0';
String canonical = buf.intern_free();
printf("%s %d\n", canonical, canonical == "abcde");
```

```text
abcde 1
```

Write bytes that way only into such a buffer. On an interned `String` it
writes through shared canonical storage. To change one byte of a canonical
`String`, use the copy-producing `String.withindex`:

```x2c
String word = "hello";
String capital = word.withindex(0, 'H');
printf("%s %s\n", word, capital);
```

```text
hello Hello
```

For anything longer, use `Buffer`. It grows, it tracks indentation, and
`Buffer.str` produces the finished canonical `String`.

```x2c
Buffer out = Buffer.new(0);
foreach(Var item, %[1, 2, 3]) {
  out.write("item ");
  out.write(item.str());
  out.newline();
}
String report = out.str();
out.free();
printf("%s", report);
```

```text
item 1
item 2
item 3
```

`String.free` releases a transient buffer early and does nothing to a
canonical process-lifetime `String`. See [Scopes and Lifetime](memory.md) for
what owns what.

## Working with Arrays

An `Array` is a growable contiguous sequence of `Var`. Use it for indexed
mutation, a stack, a queue, or scratch storage. `Array.len` is O(1) and
returns a `size_t`.

```x2c
Array stack = %[];
stack.push(1);
stack.push(2);
stack.push(3);
Var top = stack.take_last();
stack[0] = 100;
printf("%s top=%s len=%zu\n", stack.repr(), top.repr(), stack.len());
```

```text
[ 100, 2 ] top=3 len=2
```

The positional operations are `push`, `take_last`, `shift`, `unshift`,
`insert`, `remove`, and `splice`; searching is `find` / `indexof`,
`contains`, and `count`; and there are `map`, `map2`, `reduce`, `sort`,
`reverse`, `concat`, `copy`, and `join`.

Use `sort_by` to order by a computed key, or `sort_with` for a comparator.
Both preserve the input order of ties. Arrays change in place and return the
same object; Lists return a sorted copy. The existing `sort()` still uses
`Var.compare` and does not promise stable ties.

```x2c
Array rows = %[];
rows.push(%(2 "first"));
rows.push(%(1 "low"));
rows.push(%(2 "second"));
rows.sort_by(%!(List row) => row.car());
// (1 "low"), (2 "first"), (2 "second")
List descending = %(3 1 2).sort_with(
  %!(int left, int right) => right - left);
```

`sort_by` evaluates its key once per element, front to back, and compares the
keys with `Var.compare`. `sort_with` passes two values to its callback and
converts the result to `int`: negative orders the first value before the
second, zero ties, and positive orders it after. Comparators must give a
consistent ordering. Callbacks are borrowed, run synchronously, and must not
mutate the Array being sorted; they may sort another container. If a callback
or comparison fails, the Array keeps its original element order. Callback
side effects are not undone. Empty inputs call neither callback; a singleton
calls its key once but never calls a comparator.

`Array.map`, `Array.map2`, and `Array.reduce` accept the same `Func` values
as the `List` operations and pass elements by value. `String.filter` and
`String.map` do the same for bytes. Each byte is boxed from `char`,
predicates use `Var` truthiness, and `String.map` converts the result to
`int` before rejecting NUL and storing the byte.

The shared `Block` protocol also supplies `pop`, `truncate`, and `free`.
`pop` discards the final element and returns nothing; use `take_last` when
the removed value is needed. `truncate` shortens the `Array` without changing
its identity, and `free` releases its storage before the owning scope ends.

```x2c
Array items = %["a", "c"];
items.insert(1, "b");
items.unshift("start");
Var gone = items.remove(0);
printf("%s removed=%s\n", items.repr(), gone.repr());
printf("find b at %d, joined %s\n", items.find("b"), items.join("-"));
```

```text
[ "a", "b", "c" ] removed="start"
find b at 1, joined a-b-c
```

`Array` also carries binary min-heap helpers, which turn it into a priority
queue without a second data structure:

```x2c
Array heap = %[];
heap.heap_push(30);
heap.heap_push(10);
heap.heap_push(20);
printf("smallest first: %s\n", heap.heap_pop().repr());
```

```text
smallest first: 10
```

`Array.push` rejects `void`, and so does the counted construction used by
non-empty `%[...]` literals. Raw `Null` is `Array` data. An out-of-range read
returns `void`. `Array` has no status-bearing read.

### Packed numeric Arrays

`typed-array.x` declares six `Array`s whose elements are native scalars rather
than `Var`: `ArrayChar`, `ArrayShort`, `ArrayInt`, `ArrayLong`,
`ArrayFloat`, and `ArrayDbl`. Each stores its elements packed, at the width
of the C type, and carries the same positional, slicing, searching, and
`Block` operations that `Array` does. `%[...]` builds one when that is the
declared type, so `ArrayInt counts = %[1, 2, 3];` packs the literal; an
element that is not a number raises `<no-convert>`.

The bracket is where they differ. `numbers[i]` is native indexing on a
concrete element pointer: no null test, no bounds test, and no negative-index
normalization. An index outside the elements is undefined as it is for the
equivalent C pointer, and the generated code is the same indexed load or
store, so a loop over one of these runs at the speed of the C it compiles to.
That is why the types exist.

```x2c
#include "typed-array.x"

int main(void) {
  ArrayDbl samples = ArrayDbl.new();
  for (int i = 0; i < 4; i++) samples.push(i * 0.5);
  samples[3] = samples[3] * 2.0;

  double total = 0.0;
  for (int i = 0, n = (int) samples.len(); i < n; i++) total += samples[i];
  printf("len=%zu total=%.2f\n", samples.len(), total);
  return 0;
}
```

```text
len=4 total=4.50
```

Bound the loop with `len`, as above. When the index may be out of range,
`try_get` is the checked read. It returns zero and leaves its output
untouched instead of reading past the end, and it normalizes a negative index
against the length the way `Array` does.

```x2c
#include "typed-array.x"

int main(void) {
  ArrayInt values = ArrayInt.new();
  values.push(10);
  values.push(20);

  int found = -1;
  int present = values.try_get(1, &found);
  printf("%d %d\n", present, found);
  present = values.try_get(5, &found);
  printf("%d %d\n", present, found);
  present = values.try_get(-1, &found);
  printf("%d %d\n", present, found);
  return 0;
}
```

```text
1 20
0 20
1 20
```

The other members keep their checks. `push`, `insert`, `remove`,
`take_last`, `shift`, and the slicing operations raise on a bad argument or
an empty receiver, and the slice bounds normalize negatives. Only the bracket
is raw. A typed `Array` boxes into a `Var` and iterates, so
`foreach(Var item, numbers)` and dynamic indexing through a `Var` receiver
both work. The dynamic bracket reaches the same raw member.

All six packed `Array`s can cross a `Context` or `Thread` boundary while boxed.
An `Array` owned by the source keeps its pointer, and its `Block` header and
backing allocation move together so it can continue growing after the source
closes. An `Array` borrowed from an outer `Context` is returned untouched.

Compound update is native as well. `values[i] += 1`, `values[i] <<= 2`, and
`values[i]++` compute in the element type and compile to the one instruction
the operator names. Overflow wraps, a narrow element truncates a result too
wide for it, and a signed right shift keeps the sign, as C does. Three
failures are kept, since they turn a hardware trap into something you can
catch: integer `/= 0` and `%= 0` raise `<div-zero>`, a shift count outside
the element's width raises `<bad-shift>`, and `%` or a bitwise operator on a
float element raises `<bad-types>`. Each raises before storing, so a failed
update leaves the element as it was.

An `ArrayChar` *store* loop has an extra cost: it cannot keep the element base
in a register, because a byte store may alias any object, including that base.
Wider element types and reads are unaffected. For a loop that is nothing but
byte stores, bind `array.bytes` to a `char *` and write through that.

## Working with Maps

A `Map` is a mutable Robin Hood hash table from `Var` keys to `Var` values.
Keys and values are both `Var`, so a `Map` can be heterogeneous.

```x2c
Map counts = %{};
List words = %("to" "be" "or" "not" "to" "be");
foreach(Var w, words)
  counts[w] += 1;
printf("%s\n", counts.repr());
```

```text
{ "be": 2, "to": 2, "not": 1, "or": 1 }
```

Numeric `+=` treats an absent destination as zero, inserts the right-hand
side, and returns the stored value, so `counts[key] += 1` counts in one call.
The first value takes the right-hand side's numeric tag, and later updates
keep that stored tag.

Only numeric `+=` initializes. A missing or `void` right-hand side, a
nonnumeric right-hand side, and every other compound operator require an
existing destination. Inserting the first value is a structural `Map` change
and may invalidate an outstanding traversal.

`getdefault` reads with a fallback and inserts nothing. `setdefault` inserts
the fallback and returns it. `contains` reports presence whatever the stored
value is. `copy` and `merge` combine `Map`s.

Nested literals work, and `Symbol`s make readable keys for fixed schemas:

```x2c
Map config = %{
  name: "x2c",
  targets: ["c"],
  limits: {depth: 8}
};
printf("%s\n", config.repr());
printf("targets is an Array: %d\n", config[<targets>] is Array);
```

```text
{ <targets>: [ "c" ], <limits>: { <depth>: 8 }, <name>: "x2c" }
targets is an Array: 1
```

### Map lookup, deletion, and traversal

`Map.get` and bracket reads return `void` for a missing key. The `try_`
operations report presence separately from the value and leave the output
pointer untouched on failure.

```x2c
Map ages = %{"ada": 36, "grace": 45};
ages["alan"] = 41;

Var found;
if (ages.try_get("ada", &found))
  printf("ada is %s\n", found.repr());
if (!ages.try_get("nobody", &found))
  printf("nobody is absent\n");

printf("bracket read of a missing key: %s\n", ages["nobody"].repr());

Var removed;
if (ages.try_del("alan", &removed))
  printf("removed alan=%s remaining=%u\n", removed.repr(), ages.len());
```

```text
ada is 36
nobody is absent
bracket read of a missing key: void
removed alan=41 remaining=2
```

`Map.try_next` performs the traversal. It takes a cursor you own, starting
at zero, and reports status separately from the key and value it writes, so
it can yield an entry whose key is raw `Null` without that looking like
exhaustion.

```x2c
Map ages = %{"ada": 36, "grace": 45};
unsigned cursor = 0;
Var key, value;
while (ages.try_next(&cursor, &key, &value))
  printf("%s -> %s\n", key, value.repr());
```

```text
grace -> 45
ada -> 36
```

That is the table's order, and it moves when the hash changes. Sort what you
print when the order matters.

`Map.get`, `Map.del`, and the bracket forms are wrappers over
these calls. `Map.set` and bracket writes are fail-fast and reject a `void`
key or value.

**Inserting or deleting invalidates outstanding cursors and iterators.**
Finish traversing, or collect what you need first, before changing the table's
structure. Missing values and exhaustion are reported differently across the
library; check each operation's documented result before assuming `void`
means absent.

### Iterating a Map

A `foreach` over a `Map` yields each value. Two binders ask for the key as
well, and the loop reads both out of the table without allocating:

```x2c
Map ages = %{"ada": 36, "grace": 45};
foreach(Var (key, value), ages)
  printf("%s -> %s\n", key, value.repr());
```

```text
grace -> 45
ada -> 36
```

`Map.iter` yields values, `Map.keys` yields keys, and `Map.enumerate` yields
two-element key/value `List`s. The one- and two-binder `foreach` forms use the
same paths and allocate no pair `List`s. [Iteration](iteration.md) covers
`foreach`, the `Iter` protocol, and the lazy combinators.
[The language reference](../reference/language.md) specifies the
destructuring form.

### Packed typed Maps

`typed-map.x` declares three `Map`s whose keys and values use concrete fields
rather than `Var`. `MapIntInt` and `MapLongDouble` store native numeric
scalars; `MapStringString` stores canonical `String` pointers. Each carries the
same lookup, defaulting, update, deletion, traversal, `copy`, and `merge`
operations that `Map` does. `%{...}` builds one when that is the declared
type, converting every key and value to the field type; an entry that cannot
be converted raises `<no-convert>`.

```x2c
#include "typed-map.x"

int main(void) {
  MapIntInt counts = %{1: 2, 3: 4};
  counts.updateindex(1, <+>, 10);
  counts.set(5, 25);

  MapStringString label = %{"name": "x"};
  label.updateindex("name", <+>, "2c");

  int out = 0;
  printf("one=%d present=%d\n", counts.get(1), counts.try_get(5, &out));

  unsigned cursor = 0;
  int key, value, total = 0;
  while (counts.try_next(&cursor, &key, &value)) total += value;
  printf("entries=%u total=%d\n", counts.len(), total);
  printf("label=%s\n", label.get("name"));
  return 0;
}
```

```text
one=12 present=1
entries=3 total=41
label=x2c
```

These types adopt `protocol Var`, so their `getindex`, `setindex`,
`updateindex`, and `postfixindex` members also provide bracket reads, writes,
compound updates, and numeric postfix updates. The numeric families update
with native arithmetic. For `MapStringString`, `<+>` concatenates, and both
postfix operators raise `<bad-op>`. In all three families `<+>` initializes
an absent key from the right-hand side, and every other update requires an
existing one.

All three packed `Map`s can be boxed into a `Context` or returned from a
`Thread`. An owned map keeps its pointer and can continue growing after the
source `Context` closes or `Thread.join` returns. Numeric maps move their
existing entries directly. `MapStringString` rebuilds its table with `String`s
canonicalized in the destination pool; `String` pointers may change, and if two
source keys become one destination `String`, the later entry in source bucket
order wins. Traversal order is otherwise unspecified. A map borrowed from an
outer `Context` is left untouched.

The element type has no `void`, so absence is reported another way. `get`,
`getindex`, `del`, `postfixindex`, and the updates that require a destination
raise `<bad-arg>` on a missing key where `Map` would return `void`. Use
`try_get`, `try_del`, and `try_next` for status, or `getdefault` for a
fallback.

## Indexing and slicing

Native C arrays and pointers keep C indexing. `Array`, `List`, `String`, and
`Map` also define `value[...]`.

```x2c
Array digits = %[0, 1, 2, 3, 4, 5];
List letters = %(a b c d);
String text = "sphinx";

printf("%s %s %s\n",
       digits[0].repr(), digits[-1].repr(), letters[1]);
printf("%c %c\n", text[0], text[-1]);
printf("out of range: %s\n", digits[99].repr());
```

```text
0 5 b
s x
out of range: void
```

`Array`, `List`, and `String` accept negative indices, counting from the end.
An out-of-range `Array` or `List` read returns `void`, and a missing `Map` key
returns `void` through brackets. An out-of-range `String` read returns `-1`; a
successful `String` read returns one byte as an `int`.

The packed numeric `Array`s are the exception on both counts. Their bracket is
raw native indexing, with no bounds test and no negative-index rule. See
[Packed numeric Arrays](#packed-numeric-arrays).

Writing is where the immutable/mutable split shows up in the syntax:

- `array[i] = value` and `map[key] = value` are supported.
- `list[i] = value` is **not**. The compiler rejects it.
- `string[i] = ch` is **not**, since a canonical `String` is immutable. Use the
  copy-producing `String.withindex`, or bind a transient `String.malloc`
  buffer to a `char *` and write through that native pointer.

<!-- ignore: `List` has no indexed assignment; this is a compile error -->
```x2c,ignore
List letters = %(a b c);
letters[0] = "z";   // xform: type ( List ) does not support bracket
                     // assignment
```

Slicing is `value[start:stop:step]`, available on `Array`, `List`, and
`String`. Any of the three parts may be omitted. One shared runtime call
normalizes negative bounds and negative steps, so the rules are identical
across the three types. A zero step is invalid.

**A slice returns the same type as its receiver.** Slicing an `Array` gives a
new `Array`, a `List` gives a new `List`, and a `String` gives a new `String`.
The result is a fresh value, and slices do not alias.

```x2c
Array digits = %[0, 1, 2, 3, 4, 5];
Array first_three = digits[:3];
Array every_other = digits[::2];
Array backwards = digits[::-1];

List letters = %(a b c d);
List middle = letters[1:3];

String text = "sphinx";
String tail = text[2:];

printf("%s %s %s\n",
       first_three.repr(), every_other.repr(), backwards.repr());
printf("%s %s\n", middle.repr(), tail.repr());
```

```text
[ 0, 1, 2 ] [ 0, 2, 4 ] [ 5, 4, 3, 2, 1, 0 ]
(b c) "hinx"
```

A helper-backed indexed expression is not a general C lvalue. `Array` and `Map`
assignment, compound assignment, and increment/decrement work through their
collection update calls, but the expression cannot be addressed as native
storage. `List` and `String` indexed updates are unsupported.

## Choosing between them

Start from what the data *is*.

- **`List`**: symbolic and structural data, such as ASTs, patterns,
  s-expressions, association lists, and anything you match over or want
  canonical identity for. Also the return type when a function produces a
  persistent value.
- **`Array`**: indexed mutation, stacks, queues, priority queues, sorting,
  and scratch accumulation. Also the fast path when you need O(1) length and
  random access.
- **`Map`**: keyed lookup, counting, interning tables, and configuration
  keyed by `Symbol` or `String`.
- **`String`**: canonical text you compare, key on, or return.
- **`Buffer`**: building text before you have a finished `String`.
- **`Symbol`**: short immediate names, tags, and closed sets of status
  values.

Some guidelines:

- **Building a sequence in a loop?** Accumulate into an `Array`, then call
  `Array.list()` if the caller wants a `List`. That is what `List.map` and
  `List.sort` do internally.
- **Need to look something up by name?** `Map`, keyed by `String`, `Symbol`, or
  `Atom`. Do not scan a `List` with `assoc` unless the `List` *is* the data.
- **Need to compare two sequences for equality cheaply?** `List`. That
  compare is a pointer compare. `Array` equality walks elements.
- **Need to mutate an element in place?** `Array`. If you find yourself
  wanting `list[i] = x`, you wanted an `Array`.
- **Passing a sequence to many places that must not change it?** `List` or
  `String`. There is no copy to make and none to forget.
- **Using it as a `Map` key?** `String`, `Symbol`, `Atom`, number, or `List`.
`Array` and `Map` hash by identity.
- **Every element the same C scalar, and the loop is hot?** The typed
  families above, a packed `Array` first, since it is the only one with a raw
  bracket. Use these types for their type checking and shorter code; measure
  speed when it matters.

A small program that uses each type for what it is good at: a `String` split
into words, a `Map` for counting, an `Array` for ranking, and `List` pairs to
carry each entry.

```x2c
String text = "the quick the lazy the end";

Map counts = %{};
foreach(Var word, text.words())
  counts[word] += 1;

Array ranked = %[];
foreach(Var (word, count), counts)
  ranked.push(%($count $word));
ranked.sort();
ranked.reverse();

foreach(List entry, ranked) {
  Var (count, word) = entry;
  printf("%s %s\n", count, word);
}
```

## Where to look next

- The [standard library overview](../library/overview.md) links to the
  API reference for each collection.
- [The language reference](../reference/language.md) has the percent
  literal, indexing, and slicing rules.
- [Iteration](iteration.md) for `foreach` and lazy pipelines,
  [Pattern Matching](match.md) for taking `List`s apart, and
  [Idioms](idioms.md) for recommended usage.
