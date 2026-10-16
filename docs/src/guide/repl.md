# Experimental REPL

`x2c repl` is a shipped external command that evaluates a supported subset
of x2c in a persistent session.
The command compiles prompt function definitions to native code. Top-level
initializers, statements, and expressions lower to ordinary Lisp and run in
the session's evaluator. Compiler macros use native meta compilation and
helper execution.

```sh
x2c repl
x2c repl --help
x2c repl --dump --stats
```

No source file or checkout is needed when using an installed development
build. The command reads standard input and accepts no file operands. It also
runs directly as `x2c-repl` from the installation's `libexec/x2c` directory.

## Try a session

Enter these submissions in order:

```text
x2c> int total = 10;
ok
x2c> int plus(int x) { return total + x; }
defined plus
x2c> plus(3);
=> 13
x2c> total = 20;
ok
x2c> plus(3);
=> 23
```

The function calls display `=> 13` and `=> 23`: later calls read the current
value of `total`. Definitions display `defined NAME`; initializations and
statements display `ok`. A final expression displays its value using
`Var.repr`, so character and unsigned values retain their printed tags.

A function is compiled once, when its complete definition is submitted.
Compilation needs the matching x2c compiler and host C toolchain. Later calls
use the compiled code. Prompt variables have shared native storage: both
compiled functions and interpreted input read and write the same objects.
Assignment preserves each variable's address, including pointers to record
fields. `&total` therefore refers to the same object from either path.

Functions can call earlier functions and recurse directly. A saved `Func`
keeps the same bindings, so changes to shared variables remain visible:

```x2c
Func saved = plus;
total = 30;
saved(3);  // 33
```

Submit one declaration or function at a time. Executable input may contain
several statements. Semicolons are required. Incomplete input continues at
the `... ` prompt until it forms a complete submission. Put a multiline
`if`/`else` in a block when necessary: a complete `if` can execute before the
next line supplies an `else`.

Interactive terminals support the arrow keys, Home, End, Backspace, Delete,
and up/down history recall. History holds the last 100 nonempty commands and
completed source submissions for the current process; adjacent duplicates are
stored once, and history is not written to disk. A rejected or failed
submission remains available for correction.

Tab completes names from the compiler's live session namespace. The parser's
current grammar role filters that namespace: type positions offer types and
type-producing macros, expression positions offer values and callable forms,
and statement, block, and submission starts offer their legal union plus
contextual keywords. Narrow continuation contexts offer `else`, `catch`, or
`finally` where each is legal. Fields and evaluator-callable methods remain
available on a typed receiver. At a blank primary prompt completion also
offers colon commands, grouped with keywords, session names, types, and other
callables. Unsupported REPL declarations and imports are not suggested.

A colon-prefixed line completes commands even at a continuation prompt;
`:ast` and `:lowered` then complete published function names, and `:stats`
completes `verbose`. A sole match replaces the current name; otherwise Tab
inserts the common prefix, and another Tab lists compact, grouped choices.
Completion parses only through the cursor and rolls back its semantic work,
so it can use locals from pending multiline input without publishing them.
APIs become candidates when their ordinary declarations and compile-time
bindings become visible; the REPL keeps no separate API or grammar model.

Long input wraps across terminal rows. Bracketed paste keeps embedded newlines
inside one editable entry, so a pasted multiline submission can be accepted
with one Enter. Recalled multiline submissions are also one entry. The editor
folds these entries for display and moves over the folded range as a unit; it
does not provide arbitrary cursor movement among every line of a whole
submission. Typing Enter still submits the current edited entry, and an
incomplete submission continues at a fresh `... ` prompt.

## Inspect and control the session

| Command | Meaning |
| --- | --- |
| `:help` | Show session commands. |
| `:stats [verbose]` | Show concise or detailed runtime statistics. |
| `:symbols [PREFIX]` | List successfully defined names and kinds, optionally matching a name prefix. |
| `:load "file.x"` | Compile and load public functions and globals; replace an earlier load of the same file. |
| `:info NAME` | Show a session function's argument and return types, source, and execution mode. |
| `:ast plus` | Show `plus`'s typed x2c AST. |
| `:lowered plus` | Report that `plus` is compiled and has no Lisp body. |
| `:cancel` | Discard incomplete input. |
| `:quit` | Exit, discarding incomplete input. |

For the example above, `:symbols` prints the list template
`%((function "plus") (value "total"))`. Typed AST output begins with
`typed: %(`; `:lowered plus` prints
`compiled: native function; no Lisp body`. Inspection does not execute the
function, and earlier functions remain inspectable after later submissions.
Values have symbol entries but no function AST.

