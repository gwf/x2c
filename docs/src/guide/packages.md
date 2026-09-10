# Packages

x2c has one flat namespace, so an included `.x` library merges its names into
yours. A package keeps its own space. It is compiled once into an archive,
and an importing program reaches its names through an alias.

## What a package looks like

A package is a directory named for the package. Only its `src/` directory
holds package sources; everything else in the directory consumes it like any
other program.

```text
packages/greet/
  Makefile          PACKAGE := greet, then include ../package.mk
  src/greet.x       the entry unit; public surface above #pragma private
  tests/            consumers that import the package
  examples/
```

That is the whole layout for a package with no native dependency. One that
wraps a C library adds the pin, licence texts, and profile that
[Wrapping a C Library](wrapping-c-libraries.md) covers.

The entry unit needs no manifest and no export list:

```x2c
typedef struct GreetingData {
  String subject;
  int count;
} *Greeting;

Greeting Greeting.new(String subject);
String Greeting.line(Greeting greeting);

#pragma private

Greeting Greeting.new(String subject) {
  Greeting greeting = Scope.malloc(sizeof(struct GreetingData));
  greeting.subject = subject;
  greeting.count = 0;
  return greeting;
}

String Greeting.line(Greeting greeting) {
  greeting.count++;
  return %"hello, ${greeting.subject} (${greeting.count})";
}
```

`greet.x` spells its own names bare. Compiled as a package they become
`greet__Greeting`, `greet__Greeting_new`, and `greet__Greeting_line`, so a
second package may publish its own `Greeting` in the same program.

## Building one

`packages/package.mk` holds the recipe. A package Makefile is two lines:

```make
PACKAGE := greet
include ../package.mk
```

`make build` translates every `src/*.x` in package mode and produces:

```text
builds/greet.h        the generated public header
builds/libgreet.a     the archive a consumer links
builds/greet.link     the one line of extra link flags, empty when none
```

`make test` builds and runs `tests/test-*.x`, and `make clean` removes
`builds/`. A package with a pinned native dependency adds a `dependency.json`
and one more Makefile line, `DEPENDENCY_PREFIX_VAR := GREET_PREFIX`, naming
the variable that overrides the cache prefix; `make prepare` then fetches and
builds the dependency into a shared cache outside the worktree and leaves a
`deps` symlink in the package directory.

## Using one

Register the directory that holds packages and import by name:

<!-- ignore: an import needs a registered --package-dir root. -->
```x2c,ignore
import "greet" as g;

int main(void) {
  g.Greeting greeting = g.Greeting.new("x2c");
  printf("%s", %"${greeting.line()}\n");
  return 0;
}
```

```sh
x2c build --package-dir packages --output greeter greeter.x
```

The driver reads the unit's recorded dependencies, adds the package's
`builds` and `src` directories to the C include path, and links
`libgreet.a` together with the line in `greet.link`. It never rebuilds the
package. Build it once, and a read-only package tree still serves every
consumer. A target in `x2c.toml` can set `package-dirs` instead of passing
the flag.

`as` is optional; `import "greet";` binds the alias `greet`. The alias is
only a way to spell names. The generated C always uses the package's own
prefix.

Both clauses are optional and combine:

```text
import "<package>" [as <alias>] [with <Name> [as <Local>] {, ...}] ;
```

A `with` clause drops the alias from names you use often:

<!-- ignore: an import needs a registered --package-dir root. -->
```x2c,ignore
import "greet" with Greeting;             // bare Greeting
import "greet" with Greeting as Hello;    // bare Hello
import "greet" as g with Greeting;        // g.Greeting and Greeting

int main(void) {
  Greeting greeting = Greeting.new("x2c");
  printf("%s", %"${greeting.line()}\n");
  return 0;
}
```

