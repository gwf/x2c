# Experimental REPL

`x2c repl` is a shipped external command that evaluates a supported subset
of x2c in a persistent session.
Each submission that defines or runs code is compiled with the session's
earlier definitions into a native module, loaded into the REPL process, and
called. The C compiler runs once per new submission, typically 100-300 ms;
a submission identical to one compiled before loads from the module cache.

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
| `:symbols` | List successfully defined names and their kinds. |
| `:ast plus` | Show `plus`'s typed x2c AST. |
| `:lowered plus` | Show the C that the last staging emitted for `plus`. |
| `:cancel` | Discard incomplete input. |
| `:quit` | Exit, discarding incomplete input. |

For the example above, `:symbols` prints the list template
`%((function "plus") (value "total"))`. Typed AST output begins with
`typed: %(`; `:lowered` prints C. Inspection does not execute the function, and earlier functions remain inspectable after
later submissions. Values have symbol entries but no function AST.

Help and inspection commands preserve incomplete input, including when a
command reports an error. Colon commands are recognized on separate lines
even inside an incomplete string or comment. Missing names, extra arguments,
and unknown commands report errors.

`--dump` prints each available typed AST to standard error. `--stats` prints the concise runtime report at exit, to standard error.
`--verbose-stats` prints the detailed report and implies exit reporting; when
both statistics options are present, one verbose report is printed. The
options can be combined with `--dump`.

The report separates absolute live or retained quantities from activity since
the REPL opened. Scope allocation objects and live requested bytes
are process-wide runtime values; requested bytes count public managed payload,
not allocator metadata. `requested-traffic-bytes` remains cumulative activity.
Pool active and depot bytes partition retained backing capacity; they are not
reachable payload. Scope and Pool figures overlap and must not be
summed. x2c has no garbage collector, so reuse and promotion counters are
activity rather than collection counts. Verbose reports add Scope creation
and peak data and Pool traffic and capacity detail.

## Supported subset

The current subset includes initialized simple variables, function
definitions, integer arithmetic and narrowing, assignment, conditionals,
`for` loops, self recursion, and calls to earlier functions. String values
and length, List literals and indexing, and Array construction, mutation,
and indexing are exercised by the focused checks.

The runtime exposes the fixed-signature
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

Arbitrary C libraries, unions, enums, arrays as values, imports, protocols, user macro/meta definitions, preprocessor
directives, and direct Lisp input are outside this subset. A bodyless `meta`
prototype is accepted: it makes a function the compiler links, or one from a
[native module](meta-functions.md#native-modules) loaded with
`--native-module`, callable from compile-time Lisp in the session. Variables need
initializers; declarator modifiers, `const`, and `volatile` are rejected.
Function-local `static`, `extern`, and `threaded` storage are also rejected.
A submission whose C does not compile is rejected with the C compiler's
diagnostics. A final expression whose type has no `Var` form cannot be
displayed.

## Failure and lifetime

Rejected submissions leave earlier definitions usable. A declaration
publishes its names only after all initializers succeed. If a later
initializer fails, none of that declaration's names become available,
including through inspection. Effects already made on existing values
remain, both for failed initialization and failed statements.

Session storage lives until exit. Submission scratch is reclaimed, but
canonical syntax, compiler caches, and evaluator allocations can accumulate.
Long sessions do not have a bounded-memory guarantee. Loaded modules stay
loaded; each value lives in the module that initialized it. Submissions run
as native code in the REPL process: a runaway loop hangs the session, and a
crash ends it.

EOF exits successfully unless input is incomplete, which exits with status
1. With piped input, any submission or command error makes the final status
1, while later input still runs. In an interactive session, recovered errors
do not change a normal exit's status from 0.

During interactive editing, Ctrl-C clears both the current edit buffer and any
pending incomplete submission, then returns to the `x2c> ` prompt without a
diagnostic. Ctrl-D on an empty edit buffer exits; pending incomplete source
still makes that exit status 1. Terminal canonical mode is restored before a
submission runs, so Ctrl-C during evaluation continues to terminate the
process. Terminals without the required escape-sequence support use the basic
line reader instead. Piped input retains the same output and exit behavior.
