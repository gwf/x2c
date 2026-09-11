# x2c packages

These optional packages make C libraries available through x2c types and
methods while preserving access to their native APIs. Choose a package for
its examples, then follow its README to prepare dependencies and run it.
Package builds are tested on macOS. Torch also has Linux x86_64 CPU coverage.

| Package | What it provides |
| --- | --- |
| [PCRE2](pcre2/README.md) | Regular expressions, captures, and replacement |
| [yyjson](yyjson/README.md) | JSON documents, parsing, and writing |
| [SQLite](sqlite/README.md) | Databases, prepared parameters, and copied row Lists |
| [libcurl](libcurl/README.md) | HTTP requests and transfers |
| [termbox2](termbox2/README.md) | Interactive terminal applications |
| [BLIS](blis/README.md) | Matrix and vector operations |
| [libuv](libuv/README.md) | Event loops, processes, files, and networking |
| [raylib](raylib/README.md) | Images, charts, and optional desktop windows |
| [C*](cstar/README.md) | Function contracts and proofs checked by the C* symbolic executor |
| [torch](torch/README.md) | Tensors, autograd, modules, optimizers, checkpoints, and TorchScript over libtorch |

torch links libtorch dynamically, so its programs are not self-contained;
its README explains the required runtime libraries. C* is a verification
experiment: its core toolchain is closed source, it is macOS arm64 only,
and it stays outside `make packages` and `make packages-check`.

SQLite is prepared and checked separately:

```sh
make -C packages/sqlite prepare
make -C packages/sqlite test run run-lisp
```

From the repository root, build x2c, the other eight library packages, and their standard example
executables without running tests:

```sh
make packages
./packages/termbox2/builds/game-of-life
```

The first build fetches and prepares pinned dependencies in the shared cache.
Existing dependency hash and profile verification remains part of preparing
usable packages. The standard raylib examples use its headless profile;
a desktop window remains an explicit `make -C packages/raylib run-interactive`.

To report prerequisites without building or downloading anything:

```sh
./configure --packages
```

`make configure-packages` runs the same report; `make packages` runs it
before building x2c or native dependencies. To check only Game of Life's
package, use `./configure --packages termbox2`.

The report lists missing commands together and gives Fedora installation
commands. Core compilation needs a C compiler, `ar`, Make, Python 3, and Bash.
Package builds additionally check their own profile tools, such as `shasum`
and BLIS's `jq`. Preparation tools are required only when the selected native
dependency is not already cached and no native prefix override was supplied.
For example, a fresh OpenSSL build needs Perl's `FindBin` and `IPC::Cmd`
modules; fresh libuv needs Autotools. Dependency preparation also checks these
requirements before downloading sources when invoked directly.

On macOS, install the Xcode command-line tools and use Homebrew for missing
Python, Autotools, or `jq`. On Fedora, the report names the packages to install;
`perl-Digest-SHA` supplies `shasum`, `perl-FindBin` supplies `FindBin`, and
`perl-IPC-Cmd` supplies `IPC::Cmd`. The report checks availability rather than
compiling capability probes; native configure scripts retain platform checks.
Terminal validation requires Expect, but build-only reports do not require it.

To build just Game of Life after building x2c:

```sh
make -C packages/termbox2 short-example
./packages/termbox2/builds/game-of-life
```

`make packages-check` runs the optional package tests and example checks;
it is separate from normal compiler checks. Its terminal checks require
Expect. Expect is not needed to build packages or run Game of Life
interactively. See
[using packages](../docs/src/guide/packages.md) for imports and
[wrapping C libraries](../docs/src/guide/wrapping-c-libraries.md) for writing
an adapter.

## The applications

Each package carries a short application and a broader one, and the three
with a value-oriented Lisp surface carry a Lisp one. Libuv also carries four
focused reports for thread notification, TCP, named pipes, and UDP. `make
short-example`, `make example`, and `make lisp-example` build them; `make run`
runs every standard application for that package.

- [pcre2/examples/parse-log.x](pcre2/examples/parse-log.x): short. Named captures and `Regexp.split`
  summarize a syslog batch in 35 lines.
- [pcre2/examples/request-report.x](pcre2/examples/request-report.x): broad. Compiled expressions, named and
  numbered captures, iteration, aggregation, and replacement.
- [yyjson/examples/service-health.x](yyjson/examples/service-health.x): short. Reads a JSON file, reports the
  unhealthy services, and writes the failures back out in 24 lines.
- [yyjson/examples/release-catalog.x](yyjson/examples/release-catalog.x): broad. Lossless document views, ordered
  and duplicate object members, exact numeric intent, explicit x2c-value
  conversion, Patch, and serialization.
- [libcurl/examples/page-titles.x](libcurl/examples/page-titles.x): short. Fetches three pages and prints
  their titles in 24 lines.
- [libcurl/examples/endpoint-report.x](libcurl/examples/endpoint-report.x): broad. Surveys six endpoints with
  GET, HEAD, and POST, then downloads an artifact straight to a file.
- [termbox2/examples/game-of-life.x](termbox2/examples/game-of-life.x): short. Conway's life on the terminal.
- [termbox2/examples/incident-filter.x](termbox2/examples/incident-filter.x): broad. A filtered incident list with
  per-severity colour, mouse selection, resize, and Unicode column widths.
- [blis/examples/page-rank.x](blis/examples/page-rank.x): short. Power iteration where the whole
  algorithm is `rank = links * rank` normalized until it converges.
