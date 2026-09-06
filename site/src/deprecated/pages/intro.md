---
layout: ../layouts/MarkdownLayout.astro
title: x2c in Fifteen Minutes
index: informal introduction
deck: >-
  x2c keeps C and adds compile-time contracts, source generation, dynamic
  values, structured control flow, lifetime ownership, and a native build
  driver where C becomes repetitive. Read this once and you have the shape of
  the language.
description: >-
  A fifteen-minute tour of x2c: dynamic values, collections, protocols,
  macros, iteration, matching, cleanup, the build driver, the embedded Lisp,
  and one complete program.
jump:
  - href: "#dynamic-values"
    label: values
  - href: "#lists-arrays-and-maps"
    label: collections
  - href: "#protocols"
    label: protocols
  - href: "#macros"
    label: macros
  - href: "#iteration-and-lambdas"
    label: iteration
  - href: "#match-errors-and-defer"
    label: control
  - href: "#the-lisp-runtime"
    label: lisp
  - href: "#a-complete-program"
    label: program
---

The runtime examples on this page are collected in `examples/docs-tour.x`;
`make examples` translates, compiles, runs, and checks its exact output. Every
other sample here is compiled by the documentation gate.

## Dynamic values

`Var` carries its runtime kind. Native values stay native until a dynamic
boundary needs them:

```x2c
Var answer = 41;
answer += 1;
String language = %"x2c";
printf("%s\n", %"dynamic=${answer.integer()} language=$language");
```

Use `int`, `double`, structs, and pointers normally. Reach for `Var` when one
slot, collection, or operation genuinely needs more than one type.

> From Python or JavaScript: `Var` supplies the dynamic value, but the rest of
> the program remains statically typed C unless you choose otherwise.

## Lists, Arrays, and Maps

A List may hold mixed values and can be destructured at a flat statement
boundary:

```x2c
List packet = %(build 42 fast);
Var (action, value, quality) = packet;
printf("%s/%ld/%s\n",
       action.str(), value.integer(), quality.str());
```

Arrays and Maps are mutable and grow as needed:

```x2c
Array values = %[1, 2];
values.push(3);

String language = %"x2c";
Map facts = %{name: $language};
facts[<values>] = values.len();
printf("values=%ld name=%s\n",
       facts[<values>].integer(), facts[<name>].string());
```

Use List for persistent, canonical sequence structure. Use Array for indexed
mutation and Map for keyed mutation.

> From Lisp: `%(...)` is a canonical cons List. The same Atom and nested-List
> spelling is understood by x2c's Lisp reader.

## Protocols

A protocol connects one base contract to concrete participant types. The
adoption is a declaration, not a runtime interface object:

```x2c
~
~typedef struct Reading {
~  int value;
~} *Reading;
~
~typedef struct Gauge {
~  Reading reading;
~} *Gauge;
~
protocol Reading(T) {
  int T.value(T);
}

Reading Gauge.reading(Gauge gauge) {
  return gauge.reading;
}

int Reading.value(Reading reading) {
  return reading.value;
}

protocol Reading(Gauge);
~
~int main(void) {
~  Reading reading = Scope.malloc(sizeof(struct Reading));
~  reading.value = 42;
~  Gauge gauge = Scope.malloc(sizeof(struct Gauge));
~  gauge.reading = reading;
~  return gauge.value() == 42 ? 0 : 1;
~}
```

`Gauge.reading` supplies the total view of the base type. Adoption lets the
compiler generate the forwarding `Gauge.value` member. Concrete members can
instead implement a protocol operation directly. Protocols also own
associated types, operator and indexing mappings, and boxed dispatch where
the base declares it.

> From Go or Rust: participation is explicit, but x2c generates C adapters
> rather than a runtime interface or trait object.

## Macros

Macros run after parsing and type analysis. Their hole declarations say what
each `$` name binds:

```x2c
~
macro Expression $project.minutes(Expr $value) => (
  $value * 60
)
~
~int main(void) {
~  return $project.minutes(2) == 120 ? 0 : 1;
~}
```