A `with` name is still only a spelling: `Greeting.new` compiles to
`greet__Greeting_new`. Any public name works, functions included. The alias
stays registered, so `with` never takes it away, and a local variable of the
same name shadows the binding. See the
[language reference](../reference/language.md#packages-and-import) for what
does and does not cross an import.

An imported package may add a method to an external type. PCRE2, for example,
adds `Var.regexpmatch`, so `value.regexpmatch()` resolves after
`import "pcre2"`. A method declared in the consumer still wins. If two
imported packages provide the same receiver method, the call is ambiguous;
call the selected package function explicitly, such as
`pcre2.Var_regexpmatch(value)`.

That external type is often one from the package's own vendored header, which
crosses the import under its own name. raylib's `Image` and `Vector2` are
raylib's, so a consumer writes `Image.new(...)`, reads `image.width`, and uses
`a + b` with no `with` entry for either type. The types come from the header
and the methods from `raylib__`.

## Packages that wrap a C library

`packages/yyjson/` is the worked example. It publishes the vendored
`src/yyjson-0.12.h` because four of its options methods take yyjson's own flag
types, so a consumer needs the upstream header on its system include path:

```sh
make -C packages/yyjson prepare
make -C packages/yyjson build
make -C packages/yyjson test run run-lisp
x2c build --package-dir packages \
  --c-system-dir packages/yyjson/deps/include \
  --output catalog catalog.x
```

`prepare` verifies and builds the pinned native dependency. `build` creates the
package archive and link file. The three checks exercise the x2c API, example
applications, raw C header, and Lisp bindings. A program imports the ordinary
API; code that needs an unwrapped option calls yyjson's real declarations
through `yyjson-0.12.h`, and a runtime Lisp session installs the package's
group with `JsonLisp.install`. The package README states which values own
native storage and when borrowed views expire.

A source distribution carries `packages/<name>/`, including `src/`,
`dependency.json`, `LICENSES/`, its README, examples, and tests, together with
`packages/package.mk`, `packages/dependency.mk`, `packages/tools/deps.py`,
and `packages/tools/bundle.py`.
It does not carry the ignored `deps` symlink or `builds/` output. From the
repository root, produce a source archive with ordinary `tar`:

```sh
package=yyjson
tar --exclude="packages/$package/deps" \
  --exclude="packages/$package/builds" \
  -czf "$package-source.tar.gz" \
  "packages/$package" packages/package.mk packages/dependency.mk \
  packages/tools/deps.py packages/tools/bundle.py
```

The package directory includes its `Makefile`; keep any additional source
files or licenses that its build needs. Include other x2c packages it imports
in the same archive, or distribute them separately under a registered package
root. Native dependency sources are fetched and verified from
`dependency.json` during preparation.

Shared support resolves beside those files, so the bundle needs no Git
checkout. Unpack it into a directory where its sources and build outputs can
remain together. Select an installed compiler and an explicit dependency
cache. Use [the native prefix installer](installation.md) for a compiler that can
move independently of its producer checkout. A development build can instead
use the absolute path to `builds/0/x2c`; keep that compiler's support tree in
place. A package source archive does not install or bundle the compiler.

```sh
mkdir package-sources
tar -xzf yyjson-source.tar.gz -C package-sources
cd package-sources
export X2C_DEPS_DIR="$HOME/.cache/x2c-dependencies"
make -C packages/yyjson prepare build X2C=/path/to/x2c
```

Register the directory containing the package with `--package-dir`. Native
compilation and archiving use the same driver actions and retained state as
ordinary builds, keeping the generated public headers, archive, and link flags
together. Package tests that include `unittest/test-support.x` still need that
repository test support; it is not part of the source-package build contract.

A package over a third-party C library also has to decide what to expose, who
owns each returned value, how to preserve the library's error codes, and
whether to provide Lisp bindings. That is [Wrapping a C
Library](wrapping-c-libraries.md).

### Package examples

The packages include example applications that use their x2c interfaces
without requiring public services:

- `packages/sqlite/examples/observations.x` stores readings and queries slow
  or failed responses. `observation-history.x` imports a file batch in one
  transaction, then reopens the database and reports endpoint history.
- `packages/libcurl/examples/page-titles.x` fetches pages concurrently with
  `CurlEasy.get_all`; `endpoint-report.x` handles each batch response or Error
  independently, then uses the ordinary single-request operations. Batch
  results keep input order and borrow their lifetime from `CurlBatch`.
  The call stays on the caller's thread; the pinned resolver can still block
  during DNS lookup. `examples/packages/http-json-releases/`
  composes libcurl's response bytes with yyjson parsing.
- `packages/termbox2/examples/incident-filter.x` handles terminal input and
  rendering. Its standard run is driven through a pseudo-terminal.
- `packages/blis/examples/page-rank.x` expresses PageRank with BLIS operators;
  `risk-report.x` shows the broader matrix workflow.
- `packages/libuv/examples/process-report.x` supervises child processes;
  `thread-notify.x`, `network-report.x`, `ipc-report.x`, and
  `datagram-report.x` exercise wakeups, TCP, named pipes, and UDP; and
  `release-checks.x` reads produced artifacts through asynchronous files.
- raylib's standard examples render PNG files in memory. Use
  `run-interactive` for the windowed showcase; package checks do not run it.
- `packages/torch/examples/fit-line.x` fits a line by gradient descent
  through libtorch autograd: `x @ w + b`, `backward`, and an in-place update
  under `Torch.no_grad`, with every operator temporary reclaimed by the
  step's `Scope`. `mlp.x` trains a composed model with Adam and reloads it
  from a checkpoint; `mnist.x` trains a convolutional network for one epoch
  on the MNIST files named by `TORCH_MNIST`; and `jit-infer.x` runs a
  TorchScript model exported from Python.
  [Training and Inference with torch](torch.md) is the chapter for the
  package.

Run the package-local examples from the repository root:

```sh
make -C packages/libcurl run
make -C examples/packages/http-json-releases test
make -C packages/termbox2 run
make -C packages/blis run
make -C packages/libuv run
make -C packages/raylib verify
make -C packages/torch run
```

### SQLite rows and transactions

The SQLite package keeps SQL visible while accepting ordinary x2c values.
`Database.open` creates a file-backed or `":memory:"` connection. Prepare a
statement once, bind a positional List or a Map of exact parameter names,
and iterate copied row Lists. Rows preserve column order and duplicate names;
`Statement.columns` returns the names separately. Free statements before
closing their connection, with `defer` beside each acquisition.

<!-- ignore: an import needs a registered --package-dir root. -->
```x2c,ignore
import "sqlite" with Database, Statement;

void show_readings(String filename) {
  Database db = Database.open(filename);
  defer db.close();
  Statement query = db.prepare(
    "SELECT url, status FROM observation WHERE status >= ? ORDER BY url"
  );
  defer query.free();
  query.bind(%(400));
  foreach (List row, query)
    printf("%s", %"${row[0]}: HTTP ${row[1]}\n");
}
```

SQL NULL is `Var.null()`, distinct from exhausted iteration. Integers retain
SQLite's signed 64-bit domain; oversized unsigned inputs raise `conv-range`.
Text becomes `String`, while blobs and text containing NUL become copied
`Bytes`. These values survive later steps and statement release within their
ordinary x2c lifetimes. `db.transaction(%!() => { ... })` commits on success and
rolls back on Error; nested managed transactions are rejected. SQLite's own
code, message, and operation remain available in Error details.

`SqliteLisp.install` adds query, execute, NULL, and byte-list operations to an
embedded Lisp session. Each query or execute call opens its own connection,
so use a database filename to retain changes between calls. Query results are
ordinary nested Lists. The complete pinned raw SQLite API and the same native
handles remain available for advanced operations. See
`packages/sqlite/README.md` for ownership, the admitted native profile, and
the executable examples. SQLite is verified on macOS and checked separately:

```sh
make -C packages/sqlite prepare
make -C packages/sqlite test run run-lisp
```

## Movable native bundles

`make bundle` builds a package and assembles its public source interfaces,
generated headers, wrapper archive, licenses, and declared native headers and
static libraries:

```sh
make -C packages/yyjson bundle
mkdir native-packages
tar -xzf packages/yyjson/builds/bundle/yyjson-native.tar.gz -C native-packages
x2c build --package-dir native-packages app.x --output app
```

The directory `packages/yyjson/builds/bundle/yyjson` is also directly usable;
register its parent with `--package-dir`. `BUNDLE_DIR=/path/to/output` changes
the output parent. The directory and archive contain the same files. Move the
whole package directory, keeping `src`, `builds`, `native`, and licenses
together. Extracted bundle, compiler, header/archive, and consumer paths may
contain spaces. Producing packages still follows the existing Make path
restrictions; this does not promise arbitrary spaces in native build/cache
paths.

A bundle is static and specific to its host platform, architecture, native
profile, and matching x2c compiler/runtime. `BUNDLE.json` records those build
identities. Native dependency toolchain information comes from its existing
cache receipt when available; an explicit external prefix may have no receipt.
A bundle does not promise an ABI across compiler releases, cross-platform
execution, shared-library relocation, or automatic dependency resolution.
Native system libraries and frameworks remain supplied by the host.

Bundles carry `builds/<name>.native.rsp`. The compiler reads its quoted native
arguments, expands the literal `{package}` to the resolved package directory,
and applies C include/define options during native compilation and ordered
archives/system options during final linking. Arguments remain individual argv
values even when an expanded path contains spaces. They are not shell commands
and `@` does not expand another response file. Definitions do not change the
preceding x2c source preprocessing. A new bundle needs a compiler supporting
this format; older source packages continue using their existing `.link` file.

Native bundle metadata covers yyjson, PCRE2, BLIS, libuv, termbox2,
libcurl, and raylib. SQLite remains separately distributed as source in this
release.
Pure and mixed C/x2c packages with no external native inputs need no dependency
manifest; their bundle carries an empty native response file. Distribute any
other x2c package imports alongside them under the registered package root.

Libcurl bundles include its pinned OpenSSL static inputs in link order. Host
certificate configuration remains the admitted profile's system certificate
bundle; native bundling does not introduce a certificate store.

Raylib also requires its native type declarations during x2c source discovery.
Use the existing source include option for its bundled headers:

```sh
x2c build --package-dir native-packages \
  --x-include-dir native-packages/raylib/native/include chart.x --output chart
```

The default raylib bundle uses the headless profile. To produce its separately
admitted macOS desktop profile, select its dependency manifest explicitly:

```sh
make -C packages/raylib clean-builds
make -C packages/raylib bundle DEPENDENCY_MANIFEST=dependency-desktop.json
```

Prepare and validate the selected native profile before distributing it. The
bundle target preserves existing dependency checksum, header, and license
checks through the ordinary package build; consumer builds do not download
missing inputs.

### Declare a package's native distribution

The optional `distribution` object in `dependency.json` lists selected files
and directories with the existing `copies` shape and ordered native arguments:

```json
"distribution": {
  "copies": [
    {"from": "{prefix}/include/yyjson.h",
     "to": "native/include/yyjson.h"},
    {"from": "{prefix}/lib/libyyjson.a",
     "to": "native/lib/libyyjson.a"}
  ],
  "native_args": [
    "--c-system-dir", "{package}/native/include",
    "{package}/native/lib/libyyjson.a"
  ]
}
```

Copy sources expand `{prefix}` to the prepared native prefix and `{package}`
to the producer package. Destinations are relative to the bundle. Native
arguments retain `{package}` for consumer-time expansion. An optional
`platform_args` object appends arguments keyed by the producer's platform
(`darwin` or `linux`) when a shared dependency manifest has platform-specific
system requirements. The manifest selected by the package Makefile remains
the native profile owner.

Accepted options are native include directories (`-I`, `--c-include-dir`,
`--c-system-dir`), `-D`, `-U`, `-L`, `-l`, archive inputs, `-pthread`, and
`-framework <name>`. Keep native archives in dependency order after the wrapper
archive. Options that replace the consumer's output, command, or tools and
unrestricted compiler/linker escape options are not package metadata.
