# x2c bind

This experimental command writes the mechanical part of a new package from a
C header: the header shim, one handle type for each opaque pointer type,
inline methods that forward the C functions taking a handle first, and
`Cleanup` adoptions for paired releases. The author then writes the ordinary
x2c surface. Run `make commands` to build it at
`builds/0/libexec/x2c-bind`, and `make commands-check` for its smoke test.

```sh
builds/0/x2c bind --package sqlite3 \
  --header "$(xcrun --show-sdk-path)/usr/include/sqlite3.h" -l sqlite3
```

The command writes `packages/sqlite3/` unless `-o DIR` names another
directory. `-I DIR` adds a directory for headers that the bound header
includes; it also reaches the generated `Makefile`. `-l LIB` adds a library
to the consumer link flags. `--prefix PREFIX` overrides the library prefix
that method names lose.

## Input

The command uses the compiler as a library, as `x2c lint` and `x2c graph`
do. It collects two units through the host preprocessor, the collection that
`x2c translate --cpp-symbols` uses: an empty unit and a unit that includes
the header by its absolute path. The header's declarations are the rows of
the second unit that the first lacks, so system and runtime declarations
drop out without a list of names. Collection records each function's
parameter and result types, typedefs with their targets, struct and union
fields, and enums with their enumerators.

Collection does not record three things the command would use:

- Parameter names. Generated parameters are positional: the receiver is
  named by its type's lower-case initial, as the code standard's NM-2
  names a subject, and the others are `arg1`, `arg2`, and so on.
- Macro constants. The host preprocessor expands them before collection.
  They stay available through the header, and the README stub says so.
- Deprecation and availability attributes. Methods are therefore generated
  for deprecated functions; see the inline rule below.

Collection also walks the quoted include itself without evaluating
`#ifdef`, so a typedef or prototype in a disabled branch has a row. The
command keeps a function only when its name occurs in the host
preprocessor's output. For the header-only termbox2 2.5, this drops the 52
static functions of its `TB_IMPL` implementation and keeps its 38 `tb_`
functions. termbox2 keeps its state in process globals, so its functions take
no handle and the command generates only the shim for it.

## Output

