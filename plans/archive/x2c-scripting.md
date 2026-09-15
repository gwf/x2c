# x2c scripting

> Status: done - 2026-09-15. Phase 1 cb176c0, phase 2 6861d32, phase 3
> 85c1fd9, and phase 4 in the commit that archived this plan, all on `main`.
> Phase 1 notes: a private `extern` declaration lost `extern` in generated C
> (fixed in `src/generate.x`, fixture `private-extern-declaration`). `walk`
> returns a `List`, not an `Iter`. `glob` uses the manifest `**` matcher
> rewritten to try only component boundaries.
> Phase 2 notes: `src/` is 422 lines deleted and 157 added. `ChildProcess`,
> `process_run`, `x2c_path_dir`, `x2c_path_stem`, `SourceView.path`, the
> install directory helpers, and the manifest glob matcher are gone; the
> manifest glob no longer backtracks exponentially or matches mid-component.
> `_build_mkdirs` and `_build_remove_tree` remain as boolean adapters so
> bootstrap and install keep their messages, and a tool that cannot start
> still reports status 127. Self-translation of `src/*.x` at `-j 1` took
> 3.31-3.51 s against 3.38-3.50 s before. An uncaught `<cmd-fail>` aborts
> with the error-floor report, so Phase 4's synthesized `main` should report
> a failed command and exit with its status.
> Phase 3 notes: on this Mac `x2c script` on the language tour takes 0.29 s
> cold and 14 ms warm, against 0.17 s for a warm `run --build-dir`; hashing
> the compiler binary on every run stayed inside the 15 ms budget, so no
> identity shortcut was added. The record is the build-state file with one
> prerequisite path per line after the fingerprint, not a separate depfile.
> The executable is published by rename after the build, and the record is
> written after the rename.
> Phase 4 notes: the design changed in three places. A script's statement
> runs are skipped where they appear and, at end of file, rejoined into a
> token stream the ordinary parser reads as `static int x2c_script(argc,
> argv, args)` plus a `main` that calls it inside a `try`, rather than an
> AST built through `bind_syntax`; macro templates carry partly typed
> syntax, so hand-built function syntax was not reliable. The statements
> live in their own function so the `try` does not make their locals
> `volatile`. The shebang line reads as `#include "scripting.x"`, a new
> optional module that includes `path.x` and `process.x`, instead of new
> implicit-include plumbing. The planned `parallel-jobs` example was folded
> into `line-counts`, which already caps its jobs with `Job.wait_any`.
> Follow-up round 4a19965 and b4debf9: a script's local `.x` includes build
> and link with it; the cache also watches the directories the build
> searched, so the three changes it used to miss now rebuild; `walk` became
> a lazy `Iter`; globs skip leading dots as a shell does, in manifests too;
> `modified_time` keeps fractions; `x2c script --clean` and pruning of
> entries whose script is gone; `examples/scripts/parallel-jobs.x` was
> written after all. File-scope conditionals around `static` declarations
> were broken in the generated C and are fixed.

## Context

x2c already has most of what a scripting language needs:

- **Fast turnaround.** `x2c run` on the language tour takes 0.28s cold, and
  the program itself runs in ~5ms.
- **Safe argument lists.** A `%(git log $range)` literal already works as a
  shell-free argv. Each element's `.str()` is exactly one argument, and a
  `$hole` stays one argument even when it contains spaces.
- **Failure handling.** Structured `Error`s, `catch`, and `$auto` cleanup
  cover `set -e`-style failure and zombie-free child processes.

A throwaway 103-line library (`.context/scripting-spike/sh.x`) ran commands,
captured output, piped three stages, listed a directory, waited on
background jobs, and caught a failing command, all in today's x2c.

Four things are missing:

1. A runtime API for processes and the filesystem. `lib/` has only
   `File.popen`, which goes through `/bin/sh`.
2. A way to launch a script from a shebang line.
3. A warm start fast enough for scripts. Today it is 170ms, because executables
   always relink, cc re-preprocesses every source, and macOS checks each newly
   linked binary on first launch (~100ms).
4. Scripts without `main`.