- [blis/examples/risk-report.x](blis/examples/risk-report.x): broad. Column views, mixed storage and
  computation precision, and a destination-mutating `gemm`.
- [libuv/examples/process-report.x](libuv/examples/process-report.x): short. Two children, piped stdin, exit
  status.
- [libuv/examples/thread-notify.x](libuv/examples/thread-notify.x): an x2c `Thread` wakes the loop and exports
  its result through `Thread.join`.
- [libuv/examples/network-report.x](libuv/examples/network-report.x): three loopback TCP clients exchange
  copied binary data and observe EOF.
- [libuv/examples/ipc-report.x](libuv/examples/ipc-report.x): a named-pipe client and server exchange one
  binary report through a unique filesystem path.
- [libuv/examples/datagram-report.x](libuv/examples/datagram-report.x): connected and unconnected UDP preserve
  empty, binary, and deliberately truncated datagrams.
- [libuv/examples/release-checks.x](libuv/examples/release-checks.x): broad. Four supervised checks with
  deadlines, working directories, and environments; one times out, and the
  resulting artifacts are read asynchronously.
- [raylib/examples/climate-trends.x](raylib/examples/climate-trends.x): short. A deterministic PNG chart with
  no GPU and no display.
- [raylib/examples/texture-sheet.x](raylib/examples/texture-sheet.x): broad. Loads tiles, filters their pixels
  as x2c values, composites a sheet, and refuses an unreadable file.
- [raylib/examples/chart.x](raylib/examples/chart.x) and [raylib/examples/live-chart.x](raylib/examples/live-chart.x): shared chart
  drawing and its optional desktop-window front end. The package checks compile both;
  only `make run-interactive` launches the window.
- [pcre2/examples/inline-lisp.x](pcre2/examples/inline-lisp.x), [yyjson/examples/inline-lisp.x](yyjson/examples/inline-lisp.x), and
  [libcurl/examples/inline-lisp.x](libcurl/examples/inline-lisp.x): each installs its package's Lisp surface
  into a session and drives it.
- [http-json-releases](../examples/packages/http-json-releases/http-json-releases.x):
  two packages in one program, importing libcurl and yyjson and linking both
  archives.

termbox2, blis, libuv, and raylib provide x2c interfaces but no Lisp bindings.
Their objects represent native terminal state, matrices, event loops, and
images. See each package's README for ownership rules and raw API access.

## Package layout

Packages use the following layout:

- `src/<name>.x` is the entry unit named for the package. It contains the
  hand-written x2c methods, protocols, values, operators, and callback
  boundary used by normal applications, and `import "<name>"` reaches
  everything above its `#pragma private`.
- `src/<library>-<version>.h` includes the real pinned upstream header. This is
  the complete raw API, not a copied declaration or list of aliases.
- `examples/` contains both short showcases and broader applications when the
  package needs both, not ABI probes or substitutes for tests.
- `tests/` covers the x2c surface and direct use of the pinned raw API.
- `dependency.json` pins upstream source and the native build profile.
- `LICENSES/` and, when useful, a compact `PROFILE.md` or `PROFILE.json`
  retain terms and reviewed facts that cannot be replaced by a generated
  inventory.
- `Makefile` sets `PACKAGE`, includes `package.mk`, and adds the package's
  own example rules. `package.mk` builds `builds/lib<package>.a` plus the
  generated headers, objects, and `builds/<package>.link` line of extra link
  flags; tests and examples link that archive.

Opaque handle declarations and callback signatures are kept only when the C
ABI requires them. Method declarations are emitted from their x2c definitions;
packages do not maintain a second hand-written prototype list.

Applications that demonstrate two or more packages together are under
`examples/packages/`. `http-json-releases` imports libcurl and yyjson and
links both archives. Completed candidate and prerequisite research is
archived under `plans/archive/`.

## Dependency terms

x2c-owned client code, examples, tests, and specifications use
[Apache License 2.0](../LICENSE). Upstream libraries retain their own permissive terms
under each package's `LICENSES/` directory. `LICENSE-POLICY.md` defines the
intake rule for the complete compiled and distributed dependency profile,
including optional TLS, compression, graphics, and numerical backends.

## Shared dependency cache

Package Makefiles prepare their pinned dependencies through `tools/deps.py`.
By default it stores downloads, extracted source, and installed prefixes below
the clone's common Git directory, at
`$(git rev-parse --path-format=absolute --git-common-dir)/x2c-integrations`.
All worktrees of that clone therefore reuse the same completed build. The
cache keeps its older name so prefixes prepared before this tree was renamed
stay valid.

```sh
make -C packages cache-path
make -C packages prepare-checked
make -C packages/pcre2 test
make -C packages/yyjson test
```

Set `X2C_DEPS_DIR` to share another cache location across clones. A package's
package-specific prefix variable, such as `PCRE2_PREFIX`, can point at an
external installation for diagnosis. `make clean` removes only local package
outputs; it never removes the shared cache.

A dependency manifest may list local `inputs` with a `path` and `sha256`.
The helper verifies these bytes before using a cached build; the manifest's
existing cache key includes their expected hashes. Build steps can refer to
`{package}` for the manifest directory. Raylib uses this to apply its pinned
image/text patch with the ordinary `patch` command. Changing a dependency
manifest rebuilds the package and its recorded native link flags.

Build movable native bundles with `make -C packages/yyjson bundle`. See the
[package guide](../docs/src/guide/packages.md#movable-native-bundles) for
relocation, admitted profiles, compiler compatibility, and source distributions.
