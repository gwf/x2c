# Commands and Files

Two optional modules cover the work shell scripts usually do. `process.x`
runs commands, pipelines, and background jobs. `path.x` inspects and changes
files and directories. Include them explicitly:

```x2c
#include "process.x"
#include "path.x"
```

Both keep to ordinary values. A command is a `List`, a path is a `String`,
and every failure is an [`Error`](exceptions.md) that a `catch` can select.

## Write a script

A source file whose first line is a shebang is a script. It includes both
modules automatically and may put statements at file scope, which run in
order as the program:

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
combines both modules: it builds a small tree, counts lines with parallel
jobs, and writes a report.