The compiler also carries private copies of the same process and filesystem
code. The new modules would replace those copies.

## Settled decisions

Gary's choices:

- **Command.** `x2c script [options] <file.x> [args...]`, keeping x2c's
  subcommand-first CLI. The shebang is `#!/usr/bin/env -S x2c script`.
- **Cache freshness.** A dependency-file check. The cached binary is reused
  when all of these are unchanged:
  - the script
  - every file listed in its translation and compile depfiles
  - the compiler, the runtime archive, and the C compiler
  - package archives, options, and `CPATH`/`C_INCLUDE_PATH`/`LIBRARY_PATH`/`SDKROOT`

  Three changes go unnoticed until `--rebuild`: a new header shadowing an old
  one, a `__has_include` result flipping, and `-l` resolving to a different
  library.
- **Commands are methods on the argv `List`.** The spelling is
  `%(git fetch).run()`.
- **Filesystem operations are methods on path `String`s.** The spelling is
  `dir.list_dir()`.

Carried from the spike and accepted:

- Two optional runtime modules, `lib/process.x` and `lib/path.x`, that script
  units include automatically.
- A `#!` first line marks a script unit.
- A new shared error cause, `<cmd-fail>`.

Consequences settled here:

- **Options.** C has no optional parameters, so options attach through
  `List.options(Map)` rather than a trailing argument.
- **Interactive job control is out of scope.** That means fg/bg, `SIGTSTP`,
  and `tcsetpgrp`. Scripts get background jobs, wait, and kill.
- **Scripts are single-file** plus packages and the runtime. Including a
  local `.x` helper module is a later follow-up, because nothing compiles
  that helper's `.c`.

## Phase 1 - `lib/process.x` and `lib/path.x`

This phase adds public runtime API. Both modules are optional: they stay out
of `lib/Makefile` `SOURCES` and are listed in `OPTIONAL_SOURCES`.

### process.x

**Command shapes.**

- An argv `List` has elements whose `.str()` is one argument each.
- A pipeline is a `List` whose first element is itself a `List`, as in
  `%((ls -1 $dir) (grep x) (wc -l))`.
- `List.options(List command, Map options)` returns a command carrying an
  options `Map`, with the Map as its first element.
- `List.pipe(List command, List next)` returns a pipeline. If the receiver is
  already a pipeline, it appends.

**Operations.** None go through a shell. A pipeline fails if any stage fails.

| Operation | Behavior |
| --- | --- |
| `void List.run(List command)` | Inherits stdio. Raises `<cmd-fail>` with `(command ...) (status N)` on a non-zero exit. |
| `int List.status(List command)` | Returns the exit status, or 128+signal. Never raises `<cmd-fail>`. |
| `String List.output(List command)` | Returns captured stdout. Raises `<cmd-fail>`. |
| `List List.lines(List command)` | Returns stdout lines without their terminators. |
| `Job List.start(List command)` | Starts a background job. |

**Option keys.**

- `dir:` working directory, via `chdir` in the child.
- `env:` a Map of variables set in the child.
- `input:` a String fed to the first stage's stdin.
- `stdout:` a path, or `<capture>`.
- `stderr:` a path, `<stdout>`, or `<capture>`.

An unknown key raises `<bad-arg>`, so a typo such as `cwd:` can't run a
command in the wrong directory.

**`Job` is a heap class.** It uses one of the 32 custom boxing slots.

- Operations: `ready`, `wait` (returns status), `check` (raises
  `<cmd-fail>`), `kill(sig)`, `output`, `errors`, and receiverless
  `Job.wait_any(Array jobs)`.
- It adopts `Cleanup`: a live job gets `SIGTERM` and is reaped, so
  `$auto(%(...).start())` never leaks.

**Implementation.**

- Move `process_start`, `ChildProcess.ready`, `ChildProcess.wait`,
  `_cpp_status` and `_cpp_wait` from `src/utils.x:249-384` into `Job`.
  That code uses fork, `chdir`/`setenv`/`dup2` in the child, then `execvp`.
  It works on macOS, Linux, and Cosmopolitan.
