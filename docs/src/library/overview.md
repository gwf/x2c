# Standard Library by Task

Every `.x` translation unit receives the x2c runtime prelude. Each section
below names the type to use for one task. The generated
[module reference](modules/index.md) lists every signature and its behavior,
grouped by [API tier](../guide/idioms.md#prefer-the-primary-api-tier).

The implicit prelude is the standard library. Optional x2c system modules are
shipped, built, and tested with x2c, and need an explicit include. Runtime
internals are implementation details. Third-party libraries are under
`packages/` and use `import`.

Number parsing, number formatting, and case mapping call C's locale
functions and are specified for the default `C` locale; a program that
calls `setlocale` changes what they accept and produce.

## Hold a value whose type varies

Use [Var](modules/var.md) when you do not know the type of a value until the
program runs. Use the C type everywhere else.

```x2c
Var value = 42;
value = "forty-two";

if (value is String)
  printf("%s\n", value);
```

The [Var reference](modules/var.md) covers dynamic arithmetic, truthiness,
and checked conversion. `void` means missing or exhausted,
and collections and iterators never carry it as a payload.

## Choose a collection

| Need | Type | Important contract |
| --- | --- | --- |
| persistent heterogeneous sequence | [List](modules/list.md) | canonical and immutable |
| growing indexed sequence | [Array](modules/array.md) | mutable object identity |
| growing keyed lookup | [Map](modules/map.md) | mutable object identity |
| canonical byte text | [String](modules/string.md) | interned, NUL-terminated |
| streaming traversal | [Iter](modules/iter.md) | caller-owned iterator storage |

`List` and `String` values are canonical. `Array` and `Map` are distinct
allocated objects even when empty.

## Build and transform text

[String](modules/string.md) does interpolation, search, split, replace,
partition, case conversion, padding, escaping, slicing, joining, and checked
numeric parsing. Its operations work on bytes; they do not decode Unicode.
For code points, see [Encode text and parse URLs](#encode-text-and-parse-urls).

Use [Buffer](modules/buffer.md) for incremental text:

```x2c
Buffer output = auto Buffer.new(0);
output.write("count=");
output.printf("%d", 4);
String text = output;
printf("%s\n", text);
```

Use [Symbol](modules/symbol.md) for compact immediate tags and
[Atom](modules/atom.md) for exact names that may be longer.

## Read or write a file

[File](modules/file.md) wraps C streams. Iterate a text file by line:

```x2c
~File input = tmpfile();
~input.puts("first\nsecond\n");
~input.rewind();
foreach(String line in input)
  printf("%s", line);
~input.close();
```

Use `File.readline_into` and `File.read_into` for raw bytes with separate
data, EOF, and error status. Use `File.write_all` and `File.copy_to` when a
partial write must be finished or reported.

## Transform a sequence

Every collection supports iteration. Use `foreach` to walk one:

```x2c
List values = %(1 2 3);
foreach(int value in values)
  printf("%d\n", value);
```

Use [Iter](modules/iter.md) to process values as they are requested. Use a
collection's `map`, `filter`, and fold operations to compute the result
immediately. `Iter.try_next` separates a value from exhaustion and never yields
`void` as data.

## Match structured Lists

The language `match` statement and [Match](modules/match.md) use the same
`List` patterns:

```x2c
List event = %(ready 42);
match (event) {
  case %(ready ?value):
    printf("%ld\n", value);
}
```

Use the `match` statement for control flow and `List.try_match` or the other
runtime matching functions when the patterns are themselves data.

## Own allocation lifetime

[Scope](modules/scope.md) groups runtime allocations:

```x2c
auto {
  String text = "temporary";
  Array values = [text, 1, 2, 3];
  printf("%s\n", values.repr());
}
```

Use [Block](modules/block.md) for fixed-width growable storage and `Buffer` for
text construction. External resources such as `File`s still close explicitly or
through `defer`.

Each `Scope.release` must match a `Scope.retain` on the same active slot. See
[scopes and lifetime](../guide/memory.md).

## Bound temporary work

[Context](modules/context.md) combines a `Scope` lifetime with independent
`Error`, cleanup, and `Match` state. An isolated `Context` also gives temporary
`String` and `List` values private pool branches:

```x2c
Context work = Context.open_isolated_named("request");
List temporary = %(answer 42);
List result = work.export(temporary);
work.close();

printf("%s\n", result.repr());
```

Closing reclaims everything that was not exported. Close `Context`s in
last-opened, first-closed order. See
[contexts and threads](../guide/contexts-and-threads.md).

## Run work on native threads

[Thread](modules/thread.md) runs a fixed-signature callback in an isolated
`Context`. It copies the input structure, but pointers inside that structure
still point into shared process memory. A worker can read parent `String`s and
`List`s directly. Use [Mutex](modules/mutex.md) when a shared value may be
written:

```x2c
typedef struct CounterWork {
  Mutex mutex;
  int *counter;
  String label;
} CounterWork;

static Var increment(const void *input, size_t input_size) {
  if (input_size != sizeof(CounterWork)) raise %(bad-arg);
  const CounterWork *work = input;
  $lock(work.mutex) (*work.counter)++;
  return work.label;
}

int main(void) {
  int counter = 0;
  Mutex mutex = Mutex.new();
  CounterWork work = { mutex, &counter, "parent label" };
  Thread first = Thread.start_raw(increment, &work, sizeof(work));
  Thread second = Thread.start_raw(increment, &work, sizeof(work));
  String a = first.join();
  String b = second.join();
  printf("%s, %s: %d\n", a, b, counter);
  first.free();
  second.free();
  mutex.free();
  return 0;
}
```

Every started `Thread` needs one successful `Thread.join`, then
`Thread.free`. [Contexts and threads](../guide/contexts-and-threads.md#pass-shared-values-to-a-worker)
gives the sharing and result rules.

## Handle absence and failure

These operations report absence separately from data:

- `Map.try_get` and `Map.try_del` report whether the key was present,
  separately from its value.
- `Iter.try_next` separates a value from exhaustion.
- `String.try_long` and `String.try_double` separate zero from parse failure.
- raw `File` readers separate data, EOF, and error.

An operation that fails raises its cause through `Error`, and a filtered
`catch` or the cause's policy handles it. Absence, exhaustion, and parse
results come back as return values.

## Use Error transfer and cleanup

Language `raise`, `try`, filtered `catch`, `finally`, and `defer` are backed by
`Error` and the cleanup-frame runtime. Application code uses those statements
and leaves the runtime frame functions alone. See [Errors and
Cleanup](../guide/exceptions.md).

## Bind native functions

[Func](modules/func.md) binds an already-linked native function with a checked
signature. Construction, binding, conversion, and application failures raise
their cause through `Error`; none of those causes return to the call. A fixed
nonvariadic function or function-pointer value with a supported signature
converts implicitly where a `Func` is expected. Direct conversions reuse a
file-static binding that lives for the program, so an operation that takes
ownership of a `Func`, such as `Lisp.bind`, leaves it in place. Pointer
conversions snapshot the pointer in a binding held by the current `Scope`.
Call a C function directly when its name is known at compile time.

## Log structured events

[Logger](modules/logger.md) does level filtering and writes to ordered stderr,
file, memory, and custom sinks. A category labels an event; it never suppresses
one. The global `log_*` functions are the simplest interface; use a `Logger`
object to configure logging and manage its lifetime.

## Embed Lisp

[Lisp](modules/lisp.md) provides a reader, evaluator, lexical closures, macros,
global bindings, native `Func` integration, host-side value application, and
file/string evaluation:

```x2c
static String greet(String name) {
  return %"hello $name";
}

~int main(void) {
Lisp lisp = Lisp.new();
defer lisp.destroy();
$lisp.bind(lisp, "greet", greet);
String result = lisp.eval(%(greet "Ada"));
~  return result == "hello Ada" ? 0 : 1;
~}
```

`Lisp.new()` creates an isolated session and loads `etc/init.xlisp`. That file
supplies `defun`, short-circuit control, higher-order `List` operations,
numeric comparisons, basic `String` operations, and the pattern matching
described in [the language reference][lisp]. `Lisp.kernel()` creates the
evaluator primitives alone, for hosts that build their own environment.
The same standard environment includes the core `List`, `Array`, `Map`,
`String`, `Iter`, `Var`, and `Symbol` operations, plus `read-file`,
`write-file`, `sort`, `fib`, and `subst`. A host that calls `Lisp.new()`
needs no additional standard files.

[lisp]: ../reference/language.md#runtime-lisp

Use `$lisp.binding(group, "name")` on several direct functions and
`$lisp.install(lisp, group)` when a unit has a reusable set. Functions must
appear before the install call, and names in one group must be unique.
Installing the same group into two sessions creates two sets of `Func` values,
and each session releases its own in `Lisp.destroy()`.

A group compiles into the unit that declares it. A package can therefore
publish its bindings behind one public installer that a consumer calls after
importing it. See [Wrapping a C Library](../guide/wrapping-c-libraries.md).

`$lisp.bind` and grouped bindings accept the parameter and result types
`Func` supports, including untagged pointers and structs passed as `<p48>`
addresses. Native functions are trusted host code. A package-specific opaque
object needs its own `Var` adoption.

Load a Lisp program with `Lisp.eval_file`, then evaluate runtime `List` forms
with `Lisp.eval`. `$` inside `%(...)` inserts live x2c values. Within a `List`
literal, `'`, `` ` ``, `,`, and `,@` write `quote`, `quasiquote`, `unquote`,
and `unquote-splicing` just as they do in Lisp source. A flat `List` result
destructures through the same typed conversions as any other value:

```x2c
~int main(void) {
~Lisp lisp = Lisp.new();
~defer lisp.destroy();
~String role = "editor";
List outcome = lisp.eval(%(decide (quote ((role $role)))));
String decision;
int limit;
(decision, limit) = outcome;
~return 0;
~}
```

## Look up an exact operation

The [module reference](modules/index.md) is generated from runtime source and
compiler-verified signatures.

## Measure and format time

Explicitly include `time.x`. A `Time` is an instant and a `Duration` a
span, both in nanoseconds. `Time.now` reads the wall clock,
`Time.monotonic` measures elapsed time, and `Time.sleep` waits.
`Time.parse` and `Time.str` read and write RFC 3339 timestamps in UTC, and
`Time.format` applies `strftime` conversions:

```x2c
~#include "time.x"
~int main(void) {
Time start = Time.parse("2026-10-28T14:05:09Z");
Time due = start.plus(Duration.seconds(90));
printf("%s %s\n", due.str(), due.since(start).str());
~  return 0;
~}
```

```text
2026-10-28T14:06:39Z 1m30s
```

`Time.local` and `Time.format_local` use the zone `TZ` selects. See
[Time, Random Values, and Encodings](../guide/time-random-encodings.md).

## Generate random values

Explicitly include `random.x`. `Random.new(seed)` makes a repeatable
xoshiro256** generator with `next`, `below`, `double`, `shuffle`, and
`choice`. `Random.secure_fill` reads the operating system's cryptographic
generator, and `Uuid.v4` returns a random UUID.

## Encode text and parse URLs

Explicitly include `encoding.x` to iterate, count, and write the UTF-8 code
points of a `String`, and to encode and decode base64, hexadecimal, and
percent-encoded text. Explicitly include `url.x` to split a URL into its
components with `Url.parse` and to read and write query strings:

```x2c
~#include "url.x"
~int main(void) {
Url url = Url.parse("https://example.com/search?q=two+words");
Map query = Url.parse_query(url.query);
printf("%s %s %s\n", url.host, query["q"], "x2c".base64_encode());
~  return 0;
~}
```

```text
example.com two words eDJj
```

## Open a socket

Explicitly include `net.x` for blocking TCP. `Listener.bind` and
`Listener.accept` create connections; `Socket.connect` opens a client.
Read and write through the Socket's `input` and `output` Files. Both Socket
and Listener adopt `Cleanup`. See [Sockets and HTTP](../guide/networking.md)
for timeouts, half-close, listener stopping, and the process-wide SIGPIPE
setting.

## Serve HTTP

Explicitly include `http.x`. Register handlers with `Router`, construct an
`HttpServer`, and call `serve` or `start`. Requests expose path captures,
query fields, headers, and JSON; responses buffer text, JSON, or bytes.
`Http.fail` selects a failure status before anything is sent. The
[networking chapter](../guide/networking.md) explains limits, worker pools,
request storage, static files, and shutdown.
