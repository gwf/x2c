---
title: Pull up a chair.
kicker: x2c for people who already know C, in the order you will trip over it.
lede: "x2c is a strict superset of C that compiles to C. It adds three ideas, and most of the rest of the language follows from them. This page is the overview I would give you across a table: what is different, with small programs that run."
---

## Install it. Run it.

One command installs a release. You need `curl`, `tar`, and a C compiler
named `cc`.

```sh
curl -fsSL https://x2c-lang.dev/install.sh | sh
export PATH="$HOME/.local/x2c/bin:$PATH"
```

Save this as `hello.x`. It is C with one new thing in it.

```x2c
int main(int argc, char **argv) {
  String who = argc > 1 ? argv[1] : "world";
  puts(%"hello, $who");
  return 0;
}
```

```sh
x2c run hello.x -- Brian            # hello, Brian
x2c build -o hello hello.x          # keep the executable
x2c translate hello.x               # write the C and read what I did
```

`x2c run` translates to C, compiles, caches the executable, and runs it.
Run it again without touching the file and the cached executable runs.
Everything after `--` is passed in `argv`. The new thing is `%"hello, $who"`,
which is string interpolation. It produces a `String`. Both are explained
below.

## Your C still works

Rename a `.c` file to `.x` and it builds. Same headers, same structs, same
libraries, same debugger. x2c has its own C preprocessor, so X-macros,
token pasting, and nested `#ifdef`s work as they do in C.

```x2c
#include <stdlib.h>
#include <string.h>

typedef struct Server { char *host; int port; } Server;

int main(void) {
  Server *s = malloc(sizeof *s);
  s->host = strdup("localhost");
  s.port = 8080;                  // `.` reaches through one pointer
  printf("%s:%d\n", s->host, s->port);
  free(s->host);
  free(s);
  return 0;
}
```

The only x2c in there is `s.port`. A dot reaches through one pointer, so
`.` works on a struct and on a pointer to one. The arrow still works.

This is the first idea: just enough structure. x2c imposes one data model
and one lifetime rule on C, and every other feature is syntactic sugar for
C you could have written; `x2c translate` shows you that C. The language
was nearly named Sugar. It reads like a dynamic language and runs like the
static one it is. The sugar removes code: the arrow goes, reference
parameters replace `&x` at call sites and `*x` inside functions, and most
x2c programs have no pointers in them.

Multiple files work the way you expect. `#include "unit.x"` gives you that
unit's public names, and `static` keeps a name private to its file, exactly
as in C. Plain `.c`, `.o`, and `.a` files go on the same command line, and
the flags you already use pass through:

```sh
x2c build -I include -O2 -o app main.x parse.x legacy.c
```

Nothing below is mandatory. Every feature is opt-in, so you can adopt x2c
one file at a time in a codebase that contains no other x2c. The book's
[guide for C programmers](../docs/guide/from-c.html) is the long version of
this section.

## One value type

`Var` is the data model. It is an eight-byte tagged word that holds any
value and its type: an integer, a double, a `String`, a `List`, a pointer, a value of your own
type. Collections store `Var`, `%s` prints one, and assigning one to a
typed variable converts it. A `String` is still a C string and an `Array`
is still a C block, so the dynamic view and the native view are the same
bytes.

```x2c
Var n = 42, name = "Ada";
Var next = n + 1;                   // arithmetic on whatever is inside
printf("%s %s\n", next, name + " Lovelace");
int whole = n;                      // a typed destination converts
if (n is int) puts("n holds an int");
Array mixed = [1, "two", <three>, 4.5];
printf("%s\n", mixed.repr());       // [ 1, "two", <three>, 4.5 ]
~assert(whole == 42 && next == 43);
```

Your static types mean what they meant in C. `Var` appears only where you
write it, and a conversion that cannot work raises an error with your file
and line. More in [values](../docs/guide/values.html).

## Text that composes