The package uses the standard layout in
[packages/README.md](../../packages/README.md#package-layout):

- `src/STEM-raw.h`, where STEM is the header's name without `.h`, includes
  the real header with angle brackets and marks where the version check
  belongs. The generated unit header is `NAME.h`, so the shim needs a
  different name; the author renames it after the pinned version.
- `src/NAME.x` holds the generated region between
  `/* x2c bind: begin generated raw tier */` and
  `/* x2c bind: end generated raw tier */`, followed by a place for the
  ordinary surface.
- `Makefile` sets `PACKAGE`, includes `../package.mk`, and sets
  `PACKAGE_C_FLAGS` and `PACKAGE_LINK` from `-I` and `-l`.
- `README.md` lists what was generated and what remains to be written.

A later run replaces only the generated region of `src/NAME.x` and keeps the
text after it. It writes the other files only when they are absent. A
`src/NAME.x` without both markers is left unchanged, and the command exits
with status 1.

## Rules

Each rule is mechanical, so a later run produces the same text.

1. A handle is a typedef of a struct or union tag that the header never
   completes, when some function takes a pointer to it as its first
   parameter. Its x2c name joins the capitalized words of the C name:
   `sqlite3_stmt` becomes `Sqlite3Stmt`. A name that an empty unit already
   declares gains the suffix `Handle`. Complete structs, such as libuv's
   handle records, are not handles.
2. A function whose first parameter points to a handle, `const` or not,
   becomes an `inline` method on that handle. The method name is the C name
   without `C_TYPE_` when it starts with the receiver's C type, otherwise
   without the library prefix: `sqlite3_blob_close` becomes
   `Sqlite3Blob.close`, and `sqlite3_bind_int` becomes `Sqlite3Stmt.bind_int`.
   The library prefix defaults to the longest prefix ending in `_` that all
   the header's functions share. A name that collides on the same handle, or
   that a runtime protocol or conversion already uses (`cleanup`, `var`,
   `iter`, `str`, `len`, `truth`, `getindex`, `setindex`), keeps the C name.
3. Every non-`const` `T *` parameter or result whose `T` is a handle's C
   type is spelled with the handle type, so `sqlite3_db_handle` returns
   `Sqlite3` and `sqlite3_prepare_v2` fills a `Sqlite3Stmt *`. Other types
   keep their C spelling, including function pointer parameters.
4. A method is `inline`, so it reaches the generated header as a
   `static inline` function. A program compiles and links only the C
   functions it calls. That matters for SDK headers: the macOS SDK declares
   functions that an older running system lacks, and an archive of ordinary
   forwarders fails to load there. The C compiler still warns about inline
   forwarders to deprecated functions in each unit that includes the
   generated header.
5. Variadic functions and functions taking a `va_list` are not forwarded.
   Functions without a handle receiver are not generated; they remain C
   calls through the header under their real names. A plain forwarding
   function would need a new name, and stripping the prefix collides with C
   library names such as `sqlite3_free` and `free`.
6. A release is a one-parameter method whose first word is a release verb,
   when some header function whose name holds the paired acquisition verb
   returns a `T *` or fills a `T **`. The pairs are `open`/`close`,
   `new`/`free`, `new`/`delete`, `new`/`destroy`, `create`/`destroy`,
   `create`/`free`, `alloc`/`free`, and `prepare`/`finalize`. The shorter
   name wins: `Sqlite3` releases with `close`, and `close_v2` stays a method.
   The region adopts `Cleanup` with `$cleanup.by(Handle, release)`, as the
   existing packages do, so `Handle h = auto acquire(...);` releases it. A
   handle filled through an out-parameter uses declaration `auto`:
   `auto Sqlite3 db = NULL;` before `sqlite3_open(path, &db)`.
7. Each generated type and method has a `/**` comment directly above it,
   whose first sentence stands alone.

The command does not write curated semantics: no Error conversion, String
or collection results, iteration, Var adapters, Lisp bindings, license
files, or dependency pins. The README stub names those as remaining work.

## Compared with packages/sqlite

Generating from the macOS SDK's `sqlite3.h` (SQLite 3.51.0) produces 8
handles, 207 inline methods, and 4 releases (`Sqlite3.close`,
`Sqlite3Blob.close`, `Sqlite3Mutex.free`, `Sqlite3Stmt.finalize`). Of the 284
header functions, 73 have no handle receiver and 4 are variadic or take a
`va_list`. The generated region is 1014 lines. The hand-written
`packages/sqlite/src/sqlite.x` is 466 lines, and its pinned header is SQLite
3.53.4, so the inventories differ slightly.

The generator reproduces these parts of the hand-written package:

- The shim shape: a header that includes the real `<sqlite3.h>` once. The
  hand-written shim also rejects other versions and a non-serialized
  profile; the generated shim leaves that check as a placeholder.
- Handles for the two types the package wraps, `sqlite3` and
  `sqlite3_stmt`, with `$cleanup.by` adoptions that release them through
  `sqlite3_close` and `sqlite3_finalize`.
- Receiver-call access to the native operations. The hand-written source
  calls 32 distinct `sqlite3_` functions; 30 of them are generated methods.
  The other two, `sqlite3_open_v2` and `sqlite3_errstr`, take no handle
  first and remain C calls.

It cannot reproduce these parts:

- The owning wrapper structs `Database` and `Prepared`, their idempotent
  `close` and `free`, liveness checks, and `native()` accessors. Generated
  handles are the native pointers themselves.
- All 19 public `Database` and `Prepared` methods as written. Five share a
  generated method's name: `busy_timeout`, `changes`, `close`,
  `last_insert_rowid`, and `reset`. Even these differ, because the
  hand-written versions raise Errors with SQLite's code and message, and
  `changes` calls `sqlite3_changes64`. The other 14 (`open`, `open_with`,
  `execute`, `prepare`, `transaction`, `bind`, `bind_named`, `columns`,
  `next`, `iter`, `free`, `native` twice, and `Prepared.execute`) need
  curated semantics.
- The four Var converters, the `Var` and `Iter` protocol adoptions, the six
  Lisp bindings and `SqliteLisp.install`, and the four static error and
  liveness helpers.
- The package README, `dependency.json`, `headers.sha256`, `LICENSES/`,
  `PROFILE.md`, tests, and examples.

To reproduce the comparison on macOS:

```sh
mkdir -p /tmp/bind/packages && cp packages/package.mk /tmp/bind/packages/
builds/0/x2c bind --package sqlite3 -l sqlite3 -o /tmp/bind/packages/sqlite3 \
  --header "$(xcrun --show-sdk-path)/usr/include/sqlite3.h"
make -C /tmp/bind/packages/sqlite3 build X2C="$PWD/builds/0/x2c"
builds/0/x2c build --package-dir /tmp/bind/packages \
  --output /tmp/bind/consumer commands/bind/tests/sqlite-consumer.x
/tmp/bind/consumer
```

## Tests

`tests/run.sh` binds `tests/feed.h`, a small fixture library, and compares
the generated entry unit, Makefile, and README with `tests/expected/`. It
builds the package with `package.mk`, links `tests/consumer.x` with the
fixture's C implementation, and checks the consumer's output. It also checks
that a prototype in a disabled `#ifdef` branch is left out, that a rerun
keeps text outside the region, that a file without markers is refused, and
that the driver dispatches `x2c bind` and `x2c help bind`. When the host has
`sqlite3.h` from the macOS SDK or `/usr/include`, it binds that header too
and runs `tests/sqlite-consumer.x`; otherwise it prints that the SQLite check
was skipped.
