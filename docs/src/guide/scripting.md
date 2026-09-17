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
#include "regex.x"
#include "diff.x"
```

## Write a script

A source file whose first line is a shebang is a script. It can use the
modules above without including them, and its statements at file scope run
in order as the program:

```x2c
#!/usr/bin/env -S x2c script
String branch = %(git rev-parse --abbrev-ref HEAD).job().output();
foreach (String file, %(git diff --name-only).job().lines())
  printf("%s: %s\n", branch, file);
```

`args` holds the arguments after the script's name as `String`s.
[Script units](../reference/language.md#script-units) in the language
reference describes which forms stay at file scope, how a script that
defines `main` runs, and the exit status of an uncaught failure.

`x2c script` runs the file the way an interpreter would. The first run
builds it; later runs start the cached executable in a few milliseconds
until the script or something it uses changes:

```sh
x2c script tools/release-notes.x v0.12.0
```

A script can include its own local `.x` modules, which `x2c script` builds
and links with it. A script with an executable mode runs by name through its
shebang line. Every argument after the file reaches the program unchanged.
The [command reference](../reference/cli.md#run-a-script) describes the cache
and the changes that make a script build again.

## Commands

Each element of a command `List` becomes one argument. The words reach the
program without a shell, so a value inserted with `$` stays one argument
whatever it contains:

```x2c
~#include "process.x"
~int main(void) {
String message = %"it's two words";
%(git commit --allow-empty -m $message).job().run();
~  return 0;
~}
```

Bare words in a command are x2c atoms, so most flags and names need no
quotes. Write a word as a string when it contains punctuation with another
meaning in collection syntax: a comma, `$`, `@`, or a redirection such as
`2>&1`. Inside a string, `$` still interpolates; write `\$` for a literal
dollar sign.

`job` turns a command into a `Job`. The first request for a result starts
the program, waits for it, and records what it did. Every later request
reads that same record, so a job runs exactly once however many results you
take from it.

### Reading results

| Method | Result |
| --- | --- |
| `status()` | the exit status, or 128 plus a signal |
| `output()` | captured standard output |
| `lines()` | captured standard output split into lines, without endings |
| `errors()` | captured standard error, or NULL when it was not captured |
| `check()` | the job itself; raises when the status is not zero |
| `run()` | shows output live, waits, and raises when the status is not zero |

By default a job captures standard output and passes standard error through
to the terminal, the way the shell's `$(...)` does. The script receives the
output, and error messages appear on the terminal.

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

Call `live` before a job starts to show its output on the terminal, as for a
build or a test run. A live job does not capture standard output, so
`output` and `lines` return NULL. `run` is the short form of
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
not zero. The detail has `command` and `status` entries, plus `output` and
`errors` entries when they were captured. `status` and `errors` raise only
when a program cannot start, so a script can read standard error after a
nonzero status. When a program cannot start, the job raises `<not-found>`
for a missing program or directory, and `<io-fail>` for anything else:

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

The job's status is the status of its last failing stage, so a failure in
an early stage sets the status even when a later stage succeeds.

### Options

`options` attaches settings before the job starts:

```x2c
~#include "process.x"
~#include "path.x"
~int main(void) {
Path root = "build";
%(make all).job().options({dir: root, env: {CC: <clang>}}).run();
String upper = %(tr a-z A-Z).job().options({input: "quiet"}).output();
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
stage. `live()` is the same as `options({stdout: <inherit>})`. An unknown key,
such as a misspelled `dir`, raises `<bad-arg>`. Changing options or adding a
stage after the job has started also raises `<bad-arg>`.

### Background jobs

`start` begins a job without waiting and returns the job. `ready` reports
whether a started job has finished. `Job.wait_any` removes and returns the
first finished job from an `Array`. This loop uses it to bound how many jobs
run at once:

```x2c
~#include "process.x"
~int main(void) {
Array running = [];
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

A `Path` is a `String` that holds a filesystem location. A literal or a
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

`join`, `dirname`, `basename`, `stem`, `extension`, and `glob_match` operate
on the text alone. `stem` and `extension` return a `String`; the others that
return text return a `Path`. `absolute` resolves a path against the working
directory.

### Asking about a path

`exists`, `is_dir`, `is_file`, `is_executable`, `size`, and `modified_time`
query the filesystem. `modified_time` keeps the fraction of a second that the
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
`<io-fail>`. Both details have `operation` and `path` entries.

`+` joins a `Path` with a `String`, another `Path`, or a C string literal and
produces a `String`, as in `path + ".o"`. Slicing is a `String` operation.
Convert a `Path` to a `String` to slice it.

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
Values stay `String`s; convert one to a number where a number is needed.

An unknown option, a missing or unexpected value, an extra operand, or a
missing `required` row raises `<bad-arg>` with `why` and the offending
`option` or `operand`. The script chooses the message and the exit status.
`Args.usage` returns help text generated from the same spec:

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
  Stderr.printf("%s", Args.usage("install.x", spec));
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
with that command's spec.
[`etc/x2c-payload.x`](https://github.com/gwf/x2c/blob/main/etc/x2c-payload.x),
which `make install` runs, works this way.

## Checksums

`digest.x` computes SHA-256 digests, spelled as the lowercase hexadecimal
`String` that `shasum -a 256` prints. `String.sha256` hashes the text of a
`String`. `File.sha256` hashes the raw bytes from a stream's position to its
end, so it also works on binary files that `read_text` rejects:

```x2c
~#include "digest.x"
~int main(void) {
File shell = $auto(File.open("/bin/sh", "rb"));
printf("%s  /bin/sh\n", shell.sha256());
String abc = "abc".sha256();
~  return abc.startswith("ba7816bf8f01cfea") ? 0 : 1;
~}
```

## Patterns

`regex.x` matches regular expressions over the bytes of a `String`. A
`Regex` is a compiled pattern:

```x2c
~#include "regex.x"
~#include "process.x"
~int main(void) {
Regex row = Regex.compile(%"^ *(?<count>\\d+) (?<file>.+)$$");
foreach (String line, %(wc -l lib/regex.x lib/path.x).job().lines()) {
  RegexMatch found = row.match(line);
  if (found) printf("%s: %s\n", found[<file>], found[<count>]);
}
~  return 0;
~}
```

Since `%"..."` interpolates `$`, write `$$` for an end anchor, or use a
plain C string literal for the pattern.

### Syntax

A pattern is text with these forms. Anything else matches itself.

| Form | Matches |
| --- | --- |
| `.` | any byte except newline |
| `[abc]`, `[a-z]`, `[^0-9]` | one byte in, or not in, the set |
| `\d` `\w` `\s`, `\D` `\W` `\S` | a digit, word byte, or space, or their opposites; also inside `[...]` |
| `\b` `\B` | a word boundary, or its absence |
| `^` `$` | the start and end of the text |
| `x*` `x+` `x?` `x{m}` `x{m,}` `x{m,n}` | repetition, as many times as possible |
| `x*?` `x+?` `x??` `x{m,n}?` | repetition, as few times as possible |
| `a\|b` | either |
| `(x)`, `(?<name>x)` | a numbered capture, also named |
| `(?:x)` | a group that does not capture |
| `\.` `\\` `\t` `\n` `\r` | a literal byte |
| `(?i)` `(?m)` `(?s)` | at the start: ignore ASCII case, let `^` and `$` match at line breaks, let `.` match newline |

Matching is byte by byte, so `.` and `\w` treat a multi-byte character as
several bytes, and `(?i)` folds only ASCII letters. There is no lookahead,
lookbehind, or backreference. The
[`pcre2` package](https://github.com/gwf/x2c/blob/main/packages/pcre2/README.md)
has all of those and Unicode. Its types are `Regexp`, `RegexpMatch`, and
`RegexpCapture`, with the same methods. To switch to it, import the package
with those names, rename the types, and add the options argument to
`compile`.

A pattern that does not parse raises `<bad-arg>` with `why`, the `pattern`,
and the zero-based byte `offset` of the problem.

### Matching

`match` returns the first match in the text, or NULL. `match_from` starts
at a byte offset. `find_all` returns every non-overlapping match as a
`List`. A `RegexMatch` is indexed by capture number, or by a name as a
`Symbol` or `String`. The whole match is capture 0. A capture that did not
take part is NULL, and so is one that matched no bytes, since an empty
`String` is NULL; `matched` distinguishes the two:

```x2c
~#include "regex.x"
~int main(void) {
Regex pair = Regex.compile("(\\w+)=(\\w*)");
foreach (RegexMatch found, pair.find_all("a=1 b= c=3"))
  printf("%s -> %s\n", found[1], found[2] ? found[2] : "(empty)");
~  return 0;
~}
```

`capture(key)` returns the `RegexCapture` behind an index, with `text`,
`start`, `end`, and `matched`. `capture_names` lists a pattern's names in
capture order, and `pattern` returns its text.

### Splitting and replacing

`split` returns the text between matches, keeping an empty field where two
matches touch or a match sits at either end. `replace` replaces the first
match and `replace_all` every match. In the replacement, `$0` through `$9`
and `${name}` insert a capture, and `$$` is a dollar sign. `replace_fn`
calls a function with each `RegexMatch` and inserts what it returns as is.
`Regex.escape` quotes a literal for use inside a pattern:

```x2c
~#include "regex.x"
~int main(void) {
Regex spaces = Regex.compile(" +");
List words = spaces.split("  two   words ");        // "", "two", "words", ""
String dated = Regex.compile("(\\d+)-(\\d+)")
  .replace_all("2026-09 and 2027-01", "$2/$1");      // 09/2026 and 01/2027
String shouted = Regex.compile("\\w+")
  .replace_fn("go now", %!(RegexMatch m) => m[0].upper());
~  return words.len() == 4 && dated[0] == '0' && shouted == "GO NOW" ? 0 : 1;
~}
```

A `Regex` is freed by the scope that made it, like any class value. Matching
backtracks, so a pattern with nested repetition such as `(a*)*b` can take
time exponential in the text; write the repetition once. A repeated byte or
set, such as `\w*`, matches any length, but a repeated group such as
`(?:ab)*` raises `<size-limit>` past 2,000 repetitions in one match.

## Comparing text

`diff.x` compares two texts line by line. `Diff.unified` returns the
difference the way `diff -u` prints it, with the two names in the header
and three lines of context around each change, or NULL when the texts are
the same line for line. This check compares a command's output with
expected output stored in a file:

```x2c
~#include "diff.x"
~#include "path.x"
~#include "process.x"
~int main(void) {
String expected = Path.read_text("unittest/expected/help.txt");
String actual = %(./x2c --help).job().output();
String report = Diff.unified(expected, actual, "expected", "actual");
if (report) Stderr.printf("%s", report);
~  return report ? 1 : 0;
~}
```

`Diff.lines` returns the edits themselves: a `List` of `(same line)`,
`(delete line)`, and `(insert line)` forms in order, with line endings
removed:

```x2c
~#include "diff.x"
~int main(void) {
foreach (List edit, Diff.lines("a\nb\n", "a\nc\n")) {
  (Symbol kind, String line) = edit;
  if (kind != <same>) printf("%s %s\n", kind.str(), line);
}
~  return 0;
~}
```

```text
delete b
insert c
```

The edits are a shortest script for texts that are mostly alike. Past two
thousand edits the differing middle is reported as one run of deletions and
one run of insertions.

## JSON

A script that reads or writes JSON includes `json.x` itself:

```x2c
#include "json.x"
```

The names in `json.x` match the converting surface of the
[`yyjson` package](https://github.com/gwf/x2c/blob/main/packages/yyjson/README.md).
To switch a script to the package, replace that line with
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
`indent=2` and `sort_keys=True`. A bare key in a `{}` literal is a `Symbol`,
which is written as a string, and `Json.bool` makes a boolean. A `Map` or
`Array` variable passes to the writers as a `Var`:

```x2c
~#include "json.x"
~int main(void) {
Map report = {name: "x2c", passed: Json.bool(1), counts: [3, 0]};
printf("%s\n", Var.pretty_json(report));
Json.write_file(report, "/tmp/report.json");
~  return 0;
~}
```

Text that is not JSON raises `<bad-arg>` with `why`, a zero-based byte
`offset`, and one-based `line` and `column` details; `Json.read_file` adds
the `path`. Parsing raises the same cause for nesting deeper than 512 arrays
and objects, a number too large for a `double`, an unpaired surrogate
escape, and `\u0000`, which a `String` cannot hold:

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
or an infinity. A `String` that is not valid UTF-8 is written with U+FFFD in
place of each ill-formed byte sequence, the same text that Python and
JavaScript produce when they decode those bytes, so the output is always
UTF-8 that `Json.parse` accepts.

The package keeps what a `Map` cannot: object order, duplicate names, and
whether a number was signed, unsigned, or real. Its converted integers are
`long long` or `unsigned long long` values, which do not compare equal to an
`int` literal such as the 5 in `{n: 5}`. The package raises `<malformed>`
for malformed text.
