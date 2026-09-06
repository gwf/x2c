# Standard Library by Task

Every `.x` translation unit receives the x2c runtime prelude. This chapter
shows which library functions to use for common tasks. The generated [module
reference](modules/index.md) lists their signatures and behavior.

The reference has four tiers:

- **Primary** - what most programs use.
- **Advanced** - storage, ABI, embedding, representation, and diagnostics.
- **Compatibility** - older interfaces, with their preferred replacements.
- **Internal** - functions used within the runtime, documented for source
  readers.

The implicit prelude is the standard library. Optional x2c system modules are
shipped, built, and tested with x2c, and need an explicit include. Runtime
internals are implementation details. Third-party libraries are under
`packages/` and use `import`.

## Hold a value whose type varies

Use [Var](modules/var.md) when you do not know the type of a value until the
program runs. Use the C type everywhere else.

```x2c
Var value = 42;
value = "forty-two";

if (value is String)
  printf("%s\n", value.string());
```

Dynamic arithmetic and truthiness are in
[Var operations](modules/varops.md). Checked conversion is in
[Var conversion](modules/varconvert.md). `void` means missing or exhausted,
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
numeric parsing. Its operations work on bytes, not Unicode characters.

Use [Buffer](modules/buffer.md) for incremental text:

```x2c
Buffer output = Buffer.new(0);
output.write("count=");
output.printf("%d", 4);
String text = output.str();
output.free();
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
foreach(String line, input)
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
foreach(int value, values)
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
    printf("%ld\n", value.integer());
}
```

Use the `match` statement for control flow and `List.try_match` or the other
runtime matching functions when the patterns are themselves data.

## Own allocation lifetime

[Scope](modules/scope.md) groups runtime allocations:

```x2c
Scope.retain();
String text = "temporary";
Array values = %[$text, 1, 2, 3];
printf("%s\n", values.repr());
Scope.release();
```

Use [Block](modules/block.md) for fixed-width growable storage and `Buffer` for
text construction. External resources such as `File`s still close explicitly or
through `defer`.

Each `Scope.release` must match a `Scope.retain` on the same active slot. An
extra release aborts. It does not consume the surrounding process root.

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

Closing reclaims everything that was not exported. Export walks supported
`List`s, `Array`s, `Map`s, wide values, `Block`s, `Bytes`, and `Buffer`s,
moving mutable storage when it can and canonicalizing `String`s and `List`s in
the parent. A custom `Var` object can register an exporter for its own
references and allocations.

The optional name appears in `Scope` leak diagnostics. It does not change
`Context` behavior and is not a runtime identifier. Close `Context`s in
last-opened, first-closed order, usually with `defer work.close()` when no
value is needed after the close.

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
  work.mutex.lock();
  (*work.counter)++;
  work.mutex.unlock();
  return work.label.var();
}

int main(void) {
  int counter = 0;
  Mutex mutex = Mutex.new();
  CounterWork work = { mutex, &counter, "parent label" };
  Thread first = Thread.start(increment, &work, sizeof(work));
  Thread second = Thread.start(increment, &work, sizeof(work));
  String a = first.join().string();
  String b = second.join().string();
  printf("%s, %s: %d\n", a, b, counter);
  first.free();
  second.free();
  mutex.free();
  return 0;
}
```

Every successful start must be joined exactly once, and the handle can be freed
only after join. Any object a worker accesses through a borrowed pointer must
stay alive until the worker is joined. A worker result is exported only after the
worker stops. `Thread` has no detach or cancellation.

## Handle absence and failure

Use the operation that keeps the distinction you need:

- `Map.try_get` and `Map.try_del` report whether the key was present,
  separately from its value.
- `Iter.try_next` separates a value from exhaustion.
- `String.try_long` and `String.try_double` separate zero from parse failure.
- raw `File` readers separate data, EOF, and error.

An operation that fails raises its cause through `Error`. Filtered catches and
the embedding application's error policy decide what happens next. Absence,
exhaustion, and parse results come back as return values.

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
file-static binding; pointer conversions snapshot the pointer in a binding held
by the current `Scope`. Call C functions directly when the compiler already
knows which function you mean.

## Log structured events

[Logger](modules/logger.md) does level filtering and writes to ordered stderr,
file, memory, and custom sinks. A category names an event and never suppresses
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
described in [the language reference][lisp]. `Lisp.new_bare()` creates the
evaluator primitives alone, for hosts that build their own environment.
`etc/lisp-extras.xlisp` and `etc/lisp-io.xlisp` stay optional and must be
loaded by name.

[lisp]: ../reference/language.md#compile-time-lisp-and-imports

Use `$lisp.binding(group, "name")` on several direct functions and
`$lisp.install(lisp, group)` when a unit has a reusable set. Functions must
appear before the install call, and names in one group must be unique.
Installing the same group into two sessions creates two sets of `Func` values,
and each session releases its own in `Lisp.destroy()`.

A group compiles into the unit that declares it. A package can therefore
publish its bindings behind one public installer that a consumer calls after
importing it. See [Wrapping a C Library](../guide/wrapping-c-libraries.md).

`$lisp.bind` and grouped bindings accept the scalar and object types `Func`
supports. Native functions are trusted host code. Pointers, structs,
callbacks, and package-specific opaque objects cannot be passed this way.

Load a Lisp program with `Lisp.eval_file`, then evaluate runtime `List` forms
with `Lisp.eval`. `$` inside `%(...)` inserts live x2c values; it is unrelated
to compile-time `$(...)` Lisp. Within a `List` literal, `'`, `` ` ``, `,`, and
`,@` write `quote`, `quasiquote`, `unquote`, and `unquote-splicing` just as
they do in Lisp source. A flat `List` result destructures through the same
typed conversions as any other value:

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
compiler-verified signatures. Begin with the primary tier. Use an advanced or
compatibility entry when its documented behavior is what you need.