- Capture uses temporary files, as `ChildProcess` does today, which avoids
  pipe deadlock. Pipelines use `pipe()` between stages.
- A failed `execvp` exits 127 with a diagnostic, as today. `run`/`output`
  raise `<not-found>` when the program cannot be found.
- `List process_arguments(int argc, char **argv)` returns `argv[1..]` as
  Strings. Implicit `main` (Phase 4) uses it.

### path.x

Every operation is a method on `String`, named so it can't be confused with
text operations:

- **Path parts:** `join_path`, `dirname`, `basename`, `stem`, `extension`,
  `absolute_path`.
- **Queries:** `exists`, `is_dir`, `is_file`, `file_size`, `modified_time`.
- **Listing:** `list_dir` returns names sorted, without `.` and `..`.
  `walk` returns an `Iter` of paths. `glob` uses `glob(3)`.
- **Changes:** `make_dirs`, `remove_file`, `remove_tree`, `copy_file`,
  `copy_tree`, `move_to`, `symlink_to`.
- **Content:** `read_text` and `write_text`, building on `File.string_close`
  and `File.write_all`.
- **Temporary directory:** `String.temp_dir()`, removed by `remove_tree`.

Failures raise `<not-found>` or `<io-fail>` with `(operation ...) (path ...)`.
The code comes from `_build_mkdirs` and `_build_remove_tree`
(`src/build.x:175`, `:862`) and from `_entries`, `_read_text` and
`_write_text` (`src/install.x:66-103`).

### Shared cause

Add `cmd-fail` to `lib/error-macros.xmacro`. Also update:

- the count in `unittest/test-error.x:205`
- the table in `docs/src/guide/exceptions.md`

### Tests, docs, and examples

- **Unit suites.** Add `unittest/test-process.x` and `unittest/test-path.x`,
  and register them in `unittest/test-all.x` ahead of the var saturation
  test. Cover:
  - argument fidelity (spaces, a leading `-`)
  - exit and signal status
  - pipefail
  - `input:`/`stdout:`/`stderr:` routing
  - `dir:`/`env:`
  - unknown option keys
  - `wait_any`, `kill`, and `$auto` cleanup
  - every path operation against a temp directory
- **Book.** Add rows to `docs/library-manifest.txt`, `PRIMARY_EVIDENCE` entries
  in `tools/gen-api-reference.py`, `/**` docs on the public API, and a guide
  chapter `docs/src/guide/scripting.md` in `SUMMARY.md`. Then run
  `make doc-generate`.
- **Example.** Add `examples/scripts/repo-stats.x`, built with a `main` in
  this phase, with a manifest row and expected stdout.

## Phase 2 - The compiler uses the modules

This phase changes no behavior. It is a deletion.

- **`src/utils.x`.** Delete `ChildProcess`, `process_start`, `process_run`, and
  the status helpers. `worker_fork`, `worker_exit` and `worker_wait` stay:
  they continue the current process and are not command execution.
- **`src/toolchain.x`.**
  - `ToolRun` holds a `Job`. `ToolAction.start` calls `List.start` with
    `stdout:`/`stderr: <capture>`, or inherits stdio for programs.
  - `_action_argv` is deleted.
  - Verbose printing (`_print_action`) stays.
- **`src/install.x`.** `_argv`, `_run`, `_read_text`, `_write_text`, `_is_dir`,
  `_entries` and `_files_with` become calls into the modules. `_copy_tree`
  uses `copy_tree` instead of shelling out to `cp -R`.
- **`src/build.x`.** `_build_mkdirs` and `_require_directory` become
  `make_dirs`. `_build_remove_tree` becomes `remove_tree` inside a catch that
  keeps the `Build.cleanup` warning.
- **`src/utils.x`.** `x2c_path_dir` and `x2c_path_stem` become `dirname` and
  `stem` wherever the semantics match exactly. Keep them otherwise.
- **Measure.** Record authored lines deleted and added. A bootstrap translate
  time within noise of before is the check that nothing regressed.

## Phase 3 - `x2c script` and the executable cache