`:symbols pl` lists only names beginning with `pl`. `:info plus` prints a
declaration, `source: prompt`, and `execution: native`. For a loaded function,
the source is the loaded file's resolved absolute path. Parameter names are
omitted from the printed declaration; argument and return types remain.
Tab completion for `:info` includes both prompt functions and loaded functions.

Help and inspection commands preserve incomplete input, including when a
command reports an error. Colon commands are recognized on separate lines
even inside an incomplete string or comment. Missing names, extra arguments,
and unknown commands report errors.

`--dump` prints each available typed AST and lowered Lisp form to standard
error. `--stats` prints the concise runtime report at exit, to standard error.
`--verbose-stats` prints the detailed report and implies exit reporting; when
both statistics options are present, one verbose report is printed. The
options can be combined with `--dump`.

The report separates absolute live or retained quantities from activity since
the REPL opened. Scope allocation objects and live requested bytes are
process-wide runtime values; requested bytes count public managed payload.
Pool active and depot bytes partition retained backing capacity. Scope and
Pool figures overlap and must not be summed. Verbose reports add Scope and
Pool traffic and capacity details. There is no Lisp wordcode or AUTO tier.

## Load functions from a file

Save this source as `numbers.x`:

```x2c
static int twice(int n) { return 2 * n; }
static int calls = 0;
int answer(int n) { calls++; return twice(n + 1); }
int call_count(void) { return calls; }
```

Load it and call its functions with ordinary prompt expressions:

```text
x2c> :load "numbers.x"
loaded ("answer" "call_count")
x2c> answer(20);
=> 42
x2c> call_count();
=> 1
x2c> int plus_answer(int n) { return answer(n) + 1; }
defined plus_answer
x2c> plus_answer(20);
=> 43
```

`:load` compiles native code through the project meta helper builder. It
uses the ordinary include, module, package, and native dependency handling.
Public functions with bodies in the loaded file become prompt functions,
including `main`. No `meta` annotation is needed. Static helpers such as
`twice` remain private. Functions from included files and declaration-only
functions remain available to the compiled code but are not imported into
the prompt. Public type declarations accompany the loaded definitions.
Enumerator constants are not imported. Source macros remain
with the compiled source; loading does not install them in the prompt.

Public scalar globals are also available without source changes. Reads and
assignments use the same native storage as the file's functions:

```x2c
int counter = 10;
const int limit = 100;
static int private_counter;
int read_counter(void) { return counter; }
```

After loading this file, `counter;` returns `10`. Entering `counter = 20;`
makes `read_counter();` return `20`. Compound assignments and numeric prefix
or postfix increments also work. Prompt functions can read and assign these
globals, including functions saved before a reload. `limit` is read-only,
and `private_counter` remains private. `:symbols` lists the public globals.

Supported scalar values are numbers, booleans, enums, Strings, and Symbols,
including typedef aliases. Enum values use the compiler's `int`
representation. Fixed-size C arrays and structs also expose their scalar
fields and elements, including nested arrays and structs:

```x2c
int samples[3] = {10, 20, 30};
struct Point { int x; int y; };
struct Point point = {1, 2};
```

After loading this file, `samples[1];` returns `20`. Assignments such as
`samples[1] = 99;` and `point.x = 7;` change the file's native storage.
Compound assignments and increments work too. Array indices are checked
against the native array's extent and evaluated once per access. These
operations also work inside compiled prompt functions.

Enter `samples;` or `point;` to inspect the whole object. Arrays display as
Arrays and structs as Maps keyed by field name. Inspection copies the data
and visits at most 100 fields or elements, including nested containers;
`"..."` marks truncated output. Unsupported fields display `"<unavailable>"`.
Inspection is available for the final expression at the prompt. Native
arrays and structs still cannot be passed or copied across the helper
boundary as ordinary values. Assign fields and elements individually.

Static globals stay private. Const objects and const fields are read-only.
Raw pointers, unions, flexible array members, collections, `Var`, and
callable globals do not gain accessors. Globals from included files remain
private to the loaded file. A loaded global, field, or element cannot supply
an address or a reference argument because its storage belongs to the helper
process.

Compilation happens on `:load` and on each prompt function definition,
including `plus_answer` above. Top-level input stays interpreted. Loading needs
a matching x2c compiler, the host C compiler, and its runtime. A dependency
that the project meta builder cannot compile or link makes the load fail.
An explicit `meta` function remains callable under the same data limits.

