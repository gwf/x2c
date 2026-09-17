# Command-line interface

After building the repository, `./x2c` links to the development compiler;
`./bin/x2c` is the bootstrap compiler until `make build-install` links it to
a copy of the development compiler. Every invocation begins with a command:
`translate`, `build`, `run`, `new`, `script`, `bootstrap`, `env`, `install`,
`remove`, `list`, or `help`.

The generated help is the short option reference:

```sh
./x2c --help
./x2c help translate
./x2c build --help
./x2c run --help
./x2c script --help
./x2c bootstrap --help
```

## Translate to C

`translate` writes one matching `.c`, `.h`, `.xi`, and default `.d` file for
each explicit `.x` input. The `.xi` file is the unit's
[interface](../internals/architecture.md), which later translations read in
place of its source when it is current:

```sh
mkdir -p /tmp/x2c-generated
./x2c translate --out-dir /tmp/x2c-generated \
  src/main.x src/parse.x
```

Without `--out-dir`, output goes to the current directory. An explicitly
selected directory must already exist. x2c validates all inputs, output
stems, and output paths before translating the first unit. Inputs must be
regular `.x` files; two inputs with the same basename would collide in the
flat output directory and are rejected.

`--out-dir` is only the generated-C directory. Native artifacts use
`build --output` or `run --output`.

`-j`, or `--jobs`, translates several units at once, in worker processes that
inherit the collected declarations the parent already read:

```sh
./x2c translate -j 8 --out-dir /tmp/x2c-generated src/*.x
```

Each unit is translated by exactly one worker and writes only its own files,
so the generated `.c` and `.h` are byte-identical to a serial run. A `.d` file
may list more prerequisites than the serial run produces, and never fewer. A
worker that parses a header records what that parse reads, where a serial run
replays the header from its process cache. The default is one job. The
inspection and dump modes stay serial; they write one ordered stream to
standard output.

The depfile options control that `.d` output. They belong to `translate`:

```text
--no-deps               Do not write x2c dependency files
--dep-file <file>       Override the depfile path (one input only)
--dep-target <target>   Override the depfile target (one input only)
--no-phony-deps         Omit phony rules for included files
```

Symbol collection options apply to `translate`, `build`, and `run`:

```text
--no-cpp                Skip symbol collection and preprocessing
--live-symbols          Collect symbols through the host preprocessor
--cpp-symbols           Use CPP collection for this translation
```

`--source-map` adds source locations to generated C for `translate`, `build`,
and `run`. It is off by default. Combine it with native debug information to
set breakpoints, step through statements, and read backtraces in the original
`.x` files:

```sh
./x2c build --source-map -g -O0 --save-temps --output /tmp/example example.x
lldb /tmp/example
```

With source mapping enabled, C `__FILE__` and `__LINE__` refer to the original
x2c source. Macro expansions use their invocation locations; generated cleanup
uses its owning source construct. Compiler scaffolding without a source origin
retains a generated-file location. `-g` alone keeps generated-C locations, and
`--source-map` alone does not add native debug information. Changing the option
invalidates reused translation output. Optimized builds may combine or remove
statements, so source mapping does not guarantee exact stepping or recovery of
optimized-away values.

On macOS, mapped executable builds with effective native debug information
also produce `<output>.dSYM` before removing temporary objects. Move that
companion directory with the executable to retain native debug information.
Symbol assembly adds time only to these requested debug links. Its failure
fails the build and retains intermediates for diagnosis. A later `-Xcc -g0`
overrides an earlier `-g`, including one selected by a project profile.
Linux keeps its existing debug output; `--build-dir` and `--save-temps` remain
available for retaining intermediate files on either platform.

Inspection modes print an intermediate result and stop translation:

```sh
./x2c translate --dump-tokens source.x
```

- `--dump-tokens` prints source tokens and stops.
- `--dump-ast` prints the parsed AST and stops.
- `--dump-transforms` prints the transformed AST and stops.
- `--dump-code` prints unformatted generated code and stops.
- `--dump-symbols` prints the source symbol table and stops.
- `--dump-cpp` prints host-preprocessed text and stops.
- `--dump-cpp-text` is an alias for `--dump-cpp`.
- `--dump-cpp-tokens` prints host-preprocessed tokens and stops.
- `--dump-cpp-symbols` prints the CPP symbol table and stops.
- `--dump-cache` prints the compiler cache and stops.
- `--dump-conformance` prints protocol conformance and stops.

