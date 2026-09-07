# Values and Var

Most data in an x2c program has an ordinary C type: `int`, `double`, `char *`,
or a struct you declared.

Some code has to hold whatever the caller supplied. The element of a
heterogeneous list, the value stored behind a map key, `Error` detail, the
argument to a routine that prints anything: none of those have one static
type. In plain C you would write a tagged union by hand and a switch for every
operation. x2c gives you one: `Var`.

## A value that carries its own type

A `Var` is a single 64-bit value holding a payload plus a tag that names what
the payload is. Assigning a typed value into a `Var` boxes it, and the tag
records where the value came from.

```x2c
Var count = 42;
Var name = "ada";
Var setting = <verbose>;
Var numbers = %(1 2 3);

printf("%s %s %s %s\n",
       count.tag().str(), name.tag().str(),
       setting.tag().str(), numbers.tag().str());
```

```text
i32 string symbol list
```

Three queries read the tag. `Var.tag` returns the exact family, as above.
`Var.kind` returns the coarse category: `<integer>`, `<floating>`, `<symbol>`,
`<object>`, `<pointer>`, `<reference>`, or `<void>`. Use it when a whole group
of tags is treated alike. `value is i32` tests for one specific tag.

Every `Var` has the same size and shape whatever it holds, so heterogeneous
containers work. `List`, `Array`, and `Map` all store `Var`, so a list can mix
a number, a `String`, and a `Symbol`.

```x2c
~Var count = 42;
~Var name = "ada";
List mixed = %($count $name verbose);

foreach(Var item, mixed)
  printf("%s = %s\n", item.tag().str(), item);
```

```text
i32 = 42
string = ada
symbol = verbose
```

A `Var` is eight bytes, and most families keep their payload inside those
bits with no allocation. Five native families cannot: `long`,
`unsigned long`, `long long`, `unsigned long long`, and `long double`.
Boxing one of those allocates a small immutable box in the active scope, so
the boxed value follows the scope lifetime described in
[scopes and lifetime](memory.md). Those five tags are spelled `<long>`,
`<ulong>`, `<llong>`, `<ullong>`, and `<ldouble>`. Their payload widths follow
the corresponding native C types.

The complete tag set and the mapping from native source types to tags are in
[the language reference](../reference/language.md).

## Getting the value back out

Assigning a `Var` to a typed target unboxes it, and the compiler inserts the
conversion for you.

```x2c
Var boxed = 42;

int native = boxed;
double widened = boxed;
printf("%d %f\n", native, widened);
```

```text
42 42.000000
```

`Var.convert` performs every numeric conversion, and compiler-inserted
unboxing calls it before using the target's extractor. `int native = boxed;`
and an explicit conversion behave the same way.

A `Var` argument unboxes the same way at any call whose prototype x2c has
parsed. x2c does not read system headers, so the runtime declares the C99
`<math.h>` functions itself; a `Var` holding a number goes straight into one
with the ordinary include:

```x2c
#include <math.h>
~int main(void) {
Var ratio = 2.5;
printf("%f\n", sin(ratio));
~return 0;
~}
```

```text
0.598472
```

The scalar-named readers, `Var.int`, `Var.short`, `Var.uchar`, and their
siblings, work the same way. A matching tag reads its payload directly, and
any other numeric tag converts through `Var.convert`, so a reader call and
an assignment agree:

```x2c
Var small = (unsigned char) 44;

int converted = small;
int reader = small.int();
printf("tag=%s converted=%d reader=%d\n",
       small.tag().str(), converted, reader);
```

```text
tag=u8 converted=44 reader=44
```

A nonnumeric source raises the same structured `Error` either way. The raw
payload readers, `Var.integer`, `Var.floating`, and the wide `*_value`
readers, are silent low-level decoders that return zero for a tag they do
not handle.

A crossing to a pointer-shaped runtime type has nothing to convert. The
payload either has that tag or it does not. Assigning to `String`, `List`,
`Map`, `Array`, `Symbol`, or a type with a declared `protocol Var(T)`
conversion uses that type's exact reader, and a wrong tag yields NULL:

```x2c
Var listy = %(1 2 3);
String text = listy;
List same = listy;
printf("text=%d same=%d\n", text != NULL, same != NULL);
```

```text
text=0 same=1
```

Test the result, or test `listy is <list>` first. `Var.pointer` is the
unchecked read, for a raw native pointer that has no tag to check.

## Formatting dynamic values

`String` interpolation displays a `Var` with `Var.str`, whether it holds a
number, a `String`, or another dynamic value:

```x2c
Var key = 23, val = 3.14, answer = "hello";
puts(%"output: ($key: $val) = $answer");
```

A printf-family call with a single static format literal can use the format
to request native numeric arguments:

```x2c
Var key = 23, val = 3.14, answer = "hello";
printf("output: (%d: %.2lf) = %s\n", key, val, answer);
```

For numeric conversions, the compiler inserts the checked `Var.convert`
path used by typed assignment and then passes the format's promoted C vararg
type. A `Var` supplied for `%s` uses `Var.str`. This applies to `printf`,
`fprintf`, `sprintf`, `snprintf`, and the `printf` methods on `String`, `File`,
and `Buffer`.

The format must be a direct static literal whenever a variadic argument is a
`Var`. Automatic lowering covers integer, floating, `%c`, `%s`, width, and
precision arguments with the `hh`, `h`, `l`, `ll`, and `L` modifiers. Use an
explicit native conversion for `j`, `z`, `t`, `%p`, `%n`, wide
character/string conversions, positional formats, or a dynamic format. Calls
containing only native arguments keep C's printf behavior.

## Null and void

`Null` is data; `void` reports that no value is available.

**`Null`** is the all-zero `Var`. It is a *value*: the null pointer, the
external `nil`. `Null` is data. You may store it in a `List`, an `Array`, or a
`Map`, and iterating a collection can hand it back to you.

**`void`** is the all-ones `Var`, and it is *not* a value. It is the
sentinel an API returns to say "there is nothing here": out of range, key
absent, iterator exhausted. It is excluded from every collection and
iterator value domain. You cannot push it into an `Array`, store it as a `Map`
key or value, or receive it as a successful iterator payload. In an
expression, lowercase `void` is the literal for this sentinel. In a
declaration, cast, `sizeof`, or parameter list, `void` keeps its C type
meaning. `Null` says the value is zero or empty; `void` says there is no
value.

You can inspect the sentinel without it becoming data. Two `void` operands
are equal with `==` and identical with `===`, and `!=` and `!==` are their
inverses. A sentinel and any ordinary value are unequal. The same rules
apply to `Var.equal`, `Var.fallback_equal`, `Var.same`, and the four
comparison operations accepted by `Var.binary`. Display and readable output
both spell the sentinel `void`.

`void` is what you get from an out-of-range indexed read:

```x2c
List items = %(10 20 30);

Var present = items[1];
Var missing = items[7];
printf("present=%d missing=%d\n", present is void, missing is void);
```

```text
present=0 missing=1
```

A missing `Map` key reads the same way, but `Map` also offers a status-bearing
form that keeps presence separate from the payload. Prefer it:

```x2c
Map settings = %{width: 80};

Var height;
if (settings.try_get(<height>, &height)) {
  int value = height;
  printf("height is %d\n", value);
} else {
  printf("height is unset\n");
}
```

```text
height is unset
```

`Null` is a value that happens to be zero. `NULL` converts to the same value
when an x2c crossing requires a `Var`:

```x2c
Var absent = (Var) { .u64 = 0 };
Var also_absent = NULL;
List row = %($absent 1);

printf("null=%d void=%d truthy=%d len=%d\n",
       absent.is_null(), absent is void, absent.truthy(), row.len());
```

```text
null=1 void=0 truthy=0 len=2
```

Conditions are where the distinction matters. `Null` is false. `void` is
**not** false. It is outside the value domain, so a truthiness test on
`void` fails fast and terminates the program instead of taking the else
branch. Do not write `if (maybe_missing)` on a value that might be `void`.
Test it with `Var.is_void`, or use the status-bearing API and never hold a
`void`.