### CLI (`src/cli.x`)

- Add `CLI_SCRIPT = 16` (the unused bit) and a `cli_commands` row: "Build a
  script once and run it".
- `CLI_SCRIPT` joins the masks of these option groups:
  - translation: `-I`, `--x-include-dir`, `--c-include-dir`,
    `--c-system-dir`, `--package-dir`, `--source-map`
  - C compiler: `--cc`, `-O*`, `-g`, `-D`, `-U`, `-Xcc`, `-pthread`
  - linker: `-L`, `-l`, `-Wl,`, `-framework`, `-Xlinker`
  - general: `-h`, `-v`, `-###`, `--debug`, `--plain`, `--color`
  - a new `--rebuild`

  It does not join target, manifest, output, build-dir, temps, or
  compile-commands.
- **Argument rule.** Options end at the first non-dashed word, which is the
  script. Every later word goes to `run_args` verbatim, including `--`,
  `--help` and `@x`.
  - `_expand_argument` expands `@` files only before the script.
  - Exactly one script operand is required; the existing `.x` input validation
    applies to it.
- **Help and dispatch.**
  - Add a `_print_help` case and help text.
  - Update the command list in the `help` text (`cli.x:478`).
  - In `main.x:625`, `<script>` dispatches to `script_command(request)`.

### Cache and exec (new `src/script.x`)

This file owns the script command, as `install.x` owns packages.

**Cache directory.**

- The root is `X2C_CACHE_DIR`, else `$XDG_CACHE_HOME/x2c`, else
  `$HOME/.cache/x2c`. That follows `etc/cosmopolitan/setup-toolchain.sh`.
- Each script gets `<root>/scripts/<stem>-<hash(realpath)>/`.
- Add an `x2c env cache_dir` row in `_run_env` (`main.x:528`).

**Fast path.**

1. Parse `<dir>/script.d`, the union prerequisite depfile.
2. Compute the fingerprint:
   - `_state_base`: the x2c executable and the cc tool
   - the script's realpath
   - include dirs, package roots, `cpp_args`, `cc_args`, `ld_args`, and
     source-map
   - the four environment variables
   - the contents of every prerequisite
3. If the fingerprint matches `<dir>/.x2c-state/script` and `<dir>/run`
   exists, `execv` the binary.

Reuse the hashing helpers in `src/build.x:56-170` by exporting a
`Build`-level fingerprint function; don't duplicate them.

**Slow path.**

1. Take `flock` on `<dir>/lock`, then re-check the fast path.
2. Build through the existing `_run_build_request` path, exporting it from
   `main.x`. Settings: `build_dir = <dir>`, output `<dir>/run.<pid>`, quiet.
3. `rename` the output to `<dir>/run`. The rename keeps other processes that
   are still running the old binary safe; writing the file in place fails with
   ETXTBSY on Linux.
4. Write `script.d` from three sources:
   - the translation depfile `gen/<key>/<stem>.d`
   - the compile depfile `dep/<key>.d`
   - `runtime_lib` and the package `native_inputs`

   Use the existing depfile writer in `src/deps.x`.
5. Write the state with `_state_write`, then `execv`.

**Exec details.**

- `argv[0]` is the script path, so the program sees `argv[1..]` as its
  arguments.
- Call `fflush(NULL)` before `execv`.
- If exec fails, report `x2c_driver_error`.
- Exec, rather than a child process, gives the program x2c's pid, signals, and
  exit status directly.

**Hash-cost gate.** If hashing the 1.6 MB compiler binary makes a warm start
exceed 15ms for `tour.x` on this Mac, hash it once and key the result on path,
size, mtime and inode. Record the measurement either way.

### Shebang line

`_read_input_text` (`src/frontend.x:101`) replaces the bytes of a leading `#!`
line with spaces, keeping the newline. That covers every primary input, so
line numbers, token `pos`, and collection are unchanged, and a shebang file
also works with `translate`, `build` and `run`. Document it under "Source
files and pragmas" in `docs/src/reference/language.md`.

### Docs and tests