An inspection that does not write generated files does not need `--out-dir`.
Only one inspection mode runs; the last option given wins.

## Build native artifacts

`build` accepts explicit `.x`, `.c`, `.o`, and `.a` operands. It translates
x2c source, compiles generated and native C, then links an executable. One
input may include another through a directory, as in
`#include "lib/inner.x"`, when both are operands:

```sh
./x2c build --output /tmp/foreach examples/foreach.x
/tmp/foreach
```

`build` and `run` default to the host's online processor count for translation
and native compilation. Detection failure falls back to one job. Under Make
(`MAKELEVEL` greater than zero), the automatic default is one job so the
outer build owns concurrency. An explicit `-j N` or `--jobs N` overrides either
default; `translate` retains its one-job default. The online count does not
account for Linux CPU affinity, container quotas, or memory limits; use `-j`
to choose a smaller limit in those environments.

Parallel builds translate each stale unit in its own worker and generated
directory. Units with the same basename remain separate, and each unit records
its own prerequisites for subsequent build reuse. Parallel translation preserves
native header search and link order.

The driver selects the runtime that matches the compiler and supplies that
runtime's platform libraries. It also derives one object and dependency path
per C source. `--kind static-library` uses the selected archiver:

```sh
./x2c build --kind static-library \
  --output /tmp/libwidget.a src/widget.x src/helper.c
```

`-c`, or `--compile-only`, stops after compilation. One input may name its
object with `--output`. Multiple compile-only inputs require `--build-dir`, so
every object has an unambiguous path.

Without `--build-dir`, a direct build uses a private temporary directory and
removes intermediates after success. `--save-temps` retains intermediates;
`--save-temps=<dir>` places them in a chosen directory. With a named build
directory, later builds can reuse unchanged results.

`--compile-commands <file>` writes a native compilation database for C tools.
It records the actual compiler argument arrays, working directory, source,
and object output for every compilation, including reused objects. Manifest
builds include the selected target and its dependency targets. The entries
refer to generated C for x2c inputs, so the option also retains intermediates.

```sh
./x2c build --build-dir .x2c-build \
  --compile-commands .x2c-build/compile_commands.json examples/foreach.x
```

The destination's parent directory must exist when the build finishes. A
successful build replaces the database atomically; a failed build preserves
the previous file. `run` writes it before starting the program, and `-###`
writes no database. This file describes native C compilation, not x2c syntax
for an editor's C parser.

### VS Code diagnostics, definitions, and hover

Install the VSIX built from `etc/vsc-extension` with **Extensions: Install
from VSIX**. The extension uses the installed compiler directly; no separate
worker build is required. Set an absolute compiler path when it is not on
`PATH`:

```json
"x2c.semantic.compilerPath": "/path/to/x2c/bin/x2c"
```

Selection order is an explicit `x2c.semantic.compilerPath`, an explicit legacy
`x2c.semantic.workerPath`, executable `./x2c` in the trusted workspace, then
`x2c` on `PATH`. An explicit selection never silently switches to another
compiler. A missing executable produces one setup message in the **x2c**
Output channel, and discovery retries when you use the editor again. The
extension does not build or install the compiler automatically.

The default configuration discovers `x2c.toml` and its default target, or
analyzes the current file directly when there is no project. Select a target
or profile with ordinary compiler arguments:

```json
"x2c.semantic.arguments": ["build", "--target", "app", "--profile", "debug"]
```

The selected target must include the open source as an input. For a header or
macro file outside that input list, open its owning source or configure a
`translate` command with the needed include and package options. Unsaved
included files still affect analysis of their owning source.

Diagnostics, definition navigation, and type hover include unsaved source
text. Each request runs in a fresh compiler process with snapshots of open
files; editing cancels obsolete results without writing buffers to disk.
Native CPP symbol modes cannot consume unsaved source snapshots and report
that limitation. Macro-generated syntax may lack a physical definition or
identifier location.