The representation of `void` and its exclusion from collections and iterators
are consistent. Its meaning in a particular API can vary: missing,
exhausted, or invalid. Read that API's description before interpreting the
result.

## Truthiness

When a condition's static type participates in a protocol with `truth`, the
compiler applies that member. Dynamic `Var` uses `Var.truth`; built-in
`String`s, `List`s, `Array`s, `Map`s, and `Buffer`s use their concrete content
rule. This covers `if`, `while`, `do`, classic `for`, `?:`, unary `!`, and each
participating operand of `&&` and `||`. Short-circuit evaluation is untouched.
Each operand is converted only when C would evaluate it, so the right-hand
side of `&&` does not run when the left is false.

```x2c
Var name = "";
Var full = "ada";

if (!name) printf("no name\n");
if (full && full.tag() == <string>) printf("name=%s\n", full);
```

```text
no name
name=ada
```

False: numeric zero, `Symbol` zero, `Null` and null pointers, the canonical
empty `String` and empty `List`, and empty `Array`, `Map`, `Block`, `Bytes`, or
`Buffer` values. True: everything else nonzero or nonnull, including NaN and
the infinities, which are numbers. A nonnull `Iter` is true even when it is
exhausted. The condition tests the iterator pointer; it does not try to advance
it.

## Arithmetic on Var

If either operand of `+`, `-`, `*`, `/`, `%`, `<<`, `>>`, `&`, `^`, or `|`
is a `Var` and the other is a `Var` or statically numeric, both operands
are boxed as `Var`, the runtime performs the operation, and the result is a
`Var`. You write C syntax; the compiler inserts the boxing.

```x2c
Var count = 10;

Var total = count * 3 + 1;
double scaled = count * 2.5;
printf("total=%s scaled=%f\n", total, scaled);
```

```text
total=31 scaled=25.000000
```

Expressions with no `Var` operand stay native C, so this costs nothing where
you did not ask for it. Integer operands use integer promotion; arithmetic
keeps the promoted type's low bits, so overflow wraps to that type's width.
Floating operands work in the widest participating floating family with host
behavior. Remainder, the shifts, and the bitwise
operators reject a floating operand. There is no dynamic unary numeric
operator, and no dynamic `++` or `--`.

A statically nonnumeric peer is a compile-time error:

<!-- ignore: the compiler rejects a statically nonnumeric arithmetic peer -->
```x2c,ignore
Var count = 10;
String label = "items";
Var bad = count + label;   /* xform: dynamic numeric operators require
                              numeric operands */
```

A `Var` that *happens* to hold a `String` passes the static check and fails
at run time instead.

These rules do not apply to comparisons. With a `Var` operand, `==` and `!=`
use `Var.equal`, `===` and `!==` use `Var.same`, and the relational
operators use `Var.compare`. See
[the language reference](../reference/language.md) for the dispatch.

## Handling dynamic-operation failures

`Var.convert`, `Var.binary`, `Var.truthy`, `Var.update`, and `Var.postfix`
raise cause-specific `Error`s. Their default policies fail fast, and
compiler-inserted conversions raise the same causes. Install a filtered
`catch` where your code can recover from one of them.

```x2c
Var quotient = void;
try quotient = Var.binary(10, </>, 0);
catch %(div-zero):
  printf("no quotient: division by zero\n");
```

```text
no quotient: division by zero
```

```x2c
Var narrowed = Var.convert(300, <u8>);
int value = narrowed;
printf("%s holds %d\n", narrowed.tag().str(), value);
```

```text
u8 holds 44
```

Integer-to-integer conversion keeps the destination width's low bits and
does not detour through floating point, so 300 narrowed to `<u8>` is 44.
Float-to-integer conversion truncates toward zero, and raises
`<conv-range>` for NaN, the infinities, and anything not representable.
Other dynamic-operation causes include `<div-zero>`,
`<bad-shift>`, `<no-convert>`, `<bad-op>`, `<bad-types>`, and `<void-op>`;
the full list and their exact meanings are in
[the language reference](../reference/language.md).

