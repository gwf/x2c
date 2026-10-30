---
title: Pull up a chair.
kicker: x2c for people who already know C, in the order you will trip over it.
lede: "x2c is a strict superset of C that compiles to C. It adds four ideas, and most of the rest of the language falls out of them. This is how I would get you going if we were sitting across a table: what is different, small code that runs, and no time spent on things you already know."
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
Run it again without touching the file and it goes straight to your program.
Everything after `--` lands in `argv`. The new thing is `%"hello, $who"`,
which is string interpolation. It produces a `String`, and you will meet
both properly in a minute.

## Your C still works

Rename a `.c` file to `.x` and it builds. Same headers, same structs, same
libraries, same debugger. x2c runs real C headers through its own
preprocessor, so X-macros, token pasting, and your tower of `#ifdef`s come
along for the ride.

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
you can stop caring which one you need. The arrow still works.

This is the first idea: still C, with less of it. Every x2c feature is
sugar that lowers to C you can predict. The language was nearly named
Sugar. It reads like a dynamic language and runs like the static one it is.
The sugar subtracts: you can drop the arrow, and reference parameters take
the pointer plumbing out of call sites.

Multiple files work the way you expect. `#include "unit.x"` gives you that
unit's public names, and `static` keeps a name private to its file, exactly
as in C. Plain `.c`, `.o`, and `.a` files go on the same command line, and
the flags you already use pass through:

```sh
x2c build -I include -O2 -o app main.x parse.x legacy.c
```

Nothing below is mandatory. Every feature is opt-in, so you can adopt x2c
one file at a time in a codebase that has never heard of it. The book's
[guide for C programmers](../docs/guide/from-c.html) is the long version of
this section.

## One value type

This is the second idea: one data model, two speeds. `Var` is an
eight-byte tagged word that holds anything and knows what it holds: an
integer, a double, a `String`, a `List`, a pointer, a value of your own
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

Your static types still mean what they always meant. `Var` only shows up
where you ask for it, and a conversion that cannot work raises an error
that names your line instead of quietly handing you garbage. More in
[values](../docs/guide/values.html).

## Text that composes

`String` is immutable and canonical: equal text is one object, so `==` on
two Strings is a pointer compare that means what you meant. A `String` is
also a `char *`, so every C function that takes one still does.

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
`split`, `join`, `strip`, and `replace` do what they say. `words()` and
`lines()` hand `foreach` a cursor instead of building a list first. And
`switch` on a String compares content, which C never let you do and you
always wanted.

## Lists, Arrays, Maps, and Symbols

There are two kinds of data. `String`, `List`, and `Symbol` are values.
Equal content is one object, nothing mutates, and sharing is free. `Array`
and `Map` are objects. They change in place and have identity. `==`
compares content for both kinds, and `===` asks whether two handles are the
same object. Shared immutable values are the top layer of the third idea,
which the memory section below explains.

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

`%(...)` quotes a List the way Lisp does. It is also how x2c writes
patterns, errors, and code, which is the whole trick. `<name>` is a Symbol:
an interned constant, so comparing two of them is comparing two pointers. A
missing Map key reads as `void`. Test it with `is void`, because `void` in
a condition is an error, not a false. `x in c` asks about membership in
anything that has members. See
[collections](../docs/guide/collections.html) and
[symbols](../docs/guide/symbols.html).

## Loops and matching

`foreach` walks anything with elements: a collection, a `File` line by
line, a `Channel` until it closes. Two typed names unpack a Map's pairs. A
parenthesized declaration destructures a List. `match` takes data apart by
shape: `?x` binds one element, `*rest` binds whatever is left, and a guard
can follow.

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

`~=` is the same matcher used as a condition, and its bindings exist where
the test holds. `?(int n)` also checks the tag. Arms never fall through,
and a case body is one statement, so use braces for more. See
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

Define functions in any order you like. There are no prototypes to keep in
sync, and a `Func` is a first-class value you can store, pass, and return.

## Lifetime by scope

