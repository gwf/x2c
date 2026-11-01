/*  requests.x -- request defaults and input checks

    Copyright (c) 2026 Gary William Flake.
*/

// native products

static TargetKind target_kinds[] = {
  { <executable>, "executable",     "executable",     "",    ""    },
  { <static-lib>, "static-library", "static library", "lib", ".a"  },
  { <module>,     "meta-module",    "native module",  "",    ".so" },
  { 0 }
};

static macro Stmt $fail.cli_input_not_file(Expr $input) =>
  Diagnostics.driver_error(%"input is not a regular file: $($input)");

static macro Stmt $report.cli_input_directory(Expr $input) {
  fprintf(stderr, "x2c: error: input is a directory: %s\n", $input);
  fputs(
    "note: pass source files, use a shell wildcard, or define a "
    "manifest target\n", stderr);
}

static macro Stmt $report.cli_input_missing(Expr $input) =>
  fprintf(stderr, "x2c: error: input does not exist: %s\n", $input);

/** Returns the target kind spelled `spelling`, or 0 when no kind has that
    spelling. `refusal` says why this compiler refuses a known spelling, and
    is NULL otherwise.
*/
Symbol TargetKind.named(String spelling, String &refusal) {
  refusal = spelling == "shared-library" ?
    "shared-library is not supported by this compiler" : NULL;
  for (TargetKind *row = target_kinds; row.kind; row++)
    if (spelling == row.spelling) return row.kind;
  return 0;
}

/** Returns the row of target kind `kind`; any other kind reads as an
    executable.
*/
TargetKind *TargetKind.of(Symbol kind) {
  for (TargetKind *row = target_kinds; row.kind; row++)
    if (row.kind == kind) return row;
  return target_kinds;
}

// requests

/** Constructs a request with the command's ordinary CLI defaults. */
CliRequest CliRequest.new(Symbol command) {
  CliRequest request = xcalloc(1, sizeof(struct CliRequest));
  request.command = command;
  request.source_map = command in %<build run>;
  request.jobs = _default_jobs();
  request.max_errors = 20;
  if (command in %<build run script>) request.kind = <executable>;
  return request;
}

/** Returns the version line `--version` prints, without a newline. */
String Compiler.version(void) => "x2c 0.15.1";

/** Returns whether `request` selects a terminating inspection or dump mode. */
int CliRequest.inspects(CliRequest request) => request.dump != 0;

/** Returns the package roots `request` searches: its explicit `--package-dir`
    and manifest directories in order, then the home's `packages/` directory
    when it exists. A root named twice is searched twice and resolves the
    same entries. Explicit directories are borrowed; the result is a fresh
    `List` only when the home directory is appended.
*/
List CliRequest.package_roots(CliRequest request) {
  String home = Compiler.home_packages();
  if (!Path.is_dir(home)) return request.package_dirs;
  return request.package_dirs.append(cons(home, NULL));
}

/** Exits with a driver error unless `input` names a regular file.
    A wildcard or directory operand adds a note on what to pass instead.
*/
void CliRequest.require_input(String input) {
  if (!input) Diagnostics.driver_error("input path is empty");
  if (Path.is_file(input)) return;
  if (Path.is_dir(input)) {
    $report.cli_input_directory(input);
    exit(2);
  }
  if (Path.exists(input))
    $fail.cli_input_not_file(input);
  $report.cli_input_missing(input);
  if (strpbrk(input, "*?["))
    fputs("note: x2c does not expand wildcard operands\n", stderr);
  exit(2);
}

// request defaults and input checks

// An outer Make owns concurrency unless the caller explicitly supplies -j.
static int _default_jobs(void) {
  if (_make_owned()) return 1;
  long count = sysconf(_SC_NPROCESSORS_ONLN);
  return count > 0 && count <= INT_MAX ? (int) count : 1;
}

/* Reports whether a parent Make recipe runs this process, which `MAKELEVEL`
   set to a positive count shows. Parallel recipes share one terminal and
   one job budget without sharing reporter state. */
static int _make_owned(void) {
  String level = Env.get("MAKELEVEL");
  return level.is_digit() && atol(level) > 0;
}
