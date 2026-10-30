# Library playground

`x2c repl` is a persistent command-line session for experimenting with C and
x2c libraries. Load a source file, discover its functions, create an object,
and call operations on that object across successive submissions. The
command is experimental and available in checkout builds; neither
`make install` nor a release payload installs it.

Executable submissions compile through the ordinary compiler. Prompt objects
and library objects share one native worker process, so native pointers,
struct values, aliases, and C callbacks retain their ordinary meaning. The
terminal client stays alive when the worker exits or crashes.

```sh
x2c repl
x2c repl --help
x2c repl points.c
x2c repl -I include build/libpoints.a include/points.h
x2c repl --manifest-path x2c.toml --target core
```

Native include, define, compiler, linker, package-directory, and explicit
manifest options use the same spellings as `x2c build`. A header plus a
matching native library is sufficient; no generated package or `meta`
annotation is required. Prepare optional packages before using them. The
playground does not install missing dependencies.

## Create, call, and inspect

For example, save this C source as `points.c`:

```x2c
#include <stdlib.h>

typedef struct Point { int x; int y; } Point;

Point *point_new(int x, int y) {
  Point *p = malloc(sizeof(*p));
  if (!p) return NULL;
  p->x = x;
  p->y = y;
  return p;
}
void point_move(Point *p, int dx) { p->x += dx; }
void point_free(Point *p) { free(p); }
```

Start the REPL, then enter these submissions:

```text
:load "points.c"
:symbols point
:info point_move
:source point_move
Point *p = point_new(1, 2);
point_move(p, 5);
:inspect *p
p->x;
point_free(p);
p = NULL;
```

`p` designates the same allocation on each line. Inspection shows a `Point`
with `x` equal to `6` and `y` equal to `2`. A function can also return a
struct by value, accept the address of a prompt variable, fill an
out-parameter, or call a named prompt function through a C function pointer.

Loading a C source file also exposes its file-scope `static` functions and
objects. Their native linkage and storage stay unchanged. Calls from the
prompt and from the program use the same objects, including function-local
static storage. Static declarations from dependency headers stay private.
Header-only and binary-library loads keep their ordinary public surface.
If a file-static name conflicts with a name from another loaded source file,
the load fails with both paths and preserves the active session. Load those
files in separate sessions when their private names overlap.

For a complete program, run the checked-in [N-body demo][nbody-demo] from the
repository root:

```sh
./x2c repl < commands/repl/examples/nbody.repl
```

The [input script][nbody-input] loads the unchanged C benchmark, discovers
its functions, shows a static definition, and inspects the `bodies` array
before and after calls. The walkthrough also shows how to enter each command
interactively.

[nbody-demo]: https://github.com/gwf/x2c/blob/dev/commands/repl/examples/README.md
[nbody-input]: https://github.com/gwf/x2c/blob/dev/commands/repl/examples/nbody.repl

A C library often exposes an opaque handle. Inspect the pointer's declared
type and use `:members` to find related operations. Use the library's query
functions to examine its state; an incomplete type does not reveal private
fields.

The final expression in a submission displays its result. Declarations and
statements report `defined NAME` or `ok`. Semicolons are required. Incomplete
input continues at `... ` until it forms a complete submission. Submit one
persistent declaration or function definition at a time. Executable input
can contain several statements.

## Try an installed C library

If your host provides SQLite headers and its native library, create a small
header that selects the API and start a session:

```sh
printf '#include <sqlite3.h>\n' > sqlite-api.h
x2c repl -l sqlite3 sqlite-api.h
```

The SQLite declarations come from the included header. Use `--all` to browse
those dependency declarations, then call the ordinary C API:

```text
:symbols --all sqlite3_open
:info sqlite3_prepare_v2
sqlite3 *db = NULL;
sqlite3_open(":memory:", &db);
sqlite3_stmt *query = NULL;
sqlite3_prepare_v2(db, "SELECT 6*7", -1, &query, NULL);
sqlite3_step(query) == SQLITE_ROW;
:inspect sqlite3_column_int(query, 0)
sqlite3_finalize(query);
sqlite3_close(db);
```

The inspected column is `int 42`. The database and statement are ordinary
opaque C handles. They stay alive until the library's explicit release calls.

## Discover the API

| Command | Result |
| --- | --- |
| `:help [COMMAND]` | Show commands or one command's arguments. |
| `:symbols [PREFIX]` | List prompt and selected library declarations with signatures and origins. |
| `:symbols --all [PREFIX]` | Include visible runtime and dependency names. |
| `:symbols --kind KIND --file "PATH" [PREFIX]` | Filter by kind, source file, or both. |
| `:info NAME_OR_EXPRESSION` | Show a declaration or an expression's type without evaluating it. |
| `:members TYPE_OR_EXPRESSION` | Show fields, methods, and related C functions. |
| `:source NAME` | Show the captured source definition or available header declaration. |
| `:files` | Show loaded roots and native build settings. |

For example, `:info point_move` includes parameter names and their types.
`:members Point` lists its fields and related C functions. Related C
functions retain their real names and calling syntax: discovering
`point_move` does not create an invented `Point.move` method.

Declared x2c methods accept their ordinary `Type.method` spelling in
inspection. Tab completion offers relevant names in their grammar position,
including fields and methods on a typed receiver. A second Tab lists grouped
choices. Colon commands complete arguments, including file paths.

Source lookup shows the source snapshot used to build the running code. An
edit on disk does not change `:source` until a successful reload. A native
library without implementation source shows its available header declaration
and says that the definition is unavailable. Source lookup does not decompile
binary code.

## Inspect objects