This is the third idea. There is no garbage collector, and you will not
write `free` for x2c values. You manage memory in the unit you write code
in: a loop body, a request, a file. Memory belongs to a scope, and the
scope dies when its statement ends. `auto { ... }` makes one. Put `auto` on
a loop body and every iteration gets its own scope, so working data never
piles up. `auto` on a declaration cleans up that one value at block exit.
`defer` runs any statement at block exit, on `return`, and while an error
unwinds.

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

When a lifetime does not fit a block, `Scope.retain()` and
`Scope.release()` do the same job by hand. Your `malloc` and `free` still
work for C data, and they are still your problem. The details are in
[memory](../docs/guide/memory.html).

## Errors are data

`raise` throws a List. Its first element is the cause, a Symbol, and the
rest is whatever detail you care to carry. `catch` selects by pattern, so
you catch the shape of a failure, not a class hierarchy. `catch:` takes
everything else, and `finally` runs after the handlers.

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
conversion is `no-convert`. Allocation, open, read, and write raise instead
of returning a code, so the `if (p == NULL)` after every call goes away. An
error nobody catches prints its cause and your file and line, like
`uncaught <no-convert> in main (config.x:3)`, and then aborts. See
[exceptions](../docs/guide/exceptions.html).

## Your own types

`class` writes the struct and the boring methods. A value class gets `new`,
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

A protocol is a contract a type adopts on purpose.
`protocol Meters(T) { ... }` declares methods on the base type `Meters`.
`protocol Meters(Km);` adopts them for `Km`, which only has to say how to
view itself as `Meters`. The compiler writes the adapters. There are no
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

C has one flat namespace, and so does x2c. Packages stay out of each
other's way because `import` binds a package to a name you choose, and its
types and functions hang off that name:

```x2c
import "pcre2" as rx;

int main(void) {
  rx.Regexp version =
    rx.Regexp.compile("(?<major>\\d+)\\.(?<minor>\\d+)", 0);
  defer version.free();
  rx.RegexpMatch found = version.match("x2c 0.15.0");
  if (found) puts(%"major $(found[<major>]), minor $(found[<minor>])");
  return 0;
}
```

`x2c install pcre2` fetches a package from the index, and `x2c list` shows
what you have. Most packages wrap a C library you already know, such as
PCRE2, SQLite, libcurl, libuv, raylib, or torch, and the native API stays
reachable underneath. Prebuilt bundles exist for macOS and Linux. See
[packages](../docs/guide/packages.html).

## The compiler is yours

This is the part that either delights C programmers or offends them. It
is the fourth idea: x2c is its own metalanguage, and the compiler is user
space. A code literal is a `List`, so the `%(...)` that builds data also
builds patterns, errors, and syntax. Put `meta` in front of a function and
the compiler can call it: `$fib(20)` runs during translation and leaves a
constant behind. A `macro` is a typed template over syntax trees, so
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

`keyword` gives a construct a name, so `repeat (3) stmt` can become syntax
in your file. None of this is a separate macro language. It is x2c running
inside the compiler, with the runtime available. The compiler itself is
written in x2c, and every line of it is there for you to read. Start with
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
[shootout](https://github.com/gwf/x2c/blob/main/examples/shootout/README.md)
has fourteen problems written in x2c, C, and Python. The x2c versions ran
at a median of 1.04 times C's time, and the C ported to x2c ran at 0.99
times. Python took 39 times C's time. The x2c came in at about 1.5 times
Python's line count. Those are measurements of those programs on one
machine, not a ranking.

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
failures name your `.x` line, not the generated C. A file whose first line
is `#!/usr/bin/env -S x2c script` runs like a shell script and rebuilds
only when something it depends on changes. The [command
reference](../docs/reference/cli.html) has the rest, and
[scripting](../docs/guide/scripting.html) covers scripts.

## Where next

The [examples page](../examples/) puts every example in one place, and you
can run the small ones in your browser. The [book](../docs/) has the whole
language when a line needs more than a line. Keep the
[cheat sheet](../cheatsheet/) next to you while you read, then go write
something you would not have bothered to write in C.
