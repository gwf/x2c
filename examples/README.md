# Examples

Start with [foreach.x](foreach.x), or follow the Love, Power, and Magic
examples from the landing page. Each gallery program contains the website's
code, including its normally hidden setup and assertions. The correspondence
is listed in [gallery.json](gallery.json).

After building x2c, add the repository root to PATH for this shell. Start
from the repository root:

```sh
export PATH="$PWD:$PATH"
x2c run examples/foreach.x
make examples

# Run two of the executables that make examples built.
./examples/build/foreach/foreach
./examples/build/programs-lisp/lisp
```

The Lisp shell is interactive; press Ctrl-D to exit. `make examples` builds
and checks the curated examples, leaving executables under `examples/build/`.

## Love: values, data, and methods

- [Values](love/values.x): dynamic values, operators, type inspection, and C calls.
- [Strings](love/strings.x): transform, slice, parse, interpolate, and iterate text.
- [Symbols](love/symbols.x): a named state and an ordered vocabulary.
- [Lists](love/lists.x): shared tails, transformations, and nested templates.
- [Arrays](love/arrays.x): update scores, copy and rank them, then reduce a slice.
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
- [Compile-time Lisp](magic/compile-time.x): generate two arrays from one table.
- [Runtime Lisp](magic/runtime.x): evaluate two policies using a native binding.
- [Self-hosting](magic/selfhost.md): rebuild the compiler and inspect its syntax.

## Further examples

These programs explore additional uses of the language; they are separate
from the gallery examples.

- Values and text: [conversions](love/conversions.x),
  [concatenation](love/string-concatenation.x),
  [symbol forms](love/symbol-forms.x), [symbol sets](love/symbol-sets.x),
  [basic literals](love/basic-literals.x), and [List methods](love/list-methods.x).
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
x2c run examples/power/word-count-summary.x -- examples/data/docs-words.txt
x2c run examples/magic/file-policy.x -- examples/magic/policy.xlisp
```

The [Greet example](power/greet-client.x) imports the small teaching package in
[packages/greet](packages/greet/). The ordinary runner builds that package
and applies [greet-client.flags](power/greet-client.flags).

The [package examples](packages/README.md) cover creating and using packages,
with links to all seven adapters' build and run instructions. The
[HTTP and JSON example](packages/http-json-releases/) combines libcurl and
yyjson. Its optional check needs prepared dependencies:

```sh
make -C examples/packages/http-json-releases test
```

## Larger programs and tours

[programs/lisp.x](programs/lisp.x) is an interactive Lisp shell. Run it from
the repository root:

```sh
x2c run examples/programs/lisp.x
x2c run examples/programs/lisp.x -- -e '(def id (lambda (x) x)) (id 42)'
x2c run examples/programs/lisp.x -- program.xlisp
```

It loads `etc/init.xlisp` by default; `--init FILE` or `X2C_LISP_INIT` selects
another environment. `etc/lisp-extras.xlisp` and `etc/lisp-io.xlisp` provide
optional algorithms and file operations.

[programs/mandelbrot.x](programs/mandelbrot.x) renders a deep zoom on native
threads. [tours/language.x](tours/language.x) is a broader language tour;
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

The slide Markdown owns each gallery program. After editing a slide, run
`python3 tools/check-gallery-examples.py --update` to copy its complete code
into the standalone example, then run `make examples`. The check rejects a
missing slide mapping, missing source, or any difference, including hidden
assertions. The self-hosting guide keeps the same shell recipe but is not
executed by this suite because it rebuilds and installs the compiler.

The optional PCRE2 Imports program is built, run, and compared with its
expected output by `make -C packages/pcre2 run`, also included in
`make packages-check`.

Generated files stay under ignored `build/`. Normal checks never rewrite
expected output. For an intentional output change, use `make examples-update`
and review the resulting differences.