Semantic execution requires a trusted local workspace because compilation can
run macros. Untrusted and virtual workspaces retain syntax highlighting. Set
`"x2c.semantic.enabled": false` to disable semantic execution. Completion,
rename, workspace indexing, and general LSP support are separate features.
The private `x2c editor` transport serves these providers; its argument and
response formats are not a public compiler API.

Shared libraries are unsupported. Supporting them requires platform-specific
position-independent code, visibility, runtime linkage, library naming, and
initialization rules.

## Bootstrap a native installation

The Cosmopolitan APE executable is an experiment for fun only. It can
bootstrap a minimal native compiler and runtime without a repository checkout,
but includes no examples, book, or optional packages. Use the full repository
for normal development; this experiment is no substitute for it.

To try the experiment:

```sh
./x2c.com bootstrap --prefix "$HOME/.local/x2c"
```

The command verifies and extracts the source distribution stored in the APE
ZIP, builds a native runtime archive first, then builds and installs the
matching native compiler. The result includes the compiler, its runtime
archive, headers, sources, unit interfaces, licenses, and a toolchain record.

Bootstrap selects tools in the same order as ordinary builds: `--cc`, `X2C_CC`,
`CC`, then `cc`; and `--ar`, `X2C_AR`, `AR`, then `ar`. It uses `-O2` unless
another supported optimization is explicit. The installed compiler and runtime
are native to the host and do not depend on Cosmopolitan. For every C
compilation it runs, x2c selects signed plain `char`. The runtime requires an
eight-bit signed `char`, even on hosts whose C compiler defaults to unsigned
plain `char`. Compile-time Lisp bindings keep working in the native result.
They resolve against compiler-generated targets.

## Build and run

`run` builds an executable and launches it after the build succeeds:

```sh
./x2c run examples/foreach.x -- first -second input.x
```

Use `-q` to suppress build progress and receipts while preserving program
output. Use `--build-dir <dir>` to retain generated files and objects for
inspection or reuse. Otherwise temporary intermediates are removed after the
program finishes.

`--` ends build options. Every later value is passed as one program argument,
including values that begin with `-` or end in `.x`. x2c returns the program's
exit status. `-###` prints the build and run actions without creating or
launching anything.

The program inherits standard input, output, and error, so interactive prompts
and terminal applications work as they do when launched directly. Shell pipes
and redirections also apply to the program; its output is not held until exit.

## Run a script

`script` runs one source file and builds it only when needed. The file name
ends in `.x`, or may be any name when the first line is a shebang:

```sh
./x2c script tools/report.x -- first --second
```

The first run builds an executable into the per-user cache. Later runs
start that executable directly, in a few milliseconds, until one of these
changes: the script, a file it includes or imports, a header its generated C
includes, a package archive it links, the compiler, the runtime archive, the
C compiler, the script's options, or the `CPATH`, `C_INCLUDE_PATH`,
`LIBRARY_PATH`, and `SDKROOT` environment variables. The cache also records
the directories the build searched: include directories, `-L` directories,
the C compiler's header and library search paths, and the directory of each
file the build read. Adding or removing a file in one of them rebuilds the
script. This covers a header that now shadows an included one, a
`__has_include` whose result changed, and a `-l` library that now resolves
elsewhere. `--rebuild` builds regardless.

Options come before the script file, and every word after it is passed to
the program unchanged, including `--` and words that begin with `-` or `@`.
A response file given before the script supplies options. `script` accepts
the include options `-I`, `--x-include-dir`, `--c-include-dir`,
`--c-system-dir`, and `--package-dir`; the C compiler and linker options of
`run`; and `-j`, `--source-map`, `--rebuild`, `--clean`, `-v`, `-###`,
`--plain`, `--color`, `--debug`, `--max-errors`, and `--diagnostics-file`.
`x2c help script` lists them. It does not read a project manifest.

A successful build prints nothing, so the program's output is all that
appears; build diagnostics still print, and a failed build exits with its
status. `-v` shows the build actions and the final run action. The program
replaces the `x2c` process, so it receives signals and terminal input
directly and its exit status is the command's. Its `argv[0]` is the script's
absolute path. A `--source-map -g` build on macOS keeps its `run.dSYM` beside
the cached executable.

A script file can start with a shebang line and run directly:

```sh
#!/usr/bin/env -S x2c script
```