Each successful load keeps a separate helper process and its compiled
executable until the session closes. Native static values persist between
calls, and another load does not reset them. Calls exchange data values:
numbers, Strings, Symbols, Lists, and independent Arrays and Maps. Arrays
and Maps are copied across the boundary. Mutating a collection argument in
the helper does not mutate the prompt's collection; return the changed
collection to use it. Pointers, references, callbacks, records, cycles, and
shared mutable collection identity cannot cross this boundary. Functions
with these signatures can still be used inside the compiled file; calls
from the prompt must satisfy the data limits.

A failed load publishes no names and preserves earlier functions. Fix a
rejected file and load it again. Loaded names appear as `native` in
`:symbols`; `:info` shows their declarations and loaded file. They have no
prompt AST or lowered Lisp for inspection.

### Load a program with main

`:load` also accepts a program with `main`, including a `.c` file. The source
needs no `meta` annotation or renamed function. Save this as `hello.c`:

```x2c
#include <stdio.h>
int main(int argc, char *argv[]) {
  for (int i = 0; i < argc; i++) printf("%d: %s\n", i, argv[i]);
  return 0;
}
```

Pass an Array of Strings, including the program name as its first element:

```text
x2c> :load "hello.c"
loaded ("main")
x2c> main(["hello", "world"]);
0: hello
1: world
=> 0
```

The adapter supplies `argc`, writable copies of the argument strings, and
the final null pointer at `argv[argc]`. `main([])` passes zero arguments.
Changes to `argv` do not change the prompt's Array or Strings.
`:info main` shows the prompt signature `int main(Array);`.

A program with `int main(void)` or `int main()` is called as `main()`.
Both forms return zero if execution reaches the closing brace. Returning
from `main` produces a prompt result and leaves the REPL running. Standard
output and standard error appear on their usual streams, including output
without a final newline. Loading alone does not execute `main`.

The original function keeps its native calling convention inside the
compiled program. Its ordinary helpers and references to `main` continue
to work. The loader changes bound compiler syntax, not the source file.
Other C dialect and dependency limitations still apply; loading does not
provide missing libraries. Calling `exit` ends the helper, as described
below under interrupted calls.

`main` follows the same replacement rules as other loaded functions. Saved
function values and compiled prompt callers use its replacement. Changing
between the no-argument and argc/argv forms requires a new session. A second
loaded file cannot publish another `main` in that session.

### Edit a loaded file

After editing a file, use the same `:load "file.x"` command. A successful
replacement prints `reloaded`. Calls use the new code, including calls from
earlier prompt functions. Saved `Func` values use the replacement for calls
the REPL already supports. Prompt variables and functions remain, as do
other loaded files. Variables inside the replaced file and its compiled
dependencies start over, even if the file did not
change. Previously returned values remain ordinary prompt data.

Existing functions must keep their argument and return types. Parameter
names may change. Existing public types must keep their definitions. New
functions, globals, and types are allowed when their names do not
conflict. Existing globals must keep their declared types and qualifiers,
including `const`. Removing an existing function, global, or type, or
changing its type, requires a new session.
A refused replacement leaves both the old code and its variables intact.
Prompt definitions still cannot be redefined.

Relative paths, absolute paths, and symbolic links to the same file identify
one load. Each loaded file has its own compiled dependencies. If two loaded
files include the same dependency, loading one again updates only that
file's copy. Load the other file again to update its copy too.

For a real example, copy the autodiff module from a repository checkout:

```sh
cp packages/autodiff/src/autodiff-macros.x /tmp/autodiff-repl.x
x2c repl
```

At the prompt, load and inspect the copy:

```text
:load "/tmp/autodiff-repl.x"
:symbols ad_do
:info ad_dot
```

The filtered list contains `ad_dot`. Its declaration is
`String ad_dot(String);`, followed by the loaded file's absolute path.
Keep some test data and a prompt function:

```text
x2c> String label = "loss";
ok
x2c> String derive(void) { return ad_dot(label); }
defined derive
x2c> derive();
=> "loss_dot"
```

Edit the copy's `ad_dot` definition to append `"_derivative"` instead of
`"_dot"`. Run `:load "/tmp/autodiff-repl.x"` again, then call `derive()`.
The result is `"loss_derivative"`; the earlier `label` and `derive` still
work. This module also exposes syntax helpers such as `ad_unbind` and
`ad_mutates`, which can be called with List values from the prompt.

A native call that exits, crashes, or exceeds `X2C_META_TIMEOUT` fails that
submission. The next call restarts that load's helper from its retained
executable, resetting that helper's native state. Other loaded helpers keep
their state. Ordinary errors raised by a function leave its helper running.

## Supported subset

The current subset includes initialized simple variables, function
definitions, integer arithmetic and narrowing, assignment, conditionals,
`for` loops, self recursion, and calls to earlier functions. String values
and length, List literals and indexing, and Array construction, mutation,
and indexing are exercised by the focused checks. Captured `Func` values
can be called directly or passed to supported native callbacks. A record
captured by value retains a copy through later submissions.

