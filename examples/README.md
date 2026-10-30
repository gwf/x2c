# Examples

Start with [foreach.x](foreach.x), or follow the Love, Power, and Magic
examples from the landing page. Most gallery programs contain the website's
code, including its normally hidden setup and assertions. Autodiff and package
slides instead link to existing, independently maintained examples. Both
kinds of correspondence are listed in [gallery.json](gallery.json).

After building x2c, start from the repository root. Use `./x2c` to select
the current development build:

```sh
./x2c run examples/foreach.x
make examples

# Run two of the executables that make examples built.
./examples/build/foreach/foreach
./examples/build/programs-lisp/lisp
```

The Lisp shell is interactive; press Ctrl-D to exit. `make examples` builds
and checks the curated examples, leaving executables under `examples/build/`.

Files, Counting, and Exceptions use their checked-in data by default when
started from the repository root:

```sh
./x2c run examples/love/files.x
./x2c run examples/power/counting.x
./x2c run examples/power/exceptions.x
```

Files and Counting also accept an input filename. Exceptions accepts a
directory containing its `document.txt` and `document.bin` fixtures. Pass an
explicit input path when running a built executable. From another directory,
replace the executable paths below with absolute paths too:

```sh
./examples/build/love-files/files /absolute/path/to/quantities.txt
./examples/build/power-counting/counting /absolute/path/to/words.txt
./examples/build/power-exceptions/exceptions /absolute/path/to/fixtures
```

The [c2x2c tutorial](c2x2c/README.md) follows eight versions of a word counter,
from native C to parallel directory counting. Its manual commands and viewer
are separate from the curated example checks.

The [N-body REPL demo](../commands/repl/examples/README.md) loads the unchanged
C shootout program. Discover its static functions, inspect their source, and
call them while examining the bodies' fields:

```sh
./x2c repl < commands/repl/examples/nbody.repl
```

## Love: values, data, and methods

- [Values](love/values.x): dynamic values, operators, type inspection, and C calls.
- [Strings](love/strings.x): transform, slice, parse, interpolate, and iterate text.
- [Symbols](love/symbols.x): a named state and an ordered vocabulary.
- [Lists](love/lists.x): shared tails, transformations, and nested templates.
- [Arrays](love/arrays.x): update scores, copy and rank them, then fold a slice.
- [Maps](love/maps.x): stock quantities, missing keys, and stored zero values.
- [Literals](love/literals.x): describe a workshop with nested collections.
- [Files](love/files.x): read a whole file, then stream and total its rows.
- [Methods](love/methods.x): define, allocate, and move a Point.

## Power: put the pieces together

- [Counting](power/counting.x): count words and rank them by frequency.
- [Indexing](power/indexing.x): build and query an index of document words.
- [Scopes](power/scopes.x): reclaim each file's working storage and each day's
  file list; verify cleanup on normal exit, return, and exception.
- [Match](power/match.x): simplify nested code using patterns and templates.
- [Threads](power/threads.x): square two copied batches and combine their sums.
- [Channel word count](power/channel-word-count.x): stream filenames and Maps
  through bounded channels in one supervised batch. Strings use the shared
  process canonical pool; each result Map transfers explicitly.
- [Channel service](power/channel-service.x): send requests with reply channels.
  The service and its clients finish together under `Thread.run`.
- [Exceptions](power/exceptions.x): close a file before handling a failed read.
- [Generics](power/generics.x): count response codes with typed collections.
- [Imports](power/imports.x): use PCRE2 to extract named request fields.
  This example needs optional package dependencies and is checked separately.

After `make examples`, try Threads directly from the repository root:

```sh
./examples/build/power-threads/threads
```

It runs two workers and prints their combined sum of squares:

```text
sum of squares: 91
```

## Magic: extend and evaluate the language

- [Operators](magic/operators.x): define set union and intersection with a Map.
- [Macros](magic/macros.x): swap integers or strings with one typed macro.
- [Decorators](magic/decorators.x): trace a function's entry and exit.
- [Keywords](magic/keywords.x): release a mutex when an exception leaves a block.
- [Compile-time tables](magic/compile-time.x): generate two arrays from one table.
- [Runtime Lisp](magic/runtime.x): evaluate two policies using a native binding.
- [Agreement](magic/ways-to-agree.x): build the same List four different ways.
- [Self-hosting](magic/selfhost.md): rebuild the compiler and inspect its syntax.

## Further examples

These programs explore additional uses of the language; they are separate
from the gallery examples.

- Values and text: [conversions](love/conversions.x),
  [concatenation](love/string-concatenation.x),
  [symbol forms](love/symbol-forms.x), [symbol sets](love/symbol-sets.x),
  [basic literals](love/basic-literals.x), and [List methods](love/list-methods.x).
- Commands and files: [line counts](scripts/line-counts.x) runs parallel
  commands and pipelines and manages a scratch tree with `process.x` and
  `path.x`; [parallel jobs](scripts/parallel-jobs.x) caps concurrency with
  `Job.wait_any` and reports failing commands.
- Collections and execution: [collection indexing](power/collection-indexing.x),
  [word-count summary](power/word-count-summary.x),
  [shared worker state](power/shared-threads.x),
  [Context export](power/contexts.x), and iterator recipes for
  [data](power/iterators.x), [math](power/math.x), and [finance](power/finance.x).
