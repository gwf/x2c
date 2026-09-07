# Command-line interface

After building the repository, `./x2c` links to the development compiler;
`./bin/x2c` is the bootstrap compiler. Every invocation begins with `translate`, `build`, `run`,
`bootstrap`, or `help`.

The generated help is the short option reference:

```sh
./x2c --help
./x2c help translate
./x2c build --help
./x2c run --help
./x2c bootstrap --help
```

## Translate to C

`translate` writes one matching `.c`, `.h`, and default `.d` file for each
explicit `.x` input:

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
inherit the symbol snapshot and header artifact the parent already read:

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
- `--dump-symbol-snapshot` prints a complete symbol snapshot and stops.
- `--dump-header-symbols` prints the header-symbol artifact and stops.

An inspection that does not write generated files does not need `--out-dir`.
Only one inspection mode runs; the last option given wins.

## Build native artifacts

`build` accepts explicit `.x`, `.c`, `.o`, and `.a` operands. It translates
x2c source, compiles generated and native C, then links an executable:

```sh
./x2c build --output /tmp/foreach examples/foreach.x
/tmp/foreach
```

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
archive, headers, sources, symbol inputs, licenses, and a toolchain record.

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

`--` ends build options. Every later value is passed as one program argument,
including values that begin with `-` or end in `.x`. x2c returns the program's
exit status. `-###` prints the build and run actions without creating or
launching anything.

The program inherits standard input, output, and error, so interactive prompts
and terminal applications work as they do when launched directly. Shell pipes
and redirections also apply to the program; its output is not held until exit.

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
each other. Relative paths start at the manifest directory. Its `*`, `?`, and
bracket patterns stay within a path component; `**` recurses. Matches are
deduplicated and bytewise sorted. Unmatched patterns, unknown targets, and
dependency cycles are errors before any action runs.

A target may also set defines, C flags, library directories, libraries, link
flags, package directories, and an output. Command-line target, profile,
kind, output, build directory, and tool options override the corresponding
defaults. `--target <name>` builds the named manifest target and `--profile
<name>` applies the named manifest build profile; both work with `build` and
`run`.

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

There is no lowercase `-i`. `-D` and `-U` reach requested x2c preprocessing
and C compilation. Optimization, debug, and `-Xcc` are compile-only; `-L`,
`-l`, `-Wl,`, and `-Xlinker` are link-only. Unknown options are rejected.

The C compiler selection order is `--cc`, `X2C_CC`, `CC`, the installed
toolchain record, then `cc`. The archiver follows `--ar`, `X2C_AR`, `AR`, the
installed record, then `ar`. Omitted optimization, debug, define, and undefine
options preserve host defaults. `CFLAGS` and `LDFLAGS` are not shell-split or
implicitly consumed.

## Progress and receipts

Commands report completed translation, C compilation, archive, and link
phases on standard error. A final build receipt identifies the artifact,
elapsed time, generated C and header size, host compiler and job count,
intermediate directory, and output size. Manifest builds name each target;
warm builds mark cached phases and the final artifact as up to date.

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
and the symbol artifacts that unit used. The native driver adds
`-MMD -MP -MF -MT` per object and rejects conflicting dependency flags passed
through `-Xcc`.

Persistent direct and manifest builds use those x2c and C depfiles to decide
what needs rebuilding. Missing artifacts and missing, corrupt, or old private
state are cache misses rather than project errors.

External Make builds are supported. They can call `translate --out-dir`,
include its `.d` files, and set their own C compiler and linker flags. The
compiler driver does not replace a project that runs its own native build.

For example, from the repository directory you can translate an example and
compile its C output yourself:

```sh
mkdir -p /tmp/x2c-example
./x2c translate --out-dir /tmp/x2c-example examples/foreach.x
cc -iquote include /tmp/x2c-example/foreach.c \
  builds/0/libx2c.a -lm -o /tmp/x2c-example/foreach
/tmp/x2c-example/foreach
```

## Help, version, and status

`--help` and `--version` write to standard output and return `0`. Source,
host-tool, and link failures return `1`. Invalid commands, options, response
files, manifests, and preflight state return `2`. After a successful `run`,
the program's status is returned. Diagnostics and action output use standard
error; requested dumps and program output use standard output.
