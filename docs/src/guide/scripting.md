# Commands and Files

A script works with three kinds of value. A command is a `List`. A running
or finished command is a `Job`. A filesystem location is a `Path`. Every
failure is an [`Error`](exceptions.md) that a `catch` can select.

The modules are optional in ordinary programs. Include the ones a file uses:

```x2c
#include "process.x"
#include "path.x"
#include "args.x"
#include "digest.x"
```

## Write a script

A source file whose first line is a shebang is a script. It includes the
command, path, argument, environment, and checksum modules automatically and
may put statements at file scope, which run in order as the program:

```x2c
#!/usr/bin/env -S x2c script
String branch = %(git rev-parse --abbrev-ref HEAD).job().output();
foreach (String file, %(git diff --name-only).job().lines())
  printf("%s: %s\n", branch, file);
```

`args` holds the arguments after the script's name as `String`s. Functions,
types, and macros written between the statements work as they do in any
file, and the statements can call those functions wherever they are
defined. An existing program also becomes a script by adding the shebang
line: a file that defines `main` runs `main` and keeps its declarations at
file scope, so it may not also have top-level statements. A command that
fails and is not caught ends the script with the command's status, and any
other uncaught error prints its cause and ends the script with status 1. The
[language reference](../reference/language.md#script-units) lists what stays
at file scope.

`x2c script` runs the file the way an interpreter would. The first run
builds it; later runs start the cached executable in a few milliseconds
until the script or something it uses changes:

```sh
x2c script tools/release-notes.x v0.12.0
```

A script can include its own local `.x` modules, which `x2c script` builds
and links with it. With an executable mode, the shebang runs it by name.
Every argument after the file reaches the program unchanged. The [command
reference](../reference/cli.md#run-a-script) describes the cache and exactly
what makes a script build again.

## Commands

Each element of a command `List` becomes one argument. No shell reads the
words, so a value inserted with `$` stays one argument whatever it contains:

```x2c
~#include "process.x"
~int main(void) {
String message = %"it's two words";
%(git commit --allow-empty -m $message).job().run();
~  return 0;
~}
```

Bare words in a command are x2c atoms, so most flags and names need no
quotes. Write a word as a string when it contains punctuation that collection
syntax reads differently: a comma, `$`, `@`, or a redirection such as `2>&1`.
Inside a string, `$` still interpolates; write `\$` for a literal dollar
sign.

`job` turns a command into a `Job`. Making a job does not start the program.
The first result you ask for starts it, waits for it, and records what it
did. Every later request reads that same record, so a job runs exactly once
however many results you take from it.

### Reading results

| Method | Result |
| --- | --- |
| `status()` | the exit status, or 128 plus a signal; never raises |
| `output()` | captured standard output |
| `lines()` | captured standard output split into lines, without endings |
| `errors()` | captured standard error, or NULL when it was not captured; never raises |
| `check()` | the job itself; raises when the status is not zero |
| `run()` | shows output live, waits, and raises when the status is not zero |

By default a job captures standard output and passes standard error through
to the terminal, the way the shell's `$(...)` does. A script gets the output
to work with, and error messages still reach the person running it.

```x2c
~#include "process.x"
~int main(void) {
Job diff = %(git diff --stat).job();
if (diff.status() == 0)
  printf("%ld lines of summary\n", (long) diff.lines().len());
~  return 0;
~}
```

### Showing output live

A command whose output belongs on the terminal, such as a build or a test
run, calls `live` before it starts. A live job does not capture standard
output, so `output` and `lines` return NULL. `run` is the short form of
`live().check()`:

```x2c
~#include "process.x"
~int main(void) {
%(make all).job().run();
if (%(make test).job().live().status())
  printf("tests failed\n");
~  return 0;
~}
```

### Failures

`check`, `run`, `output`, and `lines` raise `<cmd-fail>` when the status is
not zero. The detail carries `command` and `status`, plus `output` and
`errors` when they were captured. `status` and `errors` never raise, so a
script can read standard error after a failure. A program that cannot start
raises `<not-found>` for a missing program or directory, and `<io-fail>` for
anything else:

```x2c
~#include "process.x"
~int main(void) {
try %(git pull --ff-only).job().run();
catch %(cmd-fail *detail):
  printf("pull failed with status %ld\n", detail.assoc(<status>).integer());
catch %(not-found *):
  printf("git is not installed\n");
~  return 0;
~}
```

In a script, a `<cmd-fail>` that nothing catches ends the script with the
command's status.

### Pipelines

A `List` of commands is a pipeline, and `pipe` adds a stage to a job. These
two jobs are the same:

```x2c
~#include "process.x"
~int main(void) {
List units = %((git ls-files) (grep "\\.x\$")).job().lines();
List same = %(git ls-files).job().pipe(%(grep "\\.x\$")).lines();
~  return units == same ? 0 : 1;
~}
```

The job's status is the status of its last failing stage, so an early
failure is not hidden by a later stage that succeeds.

### Options

`options` attaches settings before the job starts:

```x2c
~#include "process.x"
~#include "path.x"
~int main(void) {
Path root = "build";
%(make all).job().options(%{dir: $root, env: {CC: clang}}).run();
String upper = %(tr a-z A-Z).job().options(%{input: "quiet"}).output();
~  return upper == "QUIET" ? 0 : 1;
~}
```

| Key | Value |
| --- | --- |
| `dir` | working directory |
| `env` | a `Map` of variables added to the inherited environment |
| `input` | a `String` given to the first stage as standard input |
| `stdout` | `capture` (the default), `inherit`, or a file path |
| `stderr` | `inherit` (the default), `capture`, `stdout` to merge, or a file path |

`stdout` applies to the last stage of a pipeline, and `stderr` to every
stage. `live()` is the same as `options(%{stdout: inherit})`. An unknown key
raises `<bad-arg>`, so a misspelled `dir` cannot silently run a command
somewhere else. Changing options or adding a stage after the job has started
also raises `<bad-arg>`.

### Background jobs

`start` begins a job without waiting and returns the job. `ready` reports
whether a started job has finished. `Job.wait_any` removes and returns the
first finished job from an `Array`, which is enough to bound how many run at
once:

```x2c
~#include "process.x"
~int main(void) {
Array running = %[];
foreach (Var host, %(alpha beta gamma delta)) {
  if (running.len() == 2) Job.wait_any(running).check();
  running.push(%(ping -c 1 $host).job().live().start());
}
while (running.len()) Job.wait_any(running).check();
~  return 0;
~}
```

`kill` sends a signal to every stage still running. A job held with `$auto`
is terminated and reaped if it is still running when its block exits,
including when an error leaves the block:

```x2c
~#include "process.x"
~int main(void) {
{
  Job server = $auto(%(python3 -m http.server 8000).job().live().start());
  %(curl -fsS "http://localhost:8000/").job().run();
}
~  return 0;
~}
```

## Paths

A `Path` is a `String` that names a filesystem location. A literal or a
`String` converts to a `Path` wherever one is expected, and a `Path` passes
wherever a `String` parameter is expected. Only a `Path` has the file
methods.

```x2c
~#include "path.x"
~int main(void) {
Path source = "src/parse.x";
Path object = Path.join("build", %"${source.stem()}.o");
~  return object == "build/parse.o" ? 0 : 1;
~}
```

A method can be called on a `Path` value, or through the type with a
literal:

```x2c
~#include "path.x"
~int main(void) {
if (Path.exists("build")) Path.remove_tree("build");
foreach (Path unit, Path.glob("src/**/*.x"))
  printf("%s %ld\n", unit, unit.size());
~  return 0;
~}
```

### Examining a path

`join`, `dirname`, `basename`, `stem`, `extension`, and `glob_match` only
examine text. `stem` and `extension` return a `String`; the others that
return text return a `Path`. `absolute` resolves a path against the working
directory.

### Asking about a path

`exists`, `is_dir`, `is_file`, `is_executable`, `size`, and `modified_time`
ask the filesystem. `modified_time` keeps the fraction of a second that the
filesystem records.

### Listing

`list_dir` returns the sorted names in one directory. `walk` lazily yields
every path below a directory. `glob` returns the paths that match a pattern,
where `**` matches any number of directories. As in a shell, a wildcard does
not match a leading dot, so `*` skips `.git` while `.*` finds it.

### Changing the filesystem

`make_dirs`, `remove_file`, `remove_tree`, `copy_file`, `copy_tree`,
`move_to`, and `symlink_to` change the filesystem. Removing something that is
already gone succeeds. `read_text` and `write_text` read and replace a whole
file. `Path.temp_dir` creates a private directory:

```x2c
~#include "path.x"
~int main(void) {
Path work = Path.temp_dir();
work.join("out").make_dirs();
work.join("out/report.txt").write_text("done\n");
printf("%s", work.join("out/report.txt").read_text());
work.remove_tree();
~  return 0;
~}
```

A missing path raises `<not-found>`, and any other failure raises
`<io-fail>`. Both name the operation and the path.

Text operations such as slicing and `+` are `String` operations. Convert a
`Path` to a `String` to use them.

[`examples/scripts/line-counts.x`](https://github.com/gwf/x2c/blob/main/examples/scripts/line-counts.x)
combines commands and paths: it builds a small tree, counts lines with
parallel jobs, and writes a report.

## Environment

`Env.get` returns the value of one of the script's own environment variables,
or NULL when it is unset. The `env` option sets variables for a child
instead:

```x2c
~#include "process.x"
~int main(void) {
String site = Env.get("X2C_SITE");
if (!site) site = "https://x2c-lang.dev";
~  return site ? 0 : 1;
~}
```

## Arguments

`Args.parse` reads an argument `List` against a spec, which is a `List` with
one row per option or operand, and returns a `Map` from each row's name to
its value. In a program with `main`, `Args.from_argv` makes that `List` from
`argc` and `argv`; a script already has it as `args`.

```x2c
~#include "args.x"
~int main(int argc, char **argv) {
List spec = %(
  (-v --verbose (help "Report each input"))
  (-o --output (value file) (default "report.txt") (help "Write <file>"))
  (-I --include (value dir) repeated (help "Also search <dir>"))
  (inputs repeated required (help "Files to read")));
Map options = Args.parse(Args.from_argv(argc, argv), spec);
String output = options["output"].str();
foreach (String input, options["inputs"].list())
  if (options["verbose"]) printf("%s: %s\n", output, input);
~  return 0;
~}
```

A row that begins with dashed words is an option with those spellings. Its
name is the first long spelling without the dashes, or the short spelling
when it has no long one, so the rows above are named `verbose`, `output`,
and `include`. A row that begins with any other word is an operand of that
name. The rest of a row describes it:

| Row part | Meaning |
| --- | --- |
| `(value file)` | the option takes a value, shown as `<file>` in usage |
| `(default "report.txt")` | the value when the row is not given |
| `(help "text")` | the row's description in usage text |
| `required` | a missing option or operand raises `<bad-arg>` |
| `repeated` | every value is kept in a `List`; an operand takes the rest |

A long option takes its value as `--output out.txt` or `--output=out.txt`,
and a short one as `-o out.txt` or `-oout.txt`. Short flags may share a word,
as in `-vv`. Operands may come before, between, or after options, and every
word after `--` is an operand. Operand rows take operands in spec order.

Every name in the spec is present in the result. A flag holds the number of
times it appeared, a `repeated` row holds a `List`, and any other row holds
its last value as a `String`. A row that was not given holds its default, or
else zero, an empty `List`, or a NULL `String`, all of which test false.
Values stay `String`s; convert one to a number where the script needs it.

An unknown option, a missing or unexpected value, an extra operand, or a
missing `required` row raises `<bad-arg>` with `why` and the offending
`option` or `operand`. Nothing exits on the script's behalf, so the script
chooses the message and the status. `Args.usage` returns help text generated
from the same spec:

```x2c
~#include "args.x"
~int main(int argc, char **argv) {
List spec = %(
  (--prefix (value path) required (help "Install under <path>"))
  (-q --quiet (help "Print nothing on success")));
try {
  Map options = Args.parse(Args.from_argv(argc, argv), spec);
  String prefix = options["prefix"].str();
  if (!options["quiet"]) printf("installing to %s\n", prefix);
}
catch %(bad-arg *detail): {
  Stderr.printf("%s", Args.usage(spec, "install.x"));
  return 2;
}
~  return 0;
~}
```

```text
Usage:
  install.x [options]

Options:
      --prefix <path>         Install under <path>
  -q, --quiet                 Print nothing on success
```

A script with subcommands reads the first word itself and parses the rest
with that command's spec. [`etc/x2c-payload.x`](../../../etc/x2c-payload.x),
which `make install` runs, works this way.

## Checksums

`digest.x` computes SHA-256 digests, spelled as the lowercase hexadecimal
`String` that `shasum -a 256` prints. `String.sha256` hashes the text of a
`String`. `File.sha256` hashes the raw bytes from a stream's position to its
end, so it also works on binary files that `read_text` refuses:

```x2c
~#include "digest.x"
~int main(void) {
File shell = $auto(File.open("/bin/sh", "rb"));
printf("%s  /bin/sh\n", shell.sha256());
String abc = %"abc".sha256();
~  return abc.startswith("ba7816bf8f01cfea") ? 0 : 1;
~}
```

## JSON

A script that reads or writes JSON includes `json.x` itself:

```x2c
#include "json.x"
```

It is not included automatically because its names match the converting
surface of the [`yyjson` package](../../../packages/yyjson/README.md), so a
script moves to the package by replacing that line with
`import "yyjson" with Json;`.

`Json.parse` reads JSON text and `Json.read_file` reads a JSON file. The
result is made of ordinary values: an object is a `Map` with `String` keys,
an array is an `Array`, a string is a `String`, and a number is an integer or
`double` `Var`. JSON null is the all-zero `Var`. `true` and `false` are
`JsonBool` values, which test true and false in a condition and stay distinct
from the numbers 1 and 0:

```x2c
~#include "json.x"
~int main(void) {
Map release = Json.read_file("release.json");
if (!release["draft"]) printf("release %s\n", release["version"]);
foreach (Map asset, release["assets"]) printf("  %s\n", asset["name"]);
~  return 0;
~}
```

An integer that fits in an `int` reads as one, then as a `long` or an
`unsigned long`; every other number is a `double`. A repeated object name
keeps its last value.

`Var.json` returns compact text, `Var.pretty_json` indents two spaces per
level, and `Json.write_file` writes the compact form to a file. Object names
are written in byte order, so equal values always produce the same text, and
the indented layout is the one Python's `json.dumps` produces with
`indent=2` and `sort_keys=True`. A bare key in a `%{}` literal is a `Symbol`,
which is written as a string, and `Json.bool` makes a boolean. A `Map` or
`Array` variable reaches the writers through `Var`:

```x2c
~#include "json.x"
~int main(void) {
Map report = %{name: "x2c", passed: ${Json.bool(1)}, counts: [3, 0]};
printf("%s\n", Var.pretty_json(report));
Json.write_file(report, "/tmp/report.json");
~  return 0;
~}
```

Text that is not JSON raises `<bad-arg>` with `why`, a zero-based byte
`offset`, and one-based `line` and `column` details; `Json.read_file` adds
the `path`. The same cause rejects nesting deeper than 512 arrays and
objects, a number too large for a `double`, an unpaired surrogate escape,
and `\u0000`, which a `String` cannot hold:

```x2c
~#include "json.x"
~int main(void) {
try Json.read_file("settings.json");
catch %(bad-arg *detail):
  printf("settings.json:%ld:%ld: %s\n", detail.assoc(<line>).integer(),
         detail.assoc(<column>).integer(), detail.assoc(<why>).string());
~  return 0;
~}
```

Writing raises `<bad-types>` for a value JSON cannot hold, such as a `File`
or a `Map` key that is not a `String` or `Symbol`, and `<conv-range>` for NaN
or an infinity.

The package keeps what a `Map` cannot: object order, duplicate names, and
whether a number was signed, unsigned, or real. Its converted integers are
`long long` or `unsigned long long` values, which do not compare equal to an
`int` literal such as the 5 in `%{n: 5}`, and malformed text raises
`<malformed>` rather than `<bad-arg>`.

