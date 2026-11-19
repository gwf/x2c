# Examples

These programs show x2c at work, from a three-line loop to a Lisp
interpreter. Most run with a plain `x2c run`; a source that needs more
names its command in its header. Run the commands on this page from the
directory that holds `examples/`: the root of a repository checkout, or an
installed prefix such as `~/.local/x2c`. In a checkout, write `./x2c` for
the compiler you built there.

```sh
x2c run -q examples/foreach.x
```

## Start here

1. [x2c essentials](tours/essentials/) introduces values, sharing, quoting,
   classes, operators, patterns, lifetime, compile-time code, and threads.
2. [Language walkthrough](tours/language/) progresses through values, text,
   collections, iteration, functions, methods, classes, operators, patterns,
   lifetime and errors, compile-time code, and threads and channels.

Each lesson is a standalone program. For example:

```sh
x2c run examples/tours/essentials/sharing.x
x2c run examples/tours/language/collections.x
```

The [book's language guide](../docs/src/SUMMARY.md) supplies the full rules,
including source organization and optional indentation syntax. The Love,
Power, and Magic examples below explore individual features in more detail.

## Love: values, data, and methods

- [Values](love/values.x): runtime-generic functions and contained-type inspection.
- [Symbols](love/symbols.x): named values without declarations or C identifier conflicts.
- [Strings](love/strings.x): content equality, immutable transformations,
  slicing, and interpolation.
- [Lists](love/lists.x): shared tails, transformations, and nested
  templates.
- [Arrays](love/arrays.x): update scores, copy and rank them, then fold a
  slice.
- [Maps](love/maps.x): stock quantities, missing keys, and stored zero
  values.
- [Literals](love/literals.x): describe a workshop with nested collections.
- [Loops](love/loops.x): walk collections, text lines and words, and file lines.
- [Files](love/files.x): read a whole file, then stream and total its rows.
- [Methods](love/methods.x): define, allocate, and move a Point.

- [Memory](power/scopes.x): manage individual values, allocation regions,
  and retained allocation destinations with `auto`.

## Power: put the pieces together

- [Classes](power/classes.x): define a Color and use generated equality,
  printing, Map keys, and Arrays of values.
- [Counting](power/counting.x): count words and rank them by frequency.
- [Indexing](power/indexing.x): build and query an index of document words.
- [Destructuring](power/destructuring.x): name tuple fields and select orders with a pattern condition.
- [Match](power/match.x): simplify nested code using patterns and templates.
- [Threads](power/threads.x): square two copied batches and combine their
  sums.
- [Exceptions](power/exceptions.x): close a file before handling a failed
  read.
- [Imports](power/imports.x): use PCRE2 to extract named request fields.
  This example needs the PCRE2 package; its header gives the commands.

Files, Counting, and Exceptions read the checked-in files under
[data](data/) by default. Files and Counting also accept an input file;
Exceptions accepts a directory holding `document.txt` and `document.bin`:

```sh
x2c run -q examples/power/counting.x -- examples/data/docs-words.txt
```

## Magic: extend and evaluate the language

- [Runtime Lisp](magic/runtime.x): share x2c values and native functions
  with editable Lisp policies.
- [Shipped macros](magic/derive.x): derive nested record conversions,
  equality, and printing.
- [Templates](magic/macros.x): generate JSON writer and reader functions.
- [Decorators](magic/decorators.x): trace a function's entry and exit.
- [Keywords](magic/keywords.x): release a mutex when an exception leaves a
  block.
- [Extensions](../packages/x2cui/examples/counter.x): import UI notation from
  x2cui, an optional source-only package.
- [Meta](magic/fields.x): inspect fields and generate statements at compile time.
- [Compile-time code](magic/compile-time.x): build array setup code
  incrementally from one table.
- [Autodiff](../packages/autodiff/examples/energy-gradient.x): generate
  derivative code from a function.
- [Operators](magic/operators.x): define set union and intersection with a Map.
- [Agreement](magic/ways-to-agree.x): build the same List four different ways.
- [Self-hosting](magic/selfhost.md): rebuild the compiler and inspect its
  syntax. These commands need a checkout.

## More programs

- Values and text: [conversions](love/conversions.x),
  [concatenation](love/string-concatenation.x),
  [symbol forms](love/symbol-forms.x), [symbol sets](love/symbol-sets.x),
  [basic literals](love/basic-literals.x), and
  [List methods](love/list-methods.x).
- Names and arguments: [bindings](power/bindings.x) names a value five ways;
  [List rest](power/list-rest.x) and [Map rest](power/map-rest.x) pass
  variable and keyword arguments; [derive](magic/derive.x) generates record
  mappings, equality, and representation.
- Collections and execution:
  [collection indexing](power/collection-indexing.x),
  [word-count summary](power/word-count-summary.x),
  [shared worker state](power/shared-threads.x),
  [Context export](power/contexts.x),
  [channel word count](power/channel-word-count.x),
  [channel service](power/channel-service.x), and iterator recipes for
  [data](power/iterators.x), [math](power/math.x), and
  [finance](power/finance.x).
- Language extensions: [protocol defaults](magic/protocols.x),
  [lambdas](magic/lambdas.x), [meta functions](magic/meta-functions.x),
  [system macros](magic/system-macros.x),
  [imported macros](magic/imported-macros.x),
  [stacked decorators](magic/stacked-decorators.x),
  [range and swap keywords](magic/range-and-swap.x), and
  [an external Lisp policy](magic/file-policy.x).
- Commands and files: [line counts](scripts/line-counts.x) runs parallel
  commands and pipelines and manages a scratch tree;
  [parallel jobs](scripts/parallel-jobs.x) caps concurrency with
  `Job.wait_any` and reports failing commands; [wc](programs/wc) prints the
  ten most frequent words in a file.

```sh
x2c run -q examples/power/word-count-summary.x -- examples/data/docs-words.txt
x2c run -q examples/magic/file-policy.x -- examples/magic/policy.xlisp
x2c script examples/programs/wc examples/data/docs-words.txt
```

The [tic-tac-toe game](magic/tic-tac-toe.x) runs an editable
[Lisp opponent](magic/tic-tac-toe.xlisp). Play as X; the script chooses O's
moves through native board queries. Build it once, then edit the Lisp file
and play again without rebuilding:

```sh
x2c build -q --output /tmp/tic-tac-toe examples/magic/tic-tac-toe.x
/tmp/tic-tac-toe examples/magic/tic-tac-toe.xlisp
```

## Larger programs

[programs/literate-lisp.x](programs/literate-lisp.x) is a self-contained
recursive Lisp interpreter written in ordinary x2c. Its reader, closures,
evaluator, native bindings, and standard library live in that one file. The
[source walkthrough](../docs/src/internals/reference-lisp.md) explains its
representation and compatibility rules.

```sh
x2c run -q examples/programs/literate-lisp.x -- --selftest
x2c run -q examples/programs/literate-lisp.x -- \
  examples/data/reference-lisp/showcase.xlisp
```

[programs/lisp.x](programs/lisp.x) is an interactive shell for the x2c Lisp
runtime; press Ctrl-D to exit. It loads `etc/init.xlisp` by default;
`--init FILE` or `X2C_LISP_INIT` selects another environment. The default
includes the core `List`, `Array`, `Map`, `String`, `Iter`, `Var`, and
`Symbol` operations, file operations, and small list algorithms.

```sh
x2c run -q examples/programs/lisp.x
x2c run -q examples/programs/lisp.x -- -e '(def id (lambda (x) x)) (id 42)'
x2c run -q examples/programs/lisp.x -- program.xlisp
```

[Tiny Lisp](programs/tiny-lisp.md) implements one eight-form language three
ways: compact, code golf, and fully annotated. Each reads a program from
standard input:

```sh
x2c run -q examples/programs/tiny-lisp.max.x < examples/data/tiny-lisp.slp
```

[programs/mandelbrot.x](programs/mandelbrot.x) renders a deep zoom on native
threads. It writes `mandelbrot.ppm` in the working directory, or the path
given as its first argument.

The [c2x2c tutorial](c2x2c/README.md) follows nine versions of a word
counter, from native C to parallel directory counting.

[apps/notes](apps/notes/README.md) serves a browser page and a JSON API for
creating, editing, searching, tagging, and deleting notes. SQLite preserves
notes across restarts.

The [package examples](packages/README.md) cover creating and using
packages, with links to every maintained adapter's build and run
instructions. The [Greet example](power/greet-client.x) imports the small
teaching package in [packages/greet](packages/greet/). Outside a checkout,
install that package first with `x2c install greet`.

The [Benchmarks Game suite](shootout/README.md) adopts ten Benchmarks Game
problems, with two x2c variants and up to six contributed reference
languages. See the [current results and charts](shootout/results/README.md).

## Working in a checkout

The commands in this section use the repository's `make` targets, which an
installed prefix does not include. Run them from the repository root.

`make examples` builds and checks the curated examples, leaving executables
under `examples/build/`:

```sh
make examples
./examples/build/power-threads/threads
./examples/build/programs-lisp/lisp
```

Files, Counting, and Exceptions find their default data relative to their
source path, which `x2c run` supplies. Give the executables under
`examples/build/` their input explicitly:

```sh
./examples/build/love-files/files examples/data/love-files/quantities.txt
```

The Greet example needs its package built first:

```sh
make -C examples/packages/greet build
./x2c run -q --package-dir examples/packages examples/power/greet-client.x
```

The [N-body REPL demo](../commands/repl/examples/README.md) loads the
unchanged C shootout program. Discover its static functions, inspect their
source, and call them while examining the bodies' fields. The REPL is one
of the commands `make commands` builds:

```sh
make commands
./x2c repl < commands/repl/examples/nbody.repl
```

Notes uses the SQLite package. Prepare it, then run the server or its HTTP
checks; the server prints its local URL. Its
[read-load tool](apps/notes/bench/README.md) measures the running service.

```sh
make -C examples/apps/notes prepare
make -C examples/apps/notes run
make -C examples/apps/notes check
```

The HTTP and JSON example combines libcurl and yyjson. Its optional check
needs prepared dependencies:

```sh
make -C examples/packages/http-json-releases test
```

Compare the literate Lisp with the production Lisp, or run the shootout's
optional timing suite:

```sh
./x2c script examples/programs/check-reference-lisp --build
make shoot-run
```

### Checking the examples

[manifest.txt](manifest.txt) lists each teaching `.x` source, excluding the
separately maintained shootout and package sources. Ordinary examples build
and run, require a zero exit status and empty stderr, and compare stdout
with an expected result. Imports is marked optional because it requires
PCRE2. Map traversal order is unspecified. Examples use named lookups or
sorted keys when their printed output needs a fixed order.

Rows have six pipe-separated fields:

```text
name|category|check|arguments|stdout|note
```

`name` is a relative path without `.x`, such as `power/counting`. Expected
output paths are relative to this directory. An optional `<name>.flags` file
supplies additional build options. Runtime fixtures live under
`data/<name-with-slashes-replaced-by-hyphens>/`.

The slide Markdown owns each synchronized gallery program. After editing
it, run `tools/check-gallery-examples --update` to copy its complete code
into the standalone example, then run `make examples`. The check rejects a
missing slide mapping, missing source, or any difference, including hidden
assertions. The self-hosting guide keeps the same shell recipe but is not
executed by this suite because it rebuilds and installs the compiler.

Registry entries in [gallery.json](gallery.json) with `source` name an
existing repository-relative program. The check verifies its file and slide
link without copying the slide over it. Autodiff's three-mode example runs
through `make -C packages/autodiff check`; the shorter loop on its slide is
not compiled. Package excerpts link to their package-owned examples, whose
execution and external setup stay in each package's `run` or `verify`
targets. `--update` never writes these independent sources.

The optional PCRE2 Imports program is built, run, and compared with its
expected output by `make -C packages/pcre2 run`, also included in
`make packages-check`.

Generated files stay under ignored `build/`. Normal checks never rewrite
expected output. For an intentional output change, use
`make examples-update` and review the resulting differences.