`String` is immutable and canonical: equal text is one object, so `==` on
two Strings is a pointer compare. A `String` is also a `char *`, so every C
function that takes a `char *` takes a `String`.

```x2c
String line = "  GET /docs/guide/values.html  ";
(String method, String path) = line.strip(NULL).split(" ");
String page = path.split("/").last().str().replace(".html", "");
puts(%"$method $page ($(path.len()) bytes)");   // GET values (23 bytes)
printf("%s\n", path[1:5]);                      // docs
switch (method.lower()) {
  case "get":  puts("read it");  break;
  case "post": puts("write it"); break;
  default:     puts("refuse it");
}
~assert(page == "values" && path[-4:] == "html");
```

`%"..."` interpolates `$name` for a variable and `$(expr)` for anything
else. Slices are `[start:stop]`, and negative indices count from the end.
`split`, `join`, `strip`, and `replace` are methods. `words()` and
`lines()` return a cursor, so `foreach` reads one piece at a time without
building a list. `switch` on a String compares content.

## Lists, Arrays, Maps, and Symbols

There are two kinds of data. `String`, `List`, and `Symbol` are values.
Equal content is one object, nothing mutates, and sharing is free. `Array`
and `Map` are objects. They change in place and have identity. `==`
compares content for both kinds, and `===` is true when two handles are the
same object.

```x2c
List tags = %(fast small weird);         // a List: immutable, shared
Array scores = [7, 3, 9];                // an Array: mutable, has identity
Map stock = {tea: 12, "earl grey": 3};   // bare keys are Symbols
scores.push(5);
stock[<cocoa>] = 4;                      // <cocoa> is a Symbol
Array twin = [7, 3, 9, 5];
printf("%d %d\n", scores == twin, scores === twin);         // 1 0
printf("%s %s\n", scores[-1], stock["earl grey"]);          // 5 3
printf("%d %d\n", <weird> in tags, stock[<milk>] is void);  // 1 1
~assert(tags.len() == 3 && stock[<tea>] == 12 && stock[<cocoa>] == 4);
```

`%(...)` builds a List. The same literal builds patterns, errors, and code.
`<name>` is a Symbol: an interned constant, so comparing two of them is
comparing two pointers. A missing Map key reads as `void`. Test it with
`is void`, because `void` in a condition is a compile error. `x in c` tests
membership in any collection. See
[collections](../docs/guide/collections.html) and
[symbols](../docs/guide/symbols.html).

## Lifetime by scope

The lifetime rule is the other half of the first idea. `String`, `List`,
and `Symbol` values are interned in shared pools, which is why equal content is one object. Everything else
is allocated in a scope, and the scope is freed when its statement ends.
You manage memory in the unit you write code in: a loop body, a request, a
file. `auto { ... }` opens a scope. `auto` on a loop body gives each
iteration its own scope, so working data is freed every iteration. `auto`
on a declaration frees that one value at block exit. `defer` runs a
statement at block exit, on `return`, and while an error unwinds. There is
no garbage collector and no `free`.

```x2c
long words = 0;
for (int day = 0; day < 3; day++) auto {
  // Everything allocated in here is freed when the iteration ends.
  List parts = %"day $day: tea and biscuits".split(" ");
  words += parts.len();
}
File scratch = auto tmpfile();       // closed when this block exits
scratch.puts("no free, no collector\n");
FILE *sink = fopen("/dev/null", "w");
defer fclose(sink);                  // runs however the block exits
fprintf(sink, "%ld words\n", words);
~assert(words == 15);
```

When a lifetime does not fit a block, `Scope.open()` and
`Scope.close()` do the same job by hand. Your `malloc` and `free` still
work for C data, and they are still your problem. The details are in
[memory](../docs/guide/memory.html).

## Loops and matching

This is the second idea: pieces that fit together. Everything from here to
the compiler section is built from the pieces above, and each one takes a
few lines.

