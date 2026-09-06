# Errors and Cleanup

C gives you `return`, `goto`, and `longjmp`. x2c adds structured failure
recording and non-local transfer through `raise`, `try`, and filtered `catch`.
`finally` and `defer` run cleanup even when a block exits early.

The exhaustive grammar is in
[the language reference](../reference/language.md).

## One error protocol

The code that first detects a failure raises one structured `Error`:

<!-- ignore: standalone raise-site illustration; requested is supplied by its owner -->
```x2c,ignore
raise %(size-limit (operation "Block.reserve") (bytes $requested));
```

The first item is a compact `Symbol` naming the cause. The remaining items are
`(key value)` detail pairs. `Error` also records the source location. Codes
classify causes that a handler might reasonably branch on; they do not name
the reporting mechanism, recovery action, or module that detected them.

Use the most specific shared cause. For example, `<bad-arity>` identifies an
argument count, `<bad-types>` identifies unsupported dynamic operand types,
`<not-found>` identifies a missing external resource, and `<invariant>`
identifies an impossible internal state. Detail keys are open-ended, so a
raiser may add context without changing the code's identity. Detail values are
value-like: `Null`/`nil`, numeric and enum values, `Symbol`s, `Atom`s,
`String`s, and `List`s recursively containing only those values. Pointers,
`void`, `Array`s, `Map`s, resources, custom objects, and other identity-bearing
values are rejected. The compiler diagnoses invalid statically known values; a
bad value hidden in a dynamic `Var` terminates with `<bad-types>` without
re-entering error handling.

Choose codes in this order when several seem plausible: callable shape,
dynamic operation, resource or external operation, API contract, then
`<invariant>` for an impossible internal state. The shared codes are:

| Code | Cause | Default |
| --- | --- | --- |
| `<alloc-fail>` | allocation failed | `<abort>` |
| `<size-limit>` | a size, length, or capacity is unrepresentable | `<abort>` |
| `<invariant>` | an impossible internal state was reached | `<abort>` |
| `<bad-state>` | a valid object is in the wrong lifecycle state | `<abort>` |
| `<init-fail>` | process-owner initialization failed | `<abort>` |
| `<bad-arg>` | an API precondition failed with no better code | `<abort>` |
| `<bad-enc>` | a `Var` encoding is invalid | `<abort>` |
| `<void-op>` | `void` was used as a dynamic value | `<abort>` |
| `<bad-types>` | operand types do not support the operation | `<abort>` |
| `<bad-target>` | a requested conversion target is invalid | `<abort>` |
| `<no-convert>` | no requested conversion exists | `<abort>` |
| `<conv-range>` | conversion exists but the value is out of range | `<abort>` |
| `<bad-op>` | an operator is unsupported | `<abort>` |
| `<div-zero>` | integer division or remainder by zero | `<abort>` |
| `<bad-shift>` | a shift count is invalid | `<abort>` |
| `<no-member>` | a dynamic value has no such member | `<abort>` |
| `<bad-sig>` | a native or Lisp callable signature is invalid | `<abort>` |
| `<bad-arity>` | a callable received the wrong argument count | `<abort>` |
| `<no-symbol>` | a native symbol cannot be resolved | `<abort>` |
| `<bad-result>` | a native result cannot be represented | `<abort>` |
| `<not-call>` | a value cannot be called | `<abort>` |
| `<unbound>` | a program name has no binding | `<abort>` |
| `<malformed>` | external syntax or serialized input is invalid | `<abort>` |
| `<incomplete>` | external input needs more data | `<abort>` |
| `<format>` | formatting failed without output | `<abort>` |
| `<not-found>` | an external resource does not exist | `<abort>` |
| `<io-fail>` | another external I/O operation failed | `<abort>` |
| `<join-fail>` | a worker transferred captured errors at join | `<abort>` |

Every spelling shown is the compact `Symbol` identity. Unknown codes default to
`<abort>`, and no shared code defaults to `<log>`.