The whole interpreter exposes the fixed-signature
`String.format(String fmt, List values)` operation. Call it as
`fmt.format(values)`:

```x2c
~List values = %("answer" 42);
String text = "%s=%04d".format(values);
```

It supports `%%`, flags `-+ #0`, numeric and `*` width and precision, integer
conversions `d i o u x X` with `hh h l ll`, floating conversions
`f F e E g G a A` with default, `l`, or `L`, plus `%c` and `%s`. It converts
numeric `Var`s and uses `Var.str` for `%s`. Pointer and write-count
conversions, wide strings and characters, positional formats, and `j z t`
lengths are rejected. The result follows the process locale, and a failure
publishes no partial String. Native `String.printf` retains its ordinary C
varargs contract for compiled code.

REPL sessions also provide `print(String)` and `println(String)`. `print`
writes the String's bytes; `println` writes those bytes followed by one
newline. Use String interpolation for formatting, such as
`println(%"count=$count")`. Both functions are REPL-only, reserve their names
in the session, and report `ok` rather than a synthetic value. They are not
varargs aliases.

A session also declares `Json`, `Diff` and `Path`, so `Json.parse`,
`Diff.unified` and `Path.basename` evaluate without an include.

Redefinition is disabled; assign to an existing variable to change its value.
Function replacement and mutually recursive forward declarations are not
supported. Names beginning `__repl_` are reserved.

Arbitrary C libraries, unions, enums, imports, protocols, user macro/meta
definitions entered at the prompt, preprocessor directives, and direct Lisp
input are outside this subset. A bodyless `meta`
prototype is accepted: it makes a function the compiler links, or one from a
[native module](meta-functions.md#native-modules) loaded with
`--native-module`, callable in the session. Variables need
initializers; declarator modifiers, `const`, and `volatile` are rejected.
Function-local `static`, `extern`, and `threaded` storage remain rejected.
Top-level statement expressions can contain local declarations followed by
one value expression, such as `({ int n=3; n+4; })`. Other statement
expression bodies are declined.
Reference parameters use the ordinary compiler conversion: pass an
addressable value, or write `*p` to pass a pointer's object. A pointer itself
cannot substitute for the referenced object.
Records, typedefs, addressed locals and pointer reads/writes use native
storage with layouts derived from compiler types. Record assignment copies
into existing storage, preserving pointers to its fields. A session
global scalar or record keeps its address until the session closes. Other
top-level constructs depend on the existing lowering and may be declined.
Native function bodies use ordinary compiler semantics; for example, `goto`
is available there. Loaded public types can be used in prompt functions
within the same native layout limits as interpreted objects. The interpreter
does not provide full native parity:
it loses the distinction between `Var void` and an empty List.

## Failure and lifetime

Rejected submissions leave earlier definitions usable. A declaration
publishes its names only after all initializers succeed. If a later
initializer fails, none of that declaration's names become available,
including through inspection. Effects already made on existing values
remain, both for failed initialization and failed statements.

Session storage lives until exit. Submission scratch is reclaimed, but
canonical syntax, compiler caches, and evaluator allocations can accumulate.
Long sessions do not have a bounded-memory guarantee. Compiled modules stay
loaded for the process lifetime; captured bindings belong to their session.
Each submission may make 40 million interpreted Lisp calls, the evaluator's
default budget.
SIGINT (Ctrl-C) during evaluation stops the submission with an
`(interrupt ...)` evaluation error. Once the budget is exhausted or the
submission is interrupted, no further interpreted code runs, including
pending `defer` bodies. Ordinary evaluation failures
still run those cleanups. The next submission gets a fresh budget. Native
callbacks and compiled prompt functions are not a preemptible sandbox: an
interrupt takes effect at the next interpreted call. Compiled function loops
do not consume the Lisp budget. Their native crashes or nonterminating loops
can end or block the REPL process. Loaded files retain their separate helper
process and timeout behavior.

EOF exits successfully unless input is incomplete, which exits with status
1. With piped input, any submission or command error makes the final status
1, while later input still runs. In an interactive session, recovered errors
do not change a normal exit's status from 0.

During interactive editing, Ctrl-C clears both the current edit buffer and any
pending incomplete submission, then returns to the `x2c> ` prompt without a
diagnostic. Ctrl-D on an empty edit buffer exits; pending incomplete source
still makes that exit status 1. Terminal canonical mode is restored before a
submission runs. Ctrl-C during interpreted evaluation stops only that
submission.
Terminals without the required escape-sequence support use the basic line
reader instead. Piped input retains the same output and exit behavior.