This macro accepts one expression and returns one expression. Other result
kinds cover statements, fields, enum members, translation-unit items, and
decorators on following expressions or source items. Reusable definitions live
in tracked `.xmacro` imports; compile-time Lisp is available when a template
needs real computation.

Use a function for runtime computation. Use a macro when the invocation makes
one repeated source shape shorter and clearer.

## Iteration and lambdas

`File` yields canonical Strings one line at a time. String operations return
values that can immediately feed collection operations:

```x2c
~File input = tmpfile();
~input.puts("alpha beta\nbeta gamma\n");
~input.rewind();
~Map counts = %{};
~
foreach(String line, input) {
  List words = line.strip(" \n").split(%" ");
  foreach(String word, words) {
    Var old;
    long count = counts.try_get(word, &old) ? old.integer() : 0;
    counts[word] = count + 1;
  }
}
printf("beta=%ld\n", counts[%"beta"].integer());
~input.close();
```

`Map.try_get` separates absence from the stored value. That matters because
raw Null is valid data while `void` is reserved for missing or exhausted
value-bearing protocols.

Expression lambdas are a compact callback form:

```x2c
List numbers = %(1 2 3 4);
List doubled = numbers.map(%!(item) => item * 2);
printf("%s\n", doubled.repr());
```

They are intentionally small: one expression and no captured local state. Use
a named function when the callback needs a larger body or explicit state.

> From JavaScript: this looks like an arrow function, but it is adapted to a
> concrete C function-pointer type at translation time.

## Match, errors, and defer

`match` describes nested List shapes and binds the values that matter:

```x2c
List packet = %(build 42 fast);
match (packet) {
  case %(build ?amount fast):
    printf("match=ready %ld\n", amount.integer());
}
```

Arms run in source order and the first match wins. `?name` binds one value;
`*name` binds a run of values as a List.

The owner that detects a failure can `raise` a structured cause. A filtered
`catch` matches it with the same List-pattern vocabulary:

```x2c
~
~static void require_positive(int value) {
~  if (value <= 0)
~    raise %(bad-arg (operation "require-positive") (value $value));
~}
~
~int main(void) {
~  int status = 0;
~  try {
~    require_positive(-1);
~  }
catch %(bad-arg * (value ?given) *): {
  printf("invalid=%ld\n", given.integer());
~    status = 1;
}
~  return status == 1 ? 0 : 1;
~}
```

Expected absence stays on the return channel: EOF, iterator exhaustion, a
missing Map key, and failed numeric parsing are not Errors. `defer` attaches
cleanup to the current block and runs it on ordinary exit, `return`, or Error
transfer:

```x2c
~
static String first_line(String path) {
  File input = File.open(path, %"r");
  defer input.close();
  return input.readline();
}
```

This keeps resource release next to acquisition while Error owns non-local
failure transfer.

## Scope

You do not free every String or List cell. Put a lifetime boundary around the
work:

```x2c
Scope.retain();
String message = %"temporary result";
List values = %($message 1 2 3);
printf("%s\n", values.repr());
Scope.release();
```

Canonical Strings and Lists participate in their own pool lifetime; mutable
storage and wide boxes use Scope-managed allocation. Files and other external
resources still close explicitly or through `defer`.

## The driver

The command names state who owns the next stage:

```sh
x2c translate --out-dir generated source.x
x2c build --output build/app source.x
x2c run source.x -- argument
```

`translate` stops at generated C for an external build. `build` creates a
native executable or static library, and `run` builds a temporary executable
and launches it. Direct operands and `x2c.toml` project targets lower to the
same build request.

## The Lisp runtime

The runtime includes a reader, evaluator, closures, macros, inferred native
function binding, host-side value application, and a command-line shell:

```x2c
static int clamp(int value, int low, int high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

~int main(void) {
Lisp lisp = Lisp.new();
defer lisp.destroy();
$lisp.bind(lisp, "clamp", clamp);
int allowed = lisp.eval(%(clamp 14 0 8));
~  return allowed == 8 ? 0 : 1;
~}
```