Every cause whose default is `<abort>` above is non-returning. Such a cause
may transfer to a matching filtered `catch`, after running intervening
cleanup, but it can never resume after the raising call. Constructors whose
preconditions are satisfied therefore return initialized objects, and a
failed open, read, write, or format does not produce a null, `void`, or
unchanged-value fallback.

Return values still carry ordinary results. Clean EOF, a missing `Map` key,
iterator exhaustion, and numeric text that does not parse are not `Error`s.
APIs such as `File.readline_into`, `Map.try_get`, `Iter.try_next`, and
`String.try_long` keep those expected outcomes separate from their value
output.

## Catching by cause

`try` requires a following filtered `catch`, `finally`, or both. Adjacent
`catch` arms select the newest `Error` by matching `%(CODE @DETAIL)`:

<!-- ignore: illustrative `Block` and reporting callbacks are omitted -->
```x2c,ignore
try {
  block.reserve(requested);
}
catch %(size-limit * (bytes ?count) *): {
  printf("could not reserve %ld bytes\n", count.integer());
}
catch %(bad-arg *detail):
  report_bad_argument(detail);
catch:
  report_unknown_error();
```

The pattern language and binder rules are the same as `match`. A `?name`
binder declares a `Var`, a `*name` binder declares a `List`, and arms run in
source order. `catch:` is an optional default arm and must be last. Filters
are evaluated once when the `try` is entered.

When no arm matches, the `Error` continues outward. Selecting an arm consumes
the errors accumulated since that `catch` was registered. Older errors remain
available to the enclosing handlers.

The selected `catch` is removed before its body runs. A handler can therefore
translate a lower-level cause without catching its replacement:

<!-- ignore: illustrative parser and source bindings are omitted -->
```x2c,ignore
try parse_config(source);
catch %(malformed *cause):
  raise %(bad-state (operation "load-config") (cause $cause));
```

The matched details are borrowed from the selected `Error` and remain valid
through that `catch` arm. If they must survive the arm, copy them first with
`Error.snapshot`. If translation is unnecessary, omit an arm and let the
original cause continue outward.

## Handlers and policy

A filtered `catch` transfers control out of the raising call. Embedders may
also install observing handlers with `Error.push`. An observing handler runs
inside the raising call, sees the errors accumulated since its registration,
and returns:

- `<handled>` to consume those errors and stop;
- `<declined>` to leave the errors accumulated and continue outward;
- `<fatal>` to terminate without allocating.

`<unwind>` is reserved for compiler-generated filtered catches.

An observing handler cannot consume a non-returning cause with `<handled>`.
If it tries, `Error` terminates the process. Use a filtered `catch` to recover
outside the failed call.

The handler borrows its `Error`s for the duration of the callback. `Error.pop`
closes the handler and reclaims everything accumulated since its registration,
including declined or collected `Error`s. Use
`Error.snapshot(value)` to retain a value beyond a callback; it copies into the
caller's ordinary `Scope` and canonical `List` and `String` pools.
`Error.since(mark)` also returns a snapshot in the caller's scope and pools.

If every handler declines, the code's policy decides what happens:

| Policy | Result |
| --- | --- |
| `<abort>` | render if possible, then terminate without further allocation |
| `<log>` | render once, consume the newest `Error`, and continue |
| `<collect>` | retain the `Error` without rendering and continue |
| `<ignore>` | consume the newest `Error` without rendering and continue |

Every shared cause defaults to `<abort>` and cannot be reconfigured. A process
may set policy for unknown and user-defined codes only. The code that raises
chooses the cause; the embedding caller chooses the policy.

`Error.policy_set` accepts only the four dispositions in the table. Passing
another disposition raises `<bad-arg>` and leaves the previous policy
unchanged. It also rejects `<log>`, `<collect>`, or `<ignore>` for every
non-returning cause, leaving those policies at `<abort>`. Unknown `Error` codes
remain legal and default to `<abort>`.