- **`docs/src/reference/cli.md`.** Add a "Run a script" section covering:
  - the shebang forms: `env -S`, or a direct interpreter path with a single
    `script` argument
  - the cache location and the freshness contract, including the three
    changes it misses and `--rebuild`
  - quiet success and diagnostics on failure
- **Help fixtures.** Regenerate `cli-top.help` and `cli-help.help`, and add
  `cli-script.help` to the diff list in `unittest/probes/run-cli-boundary.sh`.
- **CLI probe.** Add a block to `run-cli-boundary.sh` that checks:
  - arguments including `--`, `--help`, `@x` and spaces reach the program
  - the exit status propagates
  - a shebang file runs when executed directly
  - a warm `-v` run shows no translate, preprocess, compile or link
  - editing an included `.xmacro` or the script rebuilds
  - `--rebuild` rebuilds
  - two concurrent first runs both succeed
  - a build error prints diagnostics and exits non-zero

## Phase 4 - Script units without `main`

This phase changes public language semantics. A source file whose first line
is `#!` is a script unit, and these rules apply.

**What stays at file scope.**

- preprocessor lines
- `import`, `protocol` and `static protocol`
- `macro` and `keyword` definitions
- top-level `$(...)` Lisp
- unit-macro invocations, identified by
  `macro_starts_target_at(AST_UNIT)` (`src/macros.x:668`)
- typedef, struct, union and enum definitions
- function prototypes and definitions: a declaration whose first
  depth-0 terminator is `{` or `=>`, or whose declarator is a function
- `static` and `extern` declarations

**Everything else is a statement.**

- Statements are gathered in order into a synthesized
  `int main(int argc, char **argv)` whose body starts with
  `List args = process_arguments(argc, argv);`.
- Object declarations without `static` or `extern` become locals of `main`.
  Functions can't see those locals; lambdas capture them as usual.
- `return N;` at top level sets the exit status. Falling off the end
  returns 0.
- Without any top-level statements, nothing is synthesized, so an ordinary
  `main` still works.
- Script units include `process.x` and `path.x` automatically, as though the
  file began with those includes.

### Implementation

1. **Classifier.** Add `Compiler.script_item_is_statement()` in
   `src/parse.x`. It does not consume tokens. It builds on
   `_test_declaration_start` (`parse.x:978`) and the checks
   `parse_top_level` already makes (`parse.x:1498-1546`). Full parse and
   shallow collection both use it.
2. **Full parse** (`Compiler.full_parse`, `src/compiler.x:1299-1355`), in a
   script unit, for each item the classifier calls a statement:
   - push a persistent `SymScope` with `Sym.push_scope` (`compiler.x:2910`)
   - set `return_type` to int and `fn_name` to `main`
   - parse the item with `parse_block_item` (`src/statements.x:383`)
   - pop the scope

   Definitions parse between statements with that scope popped, so script
   locals never leak into function bodies. At end of file, build
   `(function int (bind main ((fnmod (params ...)))) (block ...))` through
   `bind_syntax` at `AST_UNIT` (`parse.x:2048-2085`), the path Unit macros
   use. Append it to the AST so `_modify_main` (`src/generate.x:868`) inserts
   `x2c_initialize()`.
3. **Shallow collection** (`_shallow_parse_loop`, `compiler.x:1096`). In a
   script unit, skip each item the classifier calls a statement. Nothing
   imports a script, so collection needs only its file-scope forms. The
   skipper is `_sync_top_level` (`compiler.x:1269`), extended to continue past
   a closing brace followed by `else`, `catch`, `finally` or `while`.
4. **Script flag.** `ParsedUnit` marks the primary unit as a script when
   `_read_input_text` blanks a shebang. The flag never applies to includes,
   imports or `.xmacro` files.
5. **Prototype gate.** Before touching docs, check the classifier and parse
   against these:
   - the language tour rewritten as a script
   - `if`/`else`, `foreach`, `try`/`catch`/`finally`, `match`,
     `do`/`while`, labels, `$auto`, `$let(...) { }`, `defer`, `with`
   - a statement macro and a unit macro
   - a top-level lambda capturing a script local
   - a function defined after the statements that use it

   If the full-parse and collection passes disagree on any item, stop and
   revise the design with Gary.