That line also makes the file a
[script unit](language.md#script-units), which may put its statements at
file scope instead of defining `main`.

A script can split its code into local modules with ordinary includes, such
as `#include "lib/report.x"`. `x2c script` translates, compiles, and links
every local `.x` file the script includes, directly or through another
module, and a change to any of them rebuilds the script. Runtime and package
modules come from their archives instead.

`env -S` splits the line into words. Where `x2c` has a fixed location, the
interpreter path works without it: `#!/usr/local/bin/x2c script`.

Each script builds under `scripts/` in the cache root: `X2C_CACHE_DIR` when
set, otherwise `$XDG_CACHE_HOME/x2c`, otherwise `~/.cache/x2c`.
`x2c env cache_dir` prints the root. Concurrent runs of one script share its
build and wait for each other. `x2c script --clean <file>` removes that
script's entry without running it, and every build removes the entries of
scripts that no longer exist. Removing the cache is always safe.

## Selecting inputs

Shell wildcards work because the shell expands them into explicit operands:

```sh
./x2c build --output /tmp/tool src/*.x
```

x2c does not expand wildcard operand text or recurse through directory
operands. Naming a directory does not select the sources under it.

Response files hold long explicit command lines:

```text
build
--output
build/tool
-I
include
src/main.x
src/parse.x
```

Invoke one as `./x2c @build.rsp`. Whitespace separates arguments;
single and double quotes preserve whitespace; backslash quotes the next
character. A first-non-whitespace `#` begins a comment. Response files may
include other response files, but cycles are rejected. `@@name` passes the
literal operand `@name`.

## Start a project

`new` creates a project that builds and runs as written:

```sh
x2c new hello
cd hello
x2c run -q            # Hello, world!
x2c run -q -- Gary    # Hello, Gary!
```

It writes `x2c.toml`, `src/main.x`, and `.gitignore`, which ignores the
default build directory `.x2c-build/`. The manifest has one executable target
named after the directory:

```toml
[target.hello]
sources = ["src/*.x"]
```

The directory may be missing or empty; `x2c new .` fills the current empty
directory. `new` refuses any other existing path and never overwrites a
file. The target name is the directory's last component and may contain
letters, digits, `_`, and `-`. `-q` suppresses the `x2c: created <dir>`
line.

## Project manifests

When `build` or `run` has no explicit input operands, x2c searches the current
directory and its parents for the nearest `x2c.toml`. `--manifest-path` selects
one exact file and disables discovery. Explicit input operands do not use a
nearby manifest.

```toml
[project]
name = "demo"
default-target = "demo"
build-dir = "build/x2c"

[target.core]
kind = "static-library"
sources = ["src/core/*.x"]
exclude = ["src/core/experimental.x"]
include-dirs = ["include"]

[target.demo]
sources = ["src/main.x", "src/commands/**/*.x"]
dependencies = ["core"]
libraries = ["m"]

[target.demo.profile.release]
optimization = "O2"
debug = false
```

The manifest lists the sources of each target and how the targets depend on
each other. Relative paths start at the manifest directory. Its `*`, `?`,
and bracket patterns stay within a path component; `**` recurses. As in a
shell, a name that begins with a dot matches only where the pattern has a
literal dot. Matches are deduplicated and bytewise sorted. Unmatched patterns,
unknown targets, and dependency cycles are errors before any action runs.

A target may also set defines, C flags, library directories, libraries, link
flags, package directories, and an output. Command-line target, profile,
kind, output, build directory, and tool options override the corresponding
defaults. `--target <name>` builds the named manifest target and `--profile
<name>` applies the named manifest build profile; both work with `build` and
`run`.

### Pinned packages

A `[dependencies]` section pins packages by exact version. Each key is a
package name in the index and each value is the version in that index
row:

```toml
[dependencies]
pcre2 = "10.48"
```

This is separate from a target's `dependencies` field, which lists other
targets in the same manifest.

`build` and `run` resolve the section before planning. A pinned package
missing from the x2c home at that version is installed through the
index, the same way [`x2c install <name>`](#packages) does, and `--index`
selects another index. The resolution is then written to `x2c.lock` beside
the manifest, one `name version kind platform url sha256` row per package.
Keep that file with the manifest so a later build reproduces the same
packages.

A build whose lockfile already covers every pinned package, at the pinned
version and installed in the home, reads no index and makes no network
request. Any other state re-resolves through the index and rewrites the
lockfile. A version the index cannot supply stops the build with an error
that includes both versions. The
editor adapter never installs.

## Include and tool ownership

`-I <dir>` is the shared include option. Repeated paths keep command order,
and the first matching path wins in x2c quote-include collection, any
requested x2c host preprocessing, and generated C compilation.

The exceptions are:

```text
--x-include-dir <dir>  x2c collection and x2c preprocessing only
--c-include-dir <dir>  C compilation only, ordinary include semantics
--c-system-dir <dir>   C compilation only, system-header semantics
```

`--package-dir <dir>` adds a directory of x2c packages. An `import` statement
searches those directories for a package that is not beside the source. The
option applies to `translate`, `build`, and `run`, and repeats like `-I`.
After the explicit and manifest directories, every command also searches
`<home>/packages` when that directory exists.

## Packages

`install`, `remove`, and `list` manage `<home>/packages`; see
[install packages](../guide/packages.md#install-packages). `install` takes
one operand: a local directory, a local `.tar.gz`, a URL with `--sha256
<hex>`, or a name resolved through the index (`--index <url-or-path>`
overrides the default). `--force` accepts a bundle built by another x2c
version. `remove` takes one installed name; `list` prints `name version
kind` lines. Refusals exit with status 2 and leave the installed set as it
was.

A project manifest can pin packages instead of installing them by hand; see
[pinned packages](#pinned-packages).

## Environment

`x2c env` prints the resolved home, executable, include directory, runtime
archive, prelude interface, package roots, C compiler, archiver, and script
cache root as `name = value` lines. The prelude is the runtime `x2c.xi`
interface the compiler replays for the runtime declarations; an empty value
means the compiler reads `lib/x2c.x` from source once per process.
`x2c env <name>` prints one value; `--package-dir`, `--cc`, and `--ar` show
their effect on the report.

```sh
x2c env
x2c env runtime_lib
```

The home is `X2C_HOME` when set. Otherwise the compiler walks up from its
executable, then from the current directory, to the nearest directory holding
`include/` and `etc/compiler-sdk.xlisp`. A source checkout and an
[installed prefix](../guide/installation.md) are both homes. A stage compiler
under `<home>/builds/<n>/` links that stage's runtime archive. Any other
compiler links `<home>/lib/libx2c.a` when it exists, and otherwise
`<home>/builds/0/libx2c.a`, the stage 0 runtime whose headers a source
checkout's `include/x2c` names.

There is no lowercase `-i`. `-D` and `-U` reach requested x2c preprocessing
and C compilation. Optimization, debug, and `-Xcc` are compile-only; `-L`,
`-l`, `--rpath`, `-Wl,`, and `-Xlinker` are link-only. Unknown options are
rejected. `--rpath <dir>` records `<dir>` in the program as a place to find
shared libraries when it runs; a package bundle may include it.

The C compiler selection order is `--cc`, `X2C_CC`, `CC`, the installed
toolchain record, then `cc`. The archiver follows `--ar`, `X2C_AR`, `AR`, the
installed record, then `ar`. Omitted optimization, debug, define, and undefine
options preserve host defaults. `CFLAGS` and `LDFLAGS` are not shell-split or
implicitly consumed.

## Compiler diagnostics

Translation reports each diagnostic on standard error as
`file:line:column: code: message`, followed by the source line, a caret, and
any notes. A unit stops after 20 errors. `--max-errors <count>` changes that
bound for `translate`, `build`, `run`, and `script`, and `--max-errors 0`
removes it. When the bound is greater than one, a unit that reaches it ends
with `limit: too many errors, stopping`. With `--max-errors 1`, the unit's
output ends after its first error. The
[diagnostics section](language.md#diagnostics) of the language reference
describes which errors are reported together.

`--diagnostics-file <file>` writes the same diagnostics to `<file>` as JSON
Lines instead of standard error:

```sh
./x2c build --diagnostics-file /tmp/app.jsonl --output /tmp/app app.x
```

x2c creates or truncates the file when the command starts, so a command with
no diagnostics leaves it empty. Each line is one JSON object:

```text
{"code":"type","message":"operator 'is' requires Var on the left","severity":"error","file":"app.x","line":9,"column":16,"length":2,"position":120,"notes":["operand type: (int)"]}
```

- `code` is the diagnostic category, such as `parse`, `type`, `macro`,
  `protocol`, `xform`, `region`, `warning`, or `limit`.
- `severity` is `error`, `warning`, or `note`. It records how the report was
  submitted, so each entry in a category with both severities, such as
  `region` or `literal`, has its own severity. The `limit` notice is a
  `note`.
- `file` is relative to the working directory for a source inside it and
  absolute otherwise. A pseudo-source such as `<stdin>` keeps its name.
- `line` and `column` are one-based, `length` is the token width in bytes,
  and `position` is its zero-based byte offset. All five location fields are
  `null` for a diagnostic without a location.
- `notes` holds the text notes in order. On standard error, the notes are
  joined with spaces.

Compile-time Lisp and macros may print to standard output and standard error,
so neither stream contains JSON. Parallel translation workers share the file;
each diagnostic is one appended write, so lines never interleave. A diagnostic
is written when it is reported, and the file is complete when the command
exits, including after a failed unit. Command-line, host preprocessor, C
compiler, and linker failures are not compiler diagnostics and remain on
standard error; the exit status reports the failure.

## Progress and receipts

Commands report completed translation, C compilation, archive, and link
phases on standard error. A final build receipt identifies the artifact,
elapsed time, generated C and header size, host compiler and job count,
intermediate directory, and output size. Manifest builds name each target.
Warm builds mark reused translation, compilation, and static archives as up
to date. Executables always relink so changed libraries and native linker
inputs take effect.

On a capable terminal, work lasting at least 125 ms may also use one transient
progress line. x2c does not enter raw mode, switch screens, or read terminal
input. Commands run from Make use stable receipts, since parallel recipes may
share the terminal. Redirected standard error also uses stable
newline-delimited receipts and no automatic color.

`--plain` selects stable receipts without terminal rendering or color. `-q`
and `--quiet` suppress successful progress and receipts without suppressing
diagnostics or a run program's output.
`--color=auto|always|never` controls color; `NO_COLOR` disables automatic
color. `--debug` enables compiler debug logging; `translate`, `build`, and
`run` accept it, and `bootstrap` does not.

`--verbose` prints each command as it runs. `-###` prints the same commands
without running them. Use them first when checking runtime selection, include
order, or which phase a flag reached. Neither prints completion receipts into
that output, and the inspection modes keep progress out of their stdout data.

## Dependencies and external builds

Translation depfiles contain the primary source, transitive quote-includes,
and the runtime, macro, Lisp, and embedded-text files that unit read. The
native driver adds `-MMD -MP -MF -MT` per object and rejects conflicting
dependency flags passed through `-Xcc`.

Persistent direct and manifest builds use x2c depfiles for translation reuse.
Before reusing a native object, the selected C compiler preprocesses its source
with the current native flags and environment. Changed header search results
and `__has_include` conditions therefore rebuild the object; unchanged native
input reuses it. C depfiles remain available to external build tools. Missing
artifacts and missing, corrupt, or old private state are cache misses rather
than project errors.
Manifest comments and whitespace do not invalidate reuse; changed effective
settings still rebuild the affected actions.

External Make builds are supported. They can call `translate --out-dir`,
include its `.d` files, and set their own C compiler and linker flags. The
compiler driver does not replace a project that runs its own native build.

For example, from the repository directory you can translate an example and
compile its C output yourself:

```sh
mkdir -p /tmp/x2c-example
./x2c translate --out-dir /tmp/x2c-example examples/foreach.x
cc -iquote include/x2c /tmp/x2c-example/foreach.c \
  builds/0/libx2c.a -lm -o /tmp/x2c-example/foreach
/tmp/x2c-example/foreach
```

## Help, version, and status

`--help` and `--version` write to standard output and return `0`. Source,
host-tool, and link failures return `1`. Invalid commands, options, response
files, manifests, and preflight state return `2`. After a successful `run`,
the program's status is returned. Diagnostics and action output use standard
error; requested dumps and program output use standard output.