`foreach` iterates over anything with elements: a collection, a `File`
line by line, a `Channel` until it closes. Two typed names unpack a Map's
pairs. A parenthesized declaration destructures a List. `match` compares
data against patterns: `?x` binds one element, `*rest` binds the remaining
elements, and `if` adds a guard.

```x2c
Array orders = [%(tea 2 "Ada"), %(coffee 1 "Grace"), %(tea 3 "Linus")];
Map cups = {};
foreach (List order in orders) {
  (Symbol drink, int count, String who) = order;
  cups[drink] += count;
  match (order) {
    case %(tea ?n ?name) if (n > 2): puts(%"$name is thirsty");
    case %(coffee *rest):            printf("coffee for %s\n", rest[1]);
    default:                         {}
  }
}
foreach ((Symbol drink, int total) in cups)
  printf("%s: %d\n", drink.str(), total);
if (orders[0] ~= %(tea ?(int n) *)) printf("first order: %d teas\n", n);
~assert(cups[<tea>] == 5 && cups[<coffee>] == 1);
```

`~=` matches one pattern as a condition, and its bindings are in scope
where the test is true. `?(int n)` also checks the type. Cases do not fall
through, and a case body is one statement, so use braces for more. See
[iteration](../docs/guide/iteration.html) and
[pattern matching](../docs/guide/match.html).

## Functions without the ceremony

Functions are C functions with a few shortcuts. An expression body replaces
`{ return ...; }`. A lambda is `%!(params) => expr`. It captures locals by
value, and `using &name` shares one by reference. `Map @opts` collects
keyword arguments, `List @rest` collects the leftovers, and `T.name`
defines a method on any typedef you own, called with a dot.

```x2c
typedef struct Range { int lo, hi; } Range;

int twice(int x) => x * 2;
int Range.clamp(Range self, int n) =>
  n < self.lo ? self.lo : n > self.hi ? self.hi : n;
long sum(List @rest) => rest.foldl(0, %!(total, n) => total + n);

String brew(String tea, Map @opts) {
  String size = opts.getdefault(<size>, "small").str();
  return %"$size $tea";
}

int main(void) {
  int bias = 10, calls = 0;
  Func shift = %!(int x) => x + bias;              // copies bias now
  Func count = %!(void) using &calls => calls++;   // shares calls
  bias = 99;
  count(); count();
  printf("%s %d\n", shift(1), calls);              // 11 2
  puts(brew("oolong", size: "large"));             // large oolong
  Range percent = {0, 100};
  printf("%d %d %ld\n", twice(21), percent.clamp(140), sum(1, 2, 3, 4));
  ~assert(percent.clamp(-5) == 0 && sum() == 0);
  return 0;
}
```

Functions can be defined in any order, with no prototypes. A `Func` is a
value you can store, pass, and return.

## Errors are data

`raise` throws a List. Its first element is the cause, a Symbol, and the
rest is whatever detail you care to carry. `catch` selects by pattern on
that List. `catch:` takes everything else, and `finally` runs after the
handlers.

```x2c
#include <stdlib.h>

int parse_port(String text) {
  int port = atoi(text);
  if (port <= 0 || port > 65535)
    raise %(bad-arg (reason "not a port") (text $text));
  return port;
}

int main(void) {
  foreach (String s in %("8080" "http")) {
    try printf("port %d\n", parse_port(s));
    catch %(bad-arg *details):
      printf("%s: %s\n", s, details.assoc(<reason>));
    catch: puts("something else");
    finally puts("checked");
  }
  return 0;
}
```

The runtime raises the same way: a missing file is `not-found`, a bad
conversion is `no-convert`. Allocation, open, read, and write raise, so
there is no `if (p == NULL)` after each call. An uncaught error prints its
cause with your file and line, as in
`uncaught <no-convert> in main (config.x:3)`, and aborts. See
[exceptions](../docs/guide/exceptions.html).