### Docs, fixtures, and examples

- **Language reference.** Add a "Script units" section to
  `docs/src/reference/language.md` covering file scope vs `main`, `args`,
  exit status, and auto-includes.
- **Guide.** `docs/src/guide/scripting.md` switches to shebang scripts.
- **Compiler fixtures.** Add fixtures under `unittest/compiler-fixtures` for
  generated C of a script unit, with statements interleaved with functions and
  types.
- **Examples.** `examples/scripts/repo-stats.x` becomes a shebang script. Add
  `examples/scripts/parallel-jobs.x`, which uses `Job.wait_any` to cap
  concurrency.

## Measurements to record

| Measurement | Before | Target |
| --- | --- | --- |
| `x2c script tour.x`, cold | ~0.28s | ≤ 0.35s |
| `x2c script tour.x`, warm | 0.17s (run with `--build-dir`) | ≤ 15ms |
| Authored lines, Phase 2 | - | record deleted and added |
| Bootstrap translate time, Phase 2 | - | unchanged within noise |

## Verification

- **Per edit.** `make x2c` plus the focused checks for that phase:
  - `(cd unittest && ./test-all process_suite path_suite)`
  - `./unittest/probes/run-cli-boundary.sh`
  - the new compiler fixtures
  - `examples/check.sh` for the script examples
- **End to end.**
  1. `chmod +x` an example.
  2. Run it directly.
  3. Run it again with `-v` and confirm no build actions.
  4. Edit the script and confirm a rebuild.
  5. Pipe its output through `wc -l`.
- **Per phase before delivery.** Integrate current `origin/main`, then run
  `git diff --check` and `tools/gate-state.py ensure agent-pr-check`. Each
  phase lands on `main` in order, never stacked.

## Plan review

**Trusted facts.**

- `execvp` failure maps to 127 and signals map to 128+N in the moved child
  code, and nobody re-checks either.
- The Error protocol already guarantees non-returning `<cmd-fail>`/`<io-fail>`,
  so no success checks follow `run`, `output`, or path writes.
- The translation and compile depfiles already list their prerequisites. The
  script cache hashes them rather than re-deriving includes.
- `_modify_main` already initializes any `main` of the canonical shape.

**Deleted or reused.**

- Phase 2 deletes the compiler's `ChildProcess`, `_argv` ×2, `_action_argv`,
  the install text/dir helpers, `_build_mkdirs`/`_build_remove_tree`, and the
  `cp -R` shell-out.
- The build path, fingerprint helpers, depfile parser/writer, `_state_write`,
  `Sym.push_scope`, `bind_syntax(AST_UNIT)` and `_sync_top_level` are all
  reused.

**New lasting mechanisms.**

| Mechanism | Why |
| --- | --- |
| The two modules | Public capability. |
| `script.d` union depfile | The only way the warm path knows what to hash without translating. |
| `flock` | Two first runs would otherwise write the same `gen/`/`obj/` files at once. |
| Rename-into-place | Avoids ETXTBSY and a torn binary for concurrent runners. |
| Script-statement classifier | Needed so collection and full parse agree. |
| `script` CLI rule | Needed so shebang arguments reach the program. |

**Idiom.** Commands are ordinary Lists and paths are ordinary Strings, with
methods added by optional modules, following the `String.open` precedent.
Failure is the shared Error protocol, and cleanup is `Cleanup`/`$auto`.
There is no shell grammar, builder framework, or second process model.

**Validators and diagnostics.**

- An unknown option key raises `<bad-arg>`. It protects against a command
  running with an ignored `dir:`/`env:`/`input:`, which is wrong and possibly
  destructive.
- `script` with no operand, or with a non-`.x` operand, uses the existing
  input validation.
- No other new validators, dedicated diagnostics, or negative fixtures.
  A script that has top-level statements and also defines `main` gets the
  C compiler's redefinition error; no extra check is added.

**Implementation review.** Each phase ends by reviewing and fixing its
completed authored diff before the publication gate.