The default `Logger` registers an observing `Error` handler. It renders
policy-selected `<abort>` and `<log>` entries as structured log events, then
declines. `Error` then transfers control or consumes the errors as required.

## `finally` and `defer`

Both forms run cleanup on every exit path. They differ in what they attach to.

`finally` attaches to one `try` and runs after its body or selected handler,
on normal completion, on a propagating `Error`, and on `return`, `break`, or
`continue` out of the body:

```x2c
static String first_line(String path) {
  File input = File.open(path, "r");
  String line = NULL;
  try {
    line = input.readline();
  }
  finally {
    input.close();
  }
  return line;
}
```

The `defer` statement attaches to the enclosing block. Multiple `defer`
statements in a block run last-in, first-out:

```x2c
static String first_line(String path) {
  File input = File.open(path, "r");
  defer input.close();
  String line = input.readline();
  return line;
}
```

Prefer `defer` when a block owns a resource but has no handler. It keeps the
release next to the acquisition. Use `finally` when cleanup belongs to an
existing `try` statement. Use either for cleanup, not recovery.

Both forms hook into the `Error` transfer stack. If a callee raises, every
intervening cleanup frame runs before control reaches the selected `catch`.

### Return expressions run before cleanup

A `return` expression is evaluated and saved before cleanup runs. Cleanup then
executes, and the saved value is returned:

```x2c
static String first_line(String path) {
  File input = File.open(path, "r");
  defer input.close();
  return input.readline();
}
```

Here `readline` runs while the `File` is open, then the `File` closes, then the
saved `String` is returned. Cleanup cannot change which value the return
expression already produced.

`break` and `continue` run cleanup only up to their target loop or `switch`.
Cleanup registered outside that boundary remains active until a later normal
exit, `return`, or `Error` transfer reaches it.

`goto` follows the same cleanup ancestry rule. A jump within the same cleanup
region runs nothing. An outward jump runs every cleanup region it exits. A
jump into a protected region, or sideways into a sibling protected region,
is a compile-time error because that region's cleanup was never registered on
the source path.

## Cleanup and scopes

`Error` transfer does not release a `Scope` automatically. Pair a retained
scope with `defer` whenever a raising call can cross the release:

```x2c
static void render(String text, int width) {
  Scope.retain();
  defer Scope.release();
  char *line = Scope.malloc(width + 1);
  if (!text) {
    raise %(bad-arg (operation "render"));
    return;
  }
  line[0] = 0;
}
```

The same rule applies to pushed scope slots, `File`s, and every other resource
with paired teardown. See [Scopes and Lifetime](memory.md) for ownership
details.

## Calling fallible APIs

Distinguish an API's return value from the `Error`s it raises:

- If an operation raises, either provide a matching `catch` or let the `Error`
  continue outward. A handled resumable failure returns the documented
  sentinel; a non-returning cause transfers and never returns to that call.
- If an operation reports expected absence or exhaustion, inspect that result;
  a `try` does not convert it into an `Error`.
- Keep these outcomes distinct when adding a fallback.

For example, raw `File` readers separate data from clean EOF in their result,
while a host read failure raises `<io-fail>` and transfers:

```x2c
Block line = Block.new(1);
File input = File.open("/etc/hosts", "r");
defer input.close();
try {
  if (input.readline_into(line) == FILE_READ_EOF)
    printf("empty file\n");
}
catch %(io-fail *):
  printf("read failed\n");
```

The generated API reference states each callable's result, `Error`, and
ownership rules.

## Process shutdown

Shutdown hooks run in reverse registration order. `Error` initializes before
`Logger` installs its hook, so later subsystems may still raise during
shutdown. `Logger` then reports any collected root errors once and closes its
handler. Finally, `Error` destroys its empty handler chain, stack, policy,
pools, and `Scope`. A `raise` after that point terminates without allocating.
The raw `Scope` leak report runs after all shutdown hooks.
