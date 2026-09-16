# Commands and Files

Four optional modules cover the work shell scripts usually do. `process.x`
runs commands, pipelines, and background jobs. `path.x` inspects and changes
files and directories. `args.x` parses a script's own arguments, and
`digest.x` computes checksums. Include them explicitly:

```x2c
#include "process.x"
#include "path.x"
#include "args.x"
#include "digest.x"
```

All three keep to ordinary values. A command is a `List`, a path is a
`String`, parsed arguments are a `Map`, and every failure is an
[`Error`](exceptions.md) that a `catch` can select.

## Write a script

A source file whose first line is a shebang is a script. It includes
`process.x`, `path.x`, `args.x`, and `digest.x` automatically and may put
statements at file scope, which run in order as the program:

```x2c
#!/usr/bin/env -S x2c script
String branch = %(git rev-parse --abbrev-ref HEAD).output().strip("\n");
foreach (String file, %(git diff --name-only).lines())
  printf("%s: %s\n", branch, file);
```

`args` holds the arguments after the script's name as `String`s, and
`String.env` reads one environment variable of the script's own process,
returning NULL when it is unset:

```x2c
~#include "process.x"
~int main(void) {
String site = %"X2C_SITE".env();
if (!site) site = %"https://x2c-lang.dev";
~  return site ? 0 : 1;
~}
```

The `env` option sets variables for a child instead; this reads the script's
own environment. Functions,
types, and macros written between the statements work as they do in any
file, and the statements can call those functions wherever they are
defined. An existing program also becomes a script by adding the shebang
line: a file that defines `main` runs `main` and keeps its declarations at
file scope, so it may not also have top-level statements. A command that fails and is not caught ends the script with the
command's status, and any other uncaught error prints its cause and ends the
script with status 1. The
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

## Parse arguments

`parse_args` reads an argument `List` against a spec, which is a `List` with
one row per option or operand, and returns a `Map` from each row's name to
its value:

```x2c
~#include "args.x"
~#include "process.x"
~int main(int argc, char **argv) {
~List args = List.arguments(argc, argv);
List spec = %(
  (-v --verbose (help "Report each input"))
  (-o --output (value file) (default "report.txt") (help "Write <file>"))
  (-I --include (value dir) repeated (help "Also search <dir>"))
  (inputs repeated required (help "Files to read")));
Map options = args.parse_args(spec);
String output = options["output"].str();
foreach (String input, options["inputs"].list())
  if (options["verbose"]) printf("%s -> %s\n", input, output);
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
chooses the message and the status. `usage` returns help text generated
from the same spec:

```x2c
~#include "args.x"
~#include "process.x"
~int main(int argc, char **argv) {
List spec = %(
  (--prefix (value path) required (help "Install under <path>"))
  (-q --quiet (help "Print nothing on success")));
try {
  Map options = List.arguments(argc, argv).parse_args(spec);
  String prefix = options["prefix"].str();
  if (!options["quiet"]) printf("installing to %s\n", prefix);
}
catch %(bad-arg *detail): {
  Stderr.printf("%s", spec.usage("install.x"));
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

## Run a command

Each element of a command `List` becomes one argument. No shell reads the
words, so a value inserted with `$` stays a single argument whatever it
contains:

```x2c
~#include "process.x"
~int main(void) {
String message = %"it's two words";
%(git commit --allow-empty -m $message).run();
~  return 0;
~}
```

`run` inherits the standard streams and raises `<cmd-fail>` when the command
exits with a nonzero status. The other ways to finish a command differ only
in what they return:

| Method | Result |
| --- | --- |
| `run()` | nothing; raises on a nonzero status |
| `output()` | captured standard output; raises on a nonzero status |
| `lines()` | captured output split into lines; raises on a nonzero status |
| `status()` | the exit status, or 128 plus a signal; never `<cmd-fail>` |
| `start()` | a running `Job` |

```x2c
~#include "process.x"
~int main(void) {
String branch = %(git rev-parse --abbrev-ref HEAD).output().strip("\n");
foreach (String file, %(git ls-files "*.x").lines())
  printf("%s: %s\n", branch, file);
if (%(git diff --quiet).status())
  printf("uncommitted changes\n");
~  return 0;
~}
```

Bare words in a command are x2c atoms, so most flags and names need no
quotes. Write a word as a string when it contains punctuation that collection
syntax reads differently: a comma, `$`, `@`, or a redirection such as `2>&1`.
Inside a string, `$` still interpolates; write `\$` for a literal dollar
sign.

## Pipelines

A `List` of commands is a pipeline. `pipe` builds the same shape from two
commands:

```x2c
~#include "process.x"
~int main(void) {
String count = %((git ls-files) (grep "\\.x\$") (wc -l)).output();
String same = %(git ls-files).pipe(%(grep "\\.x\$")).pipe(%(wc -l)).output();
~  return count == same ? 0 : 1;
~}
```

A pipeline's status is the status of its last failing stage, so a failure
early in the pipeline is not hidden by a later stage that succeeds.

## Options

`options` returns the command with a `Map` of settings attached:

```x2c
~#include "process.x"
~int main(void) {
String root = "/tmp";
%(make all).options(%{dir: $root, env: {CC: clang}}).run();
String upper = %(tr a-z A-Z).options(%{input: "quiet"}).output();
%(make test).options(%{stdout: "/tmp/test.log", stderr: stdout}).run();
~  return upper == "QUIET" ? 0 : 1;
~}
```

| Key | Value |
| --- | --- |
| `dir` | working directory for the command |
| `env` | a `Map` of variables added to the inherited environment |
| `input` | a `String` given to the first stage as standard input |
| `stdout` | a file path, or `capture` |
| `stderr` | a file path, `capture`, or `stdout` to merge the two streams |

Standard output options apply to the last stage of a pipeline and `stderr`
to every stage. An unknown key raises `<bad-arg>`, so a misspelled `dir`
cannot silently run a command somewhere else.

## Failures

A command that runs and exits nonzero raises `<cmd-fail>` with `command` and
`status` details, plus `errors` when standard error was captured. A command
that cannot start raises `<not-found>` for a missing program or directory and
`<io-fail>` for anything else. Select the cases a script can handle:

```x2c
~#include "process.x"
~int main(void) {
try %(git pull --ff-only).run();
catch %(cmd-fail *detail):
  printf("pull failed with status %ld\n", detail.assoc(<status>).integer());
catch %(not-found *):
  printf("git is not installed\n");
~  return 0;
~}
```

## Background jobs

`start` returns a `Job` without waiting. `wait` returns its status, `check`
raises like `run`, and `output` and `errors` return captured text after
waiting. `Job.wait_any` removes and returns the first finished job from an
`Array`, which is enough to bound how many run at once:

```x2c
~#include "process.x"
~int main(void) {
Array running = %[];
foreach (Var host, %(alpha beta gamma delta)) {
  if (running.len() == 2) Job.wait_any(running).check();
  running.push(%(ping -c 1 $host).options(%{stdout: capture}).start());
}
while (running.len()) Job.wait_any(running).check();
~  return 0;
~}
```

A job declared with `$auto` is terminated and reaped if it is still running
when its block exits, including when an error leaves the block:

```x2c
~#include "process.x"
~int main(void) {
{
  Job server = $auto(%(python3 -m http.server 8000).start());
  %(curl -fsS "http://localhost:8000/").run();
}
~  return 0;
~}
```

`kill` sends a signal to every stage that is still running.

## Paths and files

Path methods take and return ordinary `String`s. `join_path`, `dirname`,
`basename`, `stem`, and `extension` only examine text:

```x2c
~#include "path.x"
~int main(void) {
String source = %"src".join_path("parse.x");
String object = %"build".join_path(%"${source.stem()}.o");
~  return object == "build/parse.o" && source.extension() == ".x" ? 0 : 1;
~}
```

`exists`, `is_dir`, `is_file`, `is_executable`, `file_size`, and
`modified_time` ask about a path; `modified_time` keeps the fraction of a
second the filesystem records.
`list_dir` returns the sorted names in one directory, `walk` lazily yields
every path below a directory, and `glob` returns the paths that match a
pattern, where `**` matches any number of directories. As in a shell, a
wildcard does not match a leading dot, so `*` skips `.git` while `.*` finds
it:

```x2c
~#include "path.x"
~int main(void) {
foreach (String unit, %"src/**/*.x".glob())
  printf("%s %ld\n", unit, unit.file_size());
~  return 0;
~}
```

`make_dirs`, `remove_file`, `remove_tree`, `copy_file`, `copy_tree`,
`move_to`, and `symlink_to` change the filesystem. Removing something that
is already gone succeeds. `read_text` and `write_text` read and replace a
whole file, and `String.temp_dir` creates a private directory:

```x2c
~#include "path.x"
~int main(void) {
String work = String.temp_dir();
work.join_path("out").make_dirs();
work.join_path("out/report.txt").write_text("done\n");
printf("%s", work.join_path("out/report.txt").read_text());
work.remove_tree();
~  return 0;
~}
```

A missing path raises `<not-found>` and any other failure raises `<io-fail>`,
both naming the operation and path.

[`examples/scripts/line-counts.x`](../../../examples/scripts/line-counts.x)
combines `process.x` and `path.x`: it builds a small tree, counts lines with
parallel jobs, and writes a report.

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