## Your own types

`class` writes the struct and its default methods. A value class gets `new`,
`==`, a hash, and `repr` from its fields. Add a `*` and you have a pointer
class, allocated in the current scope and compared by identity. Operators
are methods: `T.add` gives you `+`, `T.equal` gives `==`, `T.getindex`
gives `[]`, and `T.str` is what interpolation prints.

```x2c
class Vec { int x; int y; };                 // a value class
class Tab { String name; long cents; } *;    // a pointer class

Vec Vec.add(Vec a, Vec b) => Vec.new(a.x + b.x, a.y + b.y);
String Vec.str(Vec v) => %"($(v.x), $(v.y))";

int main(void) {
  Vec sum = Vec.new(1, 2) + Vec.new(3, 4);   // calls Vec.add
  puts(%"sum: $sum");                        // sum: (4, 6)
  Map seen = {};
  seen[sum] = "home";                        // values hash by content
  Tab tab = Tab.new("Brian", 0), same = tab;
  same.cents += 450;
  printf("%s %ld %d\n", seen[Vec.new(4, 6)], tab.cents, tab == same);
  ~assert(tab.cents == 450 && sum == Vec.new(4, 6));
  return 0;
}
```

`$derive` writes methods from a plain struct's fields. Ask for `<json>`,
`<equal>`, and `<repr>` and you get a JSON round trip, deep equality, and a
printer:

```x2c
#include <derive.x>

typedef struct Person { String name; int age; } Person;
$derive(Person, <json>, <equal>, <repr>);

int main(void) {
  Person ada = { "Ada", 36 };
  String text = ada.json();                  // {"age":36,"name":"Ada"}
  Person back = Person.from_json(text);
  printf("%d %s\n", ada.equal(back), back.repr());
  ~assert(text == "{\"age\":36,\"name\":\"Ada\"}");
  return 0;
}
```

A protocol is a set of methods a type adopts explicitly.
`protocol Meters(T) { ... }` declares methods on the base type `Meters`.
`protocol Meters(Km);` adopts them for `Km`, which only needs a `meters`
method that converts it to `Meters`. The compiler writes the adapters. There are no
vtables and no runtime registry.

```x2c
class Meters { long value; };
class Km { long value; };

protocol Meters(T) { String T.describe(T); }

String Meters.describe(Meters m) => %"$(m.value) m";
Meters Km.meters(Km k) => Meters.new(k.value * 1000);
protocol Meters(Km);

int main(void) {
  Km trip = Km.new(3);
  puts(trip.describe());                     // 3000 m
  return 0;
}
```

The book covers [classes](../docs/guide/system-macros.html),
[protocols](../docs/guide/protocols.html), and
[deriving records](../docs/guide/deriving-records.html).

## Packages without collisions

x2c has one flat namespace, as C does. `import` binds a package to a name
you choose, and the package's types and functions are reached through that
name, so two packages can both export a `Regexp`:

```x2c
import "pcre2" as rx;

int main(void) {
  auto rx.Regexp version =
    rx.Regexp.compile("(?<major>\\d+)\\.(?<minor>\\d+)", 0);
  rx.RegexpMatch found = version.match("x2c 0.15.0");
  if (found) puts(%"major $(found[<major>]), minor $(found[<minor>])");
  return 0;
}
```

`x2c install pcre2` fetches a package from the index, and `x2c list` shows
what you have. Most packages wrap a C library you already know, such as
PCRE2, SQLite, libcurl, libuv, raylib, or torch, and the native API is
still available. Prebuilt bundles exist for macOS and Linux. See
[packages](../docs/guide/packages.html).

## The compiler is yours