`Lisp.new()` loads the small standard environment from `etc/init.xlisp`.
Use `Lisp.new_bare()` only when you intend to build the environment yourself.
`$lisp.bind` reads the direct function's type and builds the checked `Func`
binding. Runtime `%(...)` forms can contain live x2c values through `$`
interpolation. This is separate from compile-time `$(...)` Lisp, which runs
while translating source.

The complete
[`inline-lisp.x`](https://github.com/gwf/x2c/blob/main/examples/inline-lisp.x)
example loads a policy `.xlisp` file, installs a group of decorated C-style
functions, and destructures the returned List into `String` and `int`
variables.

Run the complete shell and deterministic self-test with:

```sh
make examples
./examples/build/lisp/lisp
```

## A complete program

Counting words in a file combines C command-line handling with x2c files,
Strings, Maps, iteration, dynamic values, and scoped lifetime. The checked
source is `examples/docs-word-count.x`:

```x2c
int main(int argc, char **argv) {
  if (argc != 2) {
    Stderr.printf("usage: %s FILE\n", argv[0]);
    return 2;
  }

  Scope.retain();
  defer Scope.release();
  Map counts = %{};
  int lines = 0;
  int words = 0;

  try {
    File input = File.open(argv[1], "r");
    defer input.close();
    foreach(String line, input) {
      lines++;
      foreach(String word, line.lower().words()) {
        Var old;
        long count = counts.try_get(word, &old) ? old.integer() : 0;
        counts[word] = count + 1;
        words++;
      }
    }
  }
  catch %(not-found *): {
    Stderr.printf("cannot open %s\n", argv[1]);
    return 2;
  }
  catch %(io-fail *): {
    Stderr.printf("cannot read %s\n", argv[1]);
    return 2;
  }

  Var beta = 0;
  counts.try_get(%"beta", &beta);
  printf("lines=%d words=%d beta=%ld\n",
         lines, words, beta.integer());
  return 0;
}
```

The C boundary owns `argc`, `argv`, and the process exit status. `File.open`
owns converting a path and mode into a stream, and it reports failure by
raising rather than in its result: a missing path raises `<not-found>` and any
other open failure raises `<io-fail>`. Neither returns to the call, so the
`catch` arms are where those outcomes become an exit status.

The outer `for` asks File for an iterator. Each successful step is a String
line; EOF ends the loop without becoming data, while a host read failure
raises `<io-fail>` instead of returning. The inner loop uses the lazy `words`
cursor, which coalesces whitespace and yields no empty fields. It does not
allocate an intermediate List or allocate again when an already-interned word
is seen.

`Map.try_get` owns presence. It writes `old` only when the key exists, so a
missing word starts at zero without confusing absence with a stored Null.
Bracket assignment owns the mutation.

`Scope.retain` and its deferred `Scope.release` bracket the dynamic working
set. The cursor descriptor is scope-owned, and each distinct canonical word
remains in the active String pool. For a one-shot scan whose distinct words
should not remain resident, use a nested String pool and promote only the Map
keys that survive. The File is an external resource, so `defer input.close()`
releases it on every exit from the `try` block, including a transfer to a
`catch` arm.

Run the checked version:

```sh
make examples
./examples/build/docs-word-count/docs-word-count \
  examples/data/docs-words.txt
```

```text
lines=2 words=4 beta=2
```

Useful next changes are all local: use an Array to preserve first-seen word
order; sort an Array of `(word count)` Lists; accept more paths through
`argv`; use `File.write_all` or formatted File output for a report; or raise a
structured Error when an application layer wants failure transfer instead of
an exit status.

You now have the important shape of x2c: C underneath, explicit compile-time
extension, opt-in dynamic values, structured control and lifetime, and a
driver that can stop at C or finish the native build. The
[language guide](../docs/guide/from-c.html) explains how to choose among these
facilities, the [language reference](../docs/reference/language.html) states
the exact rules, and the [standard library](../docs/library/overview.html)
routes tasks to the generated API.