- Language extensions: [protocol defaults](magic/protocols.x),
  [lambdas](magic/lambdas.x), [imported macros](magic/imported-macros.x),
  [stacked decorators](magic/stacked-decorators.x),
  [range and swap keywords](magic/range-and-swap.x), and
  [an external Lisp policy](magic/file-policy.x).

```sh
./x2c run examples/power/word-count-summary.x -- examples/data/docs-words.txt
./x2c run examples/magic/file-policy.x -- examples/magic/policy.xlisp
```

The [tic-tac-toe game](magic/tic-tac-toe.x) runs an editable
[Lisp opponent](magic/tic-tac-toe.xlisp). Play as X; the script chooses O's
moves through native board queries. Reuse the executable after editing it:

```sh
./x2c build --output /tmp/tic-tac-toe examples/magic/tic-tac-toe.x
/tmp/tic-tac-toe examples/magic/tic-tac-toe.xlisp
```

The [Greet example](power/greet-client.x) imports the small teaching package in
[packages/greet](packages/greet/). The ordinary runner builds that package
and applies [greet-client.flags](power/greet-client.flags).

The [package examples](packages/README.md) cover creating and using packages,
with links to every maintained adapter's build and run instructions. The
[HTTP and JSON example](packages/http-json-releases/) combines libcurl and
yyjson. Its optional check needs prepared dependencies:

```sh
make -C examples/packages/http-json-releases test
```

## Larger programs and tours

[programs/literate-lisp.x](programs/literate-lisp.x) is a self-contained
recursive Lisp interpreter written in ordinary x2c. Its reader, closures,
evaluator, native bindings, and standard library live in that one file.
It runs without an initialization file:

```sh
./x2c run examples/programs/literate-lisp.x -- --selftest
./x2c run examples/programs/literate-lisp.x -- \
  examples/data/reference-lisp/showcase.xlisp
```

The [source walkthrough](../docs/src/internals/reference-lisp.md) explains
its representation and compatibility rules. The optional comparison against
the production Lisp is available with:

```sh
./x2c script examples/programs/check-reference-lisp --build
```

[programs/lisp.x](programs/lisp.x) is an interactive Lisp shell. Run it from
the repository root:

```sh
./x2c run examples/programs/lisp.x
./x2c run examples/programs/lisp.x -- -e '(def id (lambda (x) x)) (id 42)'
./x2c run examples/programs/lisp.x -- program.xlisp
```

It loads `etc/init.xlisp` by default; `--init FILE` or `X2C_LISP_INIT` selects
another environment. The default includes the core `List`, `Array`, `Map`,
`String`, `Iter`, `Var`, and `Symbol` operations, file operations, and
small list algorithms.

[programs/mandelbrot.x](programs/mandelbrot.x) renders a deep zoom on native
threads. [tours/language.x](tours/language.x) is a broader language tour;
[tours/field-guide.x](tours/field-guide.x) is a short script that introduces
x2c to C programmers one small feature at a time;
[tours/hello-worlds.x](tours/hello-worlds.x) finds twelve ways to say hello.

The [language shootout](shootout/README.md) keeps fourteen problems, each
with two x2c implementations and C/Python references. Its optional timing
suite remains separate from the teaching examples:

```sh
make shoot-run
```

## Checking the examples

[manifest.txt](manifest.txt) lists each teaching `.x` source, excluding the
separately maintained shootout and package sources. Ordinary examples build
and run, require a zero exit status and empty stderr, and compare stdout with
an expected result. Imports is marked optional because it requires PCRE2.
Map traversal order is unspecified, so its output is compared without
requiring a particular line order.

Rows have six pipe-separated fields:

```text
name|category|check|arguments|stdout|note
```

`name` is a relative path without `.x`, such as `power/counting`. Expected
output paths are relative to this directory. An optional `<name>.flags` file
supplies additional build options. Runtime fixtures live under
`data/<name-with-slashes-replaced-by-hyphens>/`.

The slide Markdown owns each synchronized gallery program. After editing it, run
`tools/check-gallery-examples --update` to copy its complete code
into the standalone example, then run `make examples`. The check rejects a
missing slide mapping, missing source, or any difference, including hidden
assertions. The self-hosting guide keeps the same shell recipe but is not
executed by this suite because it rebuilds and installs the compiler.

Registry entries with `source` name an existing repository-relative program.
The check verifies its file and slide link without copying the slide over it.
Autodiff's three-mode example runs through `make -C packages/autodiff check`;
the shorter loop on its slide is not compiled. Package excerpts link to their
package-owned examples, whose execution and external setup stay in each
package's `run` or `verify` targets. `--update` never writes these
independent sources.

The optional PCRE2 Imports program is built, run, and compared with its
expected output by `make -C packages/pcre2 run`, also included in
`make packages-check`.

Generated files stay under ignored `build/`. Normal checks never rewrite
expected output. For an intentional output change, use `make examples-update`
and review the resulting differences.

## A notes service

[apps/notes](apps/notes/README.md) serves a browser page and a JSON API for
creating, editing, searching, tagging, and deleting notes. SQLite preserves
notes across restarts. From the repository root:

```sh
make -C examples/apps/notes prepare
make -C examples/apps/notes run
```

The application prints its local URL. Run its external HTTP checks with
`make -C examples/apps/notes check`. This optional application uses the SQLite
package and is separate from `make examples`. Its
[read-load tool](apps/notes/bench/README.md) measures the running service.