```text
:inspect *p
:inspect --depth 5 --limit 200 *p
:info p->x
```

`:inspect` evaluates its expression once. The default view displays at most
100 entries and descends three levels. Truncation is marked. Select a field
or element directly, or increase the explicit limits to see more.

Structs display named fields, arrays display their extents and indexed
contents, and ordinary x2c value types keep their readable representations.
Prompt objects, loaded globals, and returned records use the same display
policy.

Pointers display their type, nullness, and address. Inspection never follows
a raw pointer automatically. Write `:inspect *p` or `:inspect p[2]` when you
want that native read. A raw `char *` remains a pointer too; use an explicit
`String.new(p)` or a library length/query operation to inspect text.

Unions display their type and member choices. Select a member explicitly to
read it; the REPL does not guess which member is active. Automatic traversal
skips volatile fields and labels them. Explicit expressions preserve ordinary
volatile semantics. Bitfields use native field access.

`:info`, `:members`, and `:source` do not run the inspected expression.
`:inspect` can have the expression's ordinary effects. A bad native pointer
read can terminate the worker, just as a bad library call can.

## Load and repeat

| Command | Result |
| --- | --- |
| `:load "PATH" ...` | Add source/header roots and build a candidate program. |
| `:reload` | Rebuild the current roots from current source files. |
| `:reset` | Start fresh from the last successful program and its declaration snapshot. |
| `:save "PATH"` | Save successful source submissions, load/reset boundaries, and launch settings. |
| `:replay "PATH"` | Start fresh and explicitly rerun a saved transcript, stopping at the first failure. |
| `:quit` | Run session cleanup and leave the playground. |

Every successful load or reload clears **all prompt and library state**.
This includes loading an additional file or an unchanged file. The REPL
announces the reset. A failed build, link, or candidate initialization keeps
the previous session. Ctrl-C during candidate preparation cancels the
candidate and preserves the active session.

`:reset` uses the exact retained program and declarations. Editing a source
or header does not change that snapshot. An explicitly linked shared library
that changed on disk requires `:reload` before a new worker can use it.

Prompt variables can be assigned new values. Duplicate prompt definitions
remain rejected. To change a function or type, reset or reload and rerun the
needed submissions. No native object, saved callback, or apparent address
survives a session replacement.

Saved `.repl` files contain source instructions and their original path base,
not serialized heap objects. Replay uses current source dependencies and has
normal side effects. It is always explicit. The terminal never replays calls
automatically after a load, crash, or interruption. A failed submission can
leave partial mutations or external effects that a successful-input script
cannot reproduce.

## Lifetimes and cleanup

The top-level prompt is one session scope. Persistent variables and direct
top-level `defer` registrations live until orderly quit, reset, or successful
replacement. Cleanup runs in reverse registration order. Function calls and
explicit blocks retain their ordinary automatic lifetimes.

The distinction between managed declarations and managed initializers remains:

- `auto T x = ...` cleans `x`'s current value at scope exit.
- `T x = auto acquire()` saves and cleans the acquired value despite a later
  reassignment of `x`.
- `defer release(x)` reads `x` when cleanup runs.

Raw C pointers do not acquire a destructor from their names or types. Release
library allocations with the library's documented operation. Escaping a
pointer to an expired automatic object remains an ordinary C lifetime error.
A forced stop or native crash cannot guarantee cleanup or undo external
effects.

## Editing and failures

Arrow keys, Home, End, Backspace, Delete, and history recall work at an
interactive prompt. Bracketed paste and recalled multiline source remain one
editable entry. History keeps the latest 100 nonempty entries and suppresses
adjacent duplicates. Interactive history persists under
`$XDG_STATE_HOME/x2c/repl-history`, or
`$HOME/.local/state/x2c/repl-history` when that variable is unset.

Ctrl-C while editing clears the current edit and pending incomplete source.
Ctrl-D exits from an empty edit. `:cancel` discards incomplete input.

During native execution, Ctrl-C terminates the worker and its active job
process group. The terminal announces lost state and starts a fresh worker
from the last successful program. Native exit, assertion failure, and crashes
follow the same recovery rule. There is no short default timeout for ordinary
library calls. A hanging cleanup can also be stopped explicitly.

Native standard output and standard error retain their usual streams.
Interactive native standard input uses the terminal while a call runs. With
piped REPL source, native standard input gets EOF; it cannot consume later
source submissions.

Syntax, type, and link errors publish no new definitions. A failed
initializer publishes none of its declaration's new names. Mutations already
made to older objects and external effects remain. An ordinary caught x2c
Error can return control to the existing worker.

With piped input, any command or submission error makes the final exit status
1, while later input continues. Interactive recovered errors do not change a
normal exit status. Incomplete input at EOF exits with status 1.

## Execution details

`:ast NAME` shows a prompt function's typed AST. `:lowered NAME` explains
that submissions execute natively. `--dump` prints typed submission syntax
and the retained directory containing native headers, source, and module;
`--stats` and `--verbose-stats` print worker allocation statistics at exit.
`:stats [verbose]` reports those statistics during a session.

The worker needs the matching x2c compiler, runtime, and configured host C
toolchain. New executable submissions incur native compilation work; cached
artifacts avoid compiling identical code again. Earlier submissions and their
initializers are not rerun to compile the next expression. Native modules may
remain loaded until the worker retires, so reset provides a reclamation
boundary.

Use source/header roots for includes, package imports, and user-authored
macro/meta/protocol surfaces. Live configuration-changing directives and
incremental definitions of those surfaces are outside this first playground
scope. The ordinary compiler and host C dialect still determine which native
libraries and calling conventions the selected toolchain supports.