This is the part that either delights C programmers or offends them. It
is the third idea: a language that extends itself. A code literal is a `List`, so the `%(...)` that builds data also
builds patterns, errors, and syntax. Put `meta` in front of a function and
the compiler can call it: `$fib(20)` runs during translation, and its
result is inserted as a constant. A `macro` is a typed template over syntax trees, so
`$minutes(1 + 1)` is 120 and the oldest joke in the C preprocessor is
retired. A `Decorator` receives the function that follows it and can
rewrite it. Each of `try`, `match`, lambdas, and interpolation is one
source file, built into the compiler and buildable the same way outside it.

```x2c
meta static int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);

macro Expression $minutes(Expr $hours) => $hours * 60;

macro Decorator $trace(Function $f) {
  printf("enter %s\n", $Code.name($f));
  @Code.body($f)
}

static const int table[] = { $fib(10), $fib(20) };   // { 55, 6765 }

$trace()
static int answer(void) => 42;

int main(void) {
  printf("%d %d %d\n", table[1], $minutes(1 + 1), answer());
  ~assert(table[0] == 55 && $minutes(1 + 1) == 120);
  return 0;
}
```

`keyword` makes a macro a statement, so `repeat (3) stmt` can be syntax in
your file. Compile-time code is ordinary x2c, running inside the compiler
with the runtime available. The compiler is written in x2c, and you can
read every line. Start with
[meta functions](../docs/guide/meta-functions.html),
[macros](../docs/guide/macros.html), and
[generating code](../docs/guide/generating-code.html), then look at
[how the compiler is built](../docs/internals/architecture.html).

## Speed, with receipts

Everything becomes C and goes through your C compiler's optimizer, so typed
code costs what C costs. A `Var` costs a tag check. When that matters, the
typed families in `typed-*.x`, such as `ArrayInt`, `MapIntInt`, and
`ListInt`, store native values and skip boxing.

```x2c
#include "typed-array.x"
#include "typed-map.x"

int main(void) {
  ArrayInt codes = [200, 404, 200, 500, 200];
  MapIntInt counts = {};
  for (int i = 0, n = codes.len(); i < n; i++) counts[codes[i]] += 1;
  printf("%d ok\n", counts[200]);            // 3 ok
  ~assert(counts[404] == 1 && counts.getdefault(301, 0) == 0);
  return 0;
}
```

The
[Benchmarks Game suite](https://github.com/gwf/x2c/blob/main/examples/shootout/README.md)
has ten problems written in x2c twice, once with ordinary collections and
once tuned with typed containers, beside contributed C, Python, Rust, C++,
Go, and Java programs. On the eight problems every column covers, idiomatic
x2c ran at a median of 2.52 times C's time and tuned x2c at 1.07. Python
took 20 times. The idiomatic x2c came in at 1.16 times Python's line count.
Those are local measurements of those programs on one machine, not a
ranking.

## The toolbox

`x2c new demo` starts a project with a manifest and a `src/main.x`. `x2c
test` finds and runs your test files. `x2c repl` compiles what you type,
and `x2c lsp` gives your editor diagnostics, definitions, and hover.

```sh
x2c new demo && cd demo
x2c run -q -- Brian                 # Hello, Brian!
x2c test
x2c repl
```

A test is a function with `$test()` in front of it:

```x2c
#include "test.x"

$test()
static void split_on_spaces(void) {
  List parts = "tea and biscuits".split(" ");
  $expect_eq(parts.len(), 3);
  $expect(parts[0] == "tea");
}

$test.main();
```

Builds are source-mapped, so compiler errors, `__LINE__`, and runtime
failures report lines in your `.x` file. A file whose first line
is `#!/usr/bin/env -S x2c script` runs like a shell script and rebuilds
only when something it depends on changes. The [command
reference](../docs/reference/cli.html) has the rest, and
[scripting](../docs/guide/scripting.html) covers scripts.

## Where next

The [examples page](../examples/) puts every example in one place, and you
can run the small ones in your browser. The [book](../docs/) has the whole
language. Keep the
[cheat sheet](../cheatsheet/) next to you while you read, then go write
something you would not have bothered to write in C.