## Compound assignment

Numeric compound assignment works when either side involves a `Var`. The
compiler takes the address of the lvalue once, and the runtime loads,
computes, converts to the target's declared family, and stores only after
every step has succeeded. A failed operation or conversion leaves the target
unchanged.

```x2c
Var total = 1;
total += 5;

int native = 7;
Var delta = 10;
native += delta;

int shown = total;
printf("total=%d native=%d\n", shown, native);
```

```text
total=6 native=17
```

Both directions work: a `Var` lvalue with any numeric operand, and a native
scalar lvalue updated by a `Var`. C indexing and member access are fine,
since those are addressable lvalues. Enum and bitfield targets are excluded.

A collection index does not work. `array[i]` is a helper call, not a C
lvalue:

<!-- ignore: indexed collection values are not addressable C lvalues -->
```x2c,ignore
Array counts = %[1, 2, 3];
counts[0] += 1;   /* xform: indexed collection values do not support += */
```

Read, compute, and assign through the collection instead:

```x2c
Array counts = %[1, 2, 3];

Var current = counts[0];
counts[0] = current + 1;

Var shown = counts[0];
printf("%s\n", shown);
```

```text
2
```

## When Var is the wrong tool

`Var` is not a better `int`. Use it when the dynamic type is part of the
problem, and use a static type when it is not.

Use `Var` when:

- the value is heterogeneous: a `List` element, a `Map` key or value, or
`Error` detail;
- the tag itself is what your code inspects or reports;
- you are crossing a boundary with no target type, such as a variadic call or
  a generic callback signature.

Prefer a plain C or runtime type when:

- **The static type already says what the function takes.**
  `long checksum(String)` tells a reader more than `Var checksum(Var)`, and
  the compiler checks it. With `Var` you have moved a class of type error
  from translation time to run time, and that costs you.
- **Cost matters in a hot path.** A dynamic operation calls into the shared
  runtime, which validates the encoding and decodes both tags, where the
  native version is one machine instruction. Boxing a `long` or a
  `long double` also allocates a scope-owned box.
- **The conversion is already proven.** If a call takes a `Var` parameter,
  pass your `String`, `Symbol`, collection, or scalar straight in and let the
  compiler insert the crossing. Declaring a local `Var` first only to hand
  it over adds a name and hides the type.

Written out, the two cases look like this:

```x2c
/* Var fits here: the tag is the answer. */
String describe(Var value) {
  return value.tag();
}

/* Var would only erase a contract the caller already knows. */
int clamp(int value, int low, int high) {
  return value < low ? low : value > high ? high : value;
}
```

The numeric conversion matrix does *not* generalize to nonnumeric tags.
`String`, `Symbol`, collection, and pointer crossings have their own typed
readers, and asking for one of those payloads from a `Var` with a different tag
is an error.

`String` interpolation reads a value instead of demanding a tag, so it has no
such limit. A numeric segment renders through its nearest declared `T_str`
converter when it has one and through `Var.str` otherwise. Converter lookup
follows the source's typedef chain, and an exact converter wins. A segment
already typed `Var` renders through `Var.str` whatever tag it holds:

```x2c
int count = 2;
Var value = 3.14;

String counted = %"processed $count items";  /* processed 2 items */
String read = %"v = $value";                   /* v = 3.140000 */
```

## Where to go next

- [Symbols and atoms](symbols.md) for the `<name>` values used above as tags
  and outcome codes.
- [Strings, lists, arrays, and maps](collections.md) for the containers that
  store `Var`.
- [Iteration](iteration.md) for `Iter`, `try_next`, and the exhaustion rule
  that `void` participates in.
- [Scopes and lifetime](memory.md) for what owns a boxed wide value.
- [Idioms](idioms.md) for practical usage, and
  [the language reference](../reference/language.md) for the full rules.

The generated [Var](../library/modules/var.md),
[conversion](../library/modules/varconvert.md), and
[operation](../library/modules/varops.md) references list every callable by
API tier.
