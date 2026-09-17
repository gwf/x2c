> Status: done
> Delivered 2026-09-17 with the commit that archives this plan. Gary approved
> the starter program. Symbol collection misreads a line-leading `#include`
> inside a percent string, so `new_command` inserts that line as `${"..."}`;
> the defect is recorded in `unittest/STATUS.md`.

# Start a project with `x2c new`

## Result

`x2c new <dir>` creates a project that builds and runs with no edits:

```sh
x2c new hello
cd hello
x2c run -q            # Hello, world!
x2c run -q -- Gary    # Hello, Gary!
```

It writes three files and nothing else:

```text
hello/x2c.toml
hello/src/main.x
hello/.gitignore
```

`x2c.toml`:

```toml
[target.hello]
sources = ["src/*.x"]
```

`src/main.x`:

```c
/*  main.x -- greet the name given on the command line */

#include <stdio.h>

int main(int argc, char **argv) {
  String name = argc > 1 ? argv[1] : "world";
  puts(%"Hello, $name!");
  return 0;
}
```

`.gitignore`:

```text
.x2c-build/
```

The program is ordinary C with one x2c feature on the line that prints.
Someone new to x2c first sees C that compiles, then one change that C cannot
express.

## Settled choices

- **Operand.** Exactly one directory path. The target name is the last
  component of its absolute path, so `x2c new .` inside an empty
  `my-tool/` names the target `my-tool`.
- **Existing paths.** The directory may be missing or empty. A non-empty
  directory, or a path that names a file, is refused with status 2 before
  anything is written. `x2c new` never overwrites a file.
- **Names.** The target name must pass the manifest's existing name rule
  (`_name_ok` in `src/project.x`: letters, digits, `_`, `-`). Otherwise the
  command refuses with status 2 and says which characters are allowed.
- **Manifest.** Only the target section. A single target is selected
  without `default-target` (`src/project.x:674-679`), and the build
  directory defaults to `.x2c-build` (`src/project.x:687-692`). Adding
  `[project]` would put lines in front of a newcomer that do nothing yet.
- **Options.** `-h`/`--help` and `-q`/`--quiet`. On success it prints
  `x2c: created <dir>`, the same form as `install` and `remove`; `-q`
  suppresses it.
- **No templates, no `git init`, no library/executable choice.** One
  starter project. A library target is one manifest line the reader can add
  from the manifest chapter.

## Evidence

A probe in the session scratchpad with `builds/0/x2c` at d63ab04 created the
three files by hand:

- `x2c run` built `.x2c-build/hello` (404.9 KiB) and printed
  `Hello, world!` with status 0; `x2c run -q -- Gary` printed
  `Hello, Gary!`.
- `x2c build` succeeded, and `x2c run` from `src/` found the manifest in
  the parent directory.
- `x2c run -q Gary` without `--` fails with
  `input does not exist: Gary`, so the documentation shows `--`.

The compiler already supports every file `new` writes. The work is the command
that writes them.

## Implementation

1. **`src/cli.x`.** Add `CLI_NEW = 1024` and the row
   `{ <new>, CLI_NEW, "Create a project that builds and runs" }` after
   `run`. Add `CLI_NEW` to the `<help>` and `<quiet>` option masks. In
   `_parse_command`, require exactly one operand with the existing
   `"${name} requires exactly one operand"` check used by
   `install`/`remove`. Add `_print_new_help` beside `_print_package_help`
   and the `<new>` case in `_print_help`, and add `new` to the `help help`
   text.
2. **`src/project.x`.** Add `int new_command(CliRequest request)`, which
   owns manifests and already has `_name_ok`. It resolves the name from
   `Path.absolute(dir)`, refuses a non-empty directory with
   `Path.list_dir` or a non-directory with `Path.exists`, calls
   `Path.make_dirs` on `<dir>/src`, and writes the three files with
   `Path.write_text` from `%"..."` literals. `Path` operations raise
   `<io-fail>` or `<not-found>`, which one `catch` reports through
   `x2c_host_error`, as `remove_command` does. No rollback: a write failure
   reports the path and leaves whatever was written, and rerunning refuses
   because the directory is no longer empty.
3. **`src/main.x`.** Dispatch `<new>` beside `install`, `remove`, and
   `list`, before `Frontend.load_support`. It needs no compiler state.
4. **Book.** In `docs/src/reference/cli.md`, add `new` to the command list
   in the opening paragraph and add a `## Start a project` section before
   `## Project manifests` that shows the command, the three files, and the
   `x2c run -q -- Gary` line. In `docs/src/guide/installation.md`, open
   `## Build, debug, and use packages` with the three-line
   `x2c new hello` example and a link to that section.
5. **Probe.** In `unittest/probes/run-cli-boundary.sh`, add `new --help`
   against a new `unittest/compiler-fixtures/cli-new.help`, and update
   `cli-top.help` and `cli-help.help`. Then create a project under
   `$BUILD`, run it with `-q`, and compare stdout to `Hello, world!`.
   Finally, run `new` again on that now non-empty directory and check
   status 2 with `x2c.toml` unchanged.
6. **Generated files.** `make doc-generate` for the compiler API reference
   (`new_command` is exported) and `llms.txt`.
7. **Review.** Review and fix the completed authored diff for repeated
   checks, reuse of `install.x`/`project.x` helpers, and style, then run
   `tools/gate-state.py ensure agent-pr-check` and deliver to `main`.

## Plan review

- **Trusted facts.** `Path.make_dirs`, `Path.write_text`, and
  `Path.list_dir` raise on failure; the command checks no return values.
  `_name_ok` is the manifest parser's own rule, so a name `new` accepts
  always parses. The command does not build the project to check it; the
  probe establishes that once.
- **Reuse.** Command table, option masks, the one-operand check, help-row
  printing, `_name_ok`, `Path` operations, `x2c_host_error`, and the
  `x2c: <verb> <path>` message form all exist. The only new function is
  `new_command`, plus its help printer, which every command has.
- **Idiom.** Three multiline `%"..."` literals and direct `Path` calls in
  one function. No template engine, template directory, or scaffold data
  file.
- **Validators and negative checks.** Two refusals, each protecting
  deliberate public behavior: a non-empty directory (protects existing user
  files from being overwritten) and an invalid name (a manifest that
  `build` would reject as `unknown manifest section`). One negative probe
  covers the first. The name refusal has no dedicated fixture.
