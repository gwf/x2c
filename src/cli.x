/*  cli.x -- x2c command-line parsing and presentation.

    Copyright (c) 2026 Gary William Flake.

    Each option is one table row: the commands that accept it, its
    spellings, its help text, and the request field it sets. Parsing and
    help read the same rows.
*/

#pragma once
#include "sourceview.x"

/** Holds one compiler command and its command-specific inputs and options.
    `List`s produced by `CliRequest.parse` preserve CLI order. Copies are
    shallow: request storage and referenced canonical values keep their
    producing `Scope` and pool lifetimes.
*/
typedef struct CliRequest {
  Symbol command, List inputs, run_args, include_dirs, package_dirs, cpp_args;
  List cc_args, ld_args, native_modules, extensions;
  // Package roots for generated registration units during collection.
  Map collection_packages;
  String out_dir, dep_file, dep_target, manifest;
  String target, profile, output, build_dir, temps_dir, label, state_seed;
  String cc, meta_cc, ar, compile_commands, sha256, index, Symbol kind;
  String diagnostics_file, Symbol color_mode;
  // The one --dump-* option in force, or 0. Each prints and stops.
  Symbol dump;
  int jobs, debugging, verbose, dry_run, quiet, plain, no_deps;
  int no_phony_deps, compile_only, kind_explicit, save_temps, no_cpp;
  // The translation error limit; 0 reports every recoverable error.
  int max_errors;
  int source_map, source_facts, live_symbols, cpp_symbols;
  int force, rebuild, clean;
  // Repository build controls: a warning fails its unit; no .xi is read.
  int fatal_warnings, no_interfaces;
  SourceView sources;
} *CliRequest;

/** Describes one target kind: its spelling on the command line and in a
    manifest, the noun a report uses, and the default output file name
    around the target's name.
*/
typedef struct TargetKind {
  Symbol kind, String spelling, noun, prefix, suffix;
} TargetKind;

#include "system-macros.x"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "buffer.x"
#include "report.x"
#include "utils.x"

/* cli command reports. */

static macro Stmt $fail.cli_command_unknown(Expr $first) =>
  Diagnostics.driver_error(%"unknown command or global option '${$first}'");

static macro Stmt $fail.cli_operand_required(Expr $name) =>
  Diagnostics.driver_error(%"${$name} requires exactly one operand");

static macro Stmt $fail.cli_operands_forbidden(Expr $name) =>
  Diagnostics.driver_error(%"${$name} accepts no operands");

static macro Stmt $fail.cli_help_unknown(Expr $name) =>
  Diagnostics.driver_error(%"unknown help command '${$name}'");

static macro Stmt $fail.cli_option_value_forbidden(Expr $arg) =>
  Diagnostics.driver_error(%"option takes no value '${$arg}'");

static macro Stmt $fail.cli_option_value_required(Expr $arg) =>
  Diagnostics.driver_error(%"option requires a value '${$arg}'");

static macro Stmt $fail.cli_color_invalid(Expr $value) =>
  Diagnostics.driver_error(%"invalid color mode '${$value}'");

static macro Stmt $fail.cli_target_unknown(Expr $value) =>
  Diagnostics.driver_error(%"unknown target kind '${$value}'");

static macro Stmt $fail.cli_value_invalid(Expr $noun, Expr $value) =>
  Diagnostics.driver_error(%"invalid ${$noun} '${$value}'");

static macro Stmt $fail.cli_dependency_owned(Expr $value) =>
  Diagnostics.driver_error(%"C dependency option is driver-owned '${$value}'");

static macro Stmt $fail.cli_native_unsupported(Expr $arg) =>
  Diagnostics.driver_error(%"unsupported package native argument '${$arg}'");

static macro Stmt $fail.cli_option_unknown(Expr $arg) =>
  Diagnostics.driver_error(%"unknown option '${$arg}'");

// commands and options

static typedef struct CliCommand {
  Symbol name, const char *description;
} CliCommand;

static CliCommand cli_commands[] = {
  { <translate>, "Translate .x files to .c and .h files" },
  { <build>,     "Translate, compile, and optionally link a target" },
  { <run>,       "Build an executable and run it" },
  { <new>,       "Create a project that builds and runs" },
  { <script>,    "Build a script when it changes and run it" },
  { <env>,       "Show the resolved home, layout, and tools" },
  { <install>,   "Install a package into the home" },
  { <remove>,    "Remove an installed package" },
  { <list>,      "List installed packages" },
  { <help>,      "Show help for x2c or one command" },
  { 0 }
};

/* `spelling` is the text an argument must match, and is also the help label
   unless `label` overrides it. `alias` is a second accepted spelling, and
   `prefix` matches an option whose text continues in the same argument.
   An option with a request field sets it as `apply` says; each other
   option has an arm in _apply. */
static typedef struct CliOption {
  Symbol id, SymbolSet commands, Symbol group, String spelling;
  const char *value, *description, int hidden;
  String alias, label, int prefix;
  Symbol apply, int package_native;
  size_t offset;
} CliOption;

/* A command's help lists its option groups in this order. */
static typedef struct CliGroup { Symbol group, const char *title; } CliGroup;

static CliGroup cli_groups[] = {
  { <global>,     "Global options:" },
  { <target>,     "Target options:" },
  { <output>,     "Output options:" },
  { <source>,     "Translation options:" },
  { <package>,    "Package options:" },
  { <c-compiler>, "C compiler options:" },
  { <linker>,     "Linker options:" },
  { <inspection>, "Inspection options:" },
  { <general>,    "General options:" },
  { 0 }
};

#define CLI_FIELD(kind, field) .apply = kind, \
  .offset = offsetof(struct CliRequest, field)

static CliOption cli_options[] = {
  { <help>, %<<top translate build run script env install remove list new>>,
    <general>,
    "-h", NULL, "Show help and exit", 0, .alias = "--help" },
  { <version>, %<<top>>, <global>, "-V", NULL,
    "Show the x2c version and exit", 0, .alias = "--version" },
  { <verbose>, %<<translate build run script>>,
    <general>, "-v", NULL,
    "Show commands as they are executed", 0, .alias = "--verbose",
    CLI_FIELD(<flag>, verbose) },
  { <dry-run>, %<<translate build run script>>,
    <general>, "-###", NULL, "Show commands without executing them", 0,
    CLI_FIELD(<flag>, dry_run) },
  { <quiet>, %<<translate build run install remove new>>,
    <general>, "-q", NULL,
    "Suppress successful progress and receipts", 0, .alias = "--quiet",
    CLI_FIELD(<flag>, quiet) },
  { <plain>, %<<translate build run script>>,
    <general>, "--plain", NULL,
    "Use stable output without terminal rendering", 0, CLI_FIELD(<flag>, plain) },
  { <color>, %<<translate build run script>>,
    <general>, "--color", "<auto|always|never>", "Control terminal color", 0 },
  { <debug>, %<<translate build run script>>,
    <general>, "--debug", NULL, "Enable compiler debug logging", 0,
    CLI_FIELD(<flag>, debugging) },
  { <max-errors>, %<<translate build run script>>, <general>, "--max-errors",
    "<count>", "Stop after <count> errors per unit (default: 20)", 0 },
  { <diag-file>, %<<translate build run script>>, <general>,
    "--diagnostics-file", "<file>",
    "Write compiler diagnostics to <file> as JSON Lines", 0,
    CLI_FIELD(<text>, diagnostics_file) },
  { <fatal-warn>, %<<translate>>, <general>, "--fatal-warnings", NULL,
    "Fail a unit that reports a warning", 1, CLI_FIELD(<flag>, fatal_warnings) },
  { <no-iface>, %<<translate>>, <source>, "--no-interfaces", NULL,
    "Collect every unit cold without reading .xi interfaces", 1,
    CLI_FIELD(<flag>, no_interfaces) },
  { <out-dir>, %<<translate>>, <output>, "--out-dir", "<dir>",
    "Write generated files under <dir> (default: .)", 0,
    CLI_FIELD(<text>, out_dir) },
  { <src-map>, %<<translate build run script>>, <output>, "--source-map",
    NULL, "Map generated C locations to original x2c sources", 0,
    CLI_FIELD(<flag>, source_map) },
  { <no-deps>, %<<translate>>, <output>, "--no-deps", NULL,
    "Do not write x2c dependency files", 0, CLI_FIELD(<flag>, no_deps) },
  { <dep-file>, %<<translate>>, <output>, "--dep-file", "<file>",
    "Override the depfile path (one input only)", 0,
    CLI_FIELD(<text>, dep_file) },
  { <dep-target>, %<<translate>>, <output>, "--dep-target",
    "<target>", "Override the depfile target (one input only)", 0,
    CLI_FIELD(<text>, dep_target) },
  { <no-phony>, %<<translate>>, <output>,
    "--no-phony-deps", NULL, "Omit phony rules for included files", 0,
    CLI_FIELD(<flag>, no_phony_deps) },
  { <manifest>, %<<build run>>, <target>, "--manifest-path",
    "<file>", "Use <file> instead of discovering x2c.toml", 0,
    CLI_FIELD(<text>, manifest) },
  { <target>, %<<build run>>, <target>, "--target", "<name>",
    "Build the named manifest target", 0, CLI_FIELD(<text>, target) },
  { <profile>, %<<build run>>, <target>, "--profile", "<name>",
    "Apply the named manifest build profile", 0, CLI_FIELD(<text>, profile) },
  { <kind>, %<<build>>, <target>, "--kind", "<kind>",
    "executable, static-library, or meta-module", 0 },
  { <compile>, %<<build>>, <target>, "-c",
    NULL, "Produce object files without linking", 0,
    .alias = "--compile-only", CLI_FIELD(<flag>, compile_only) },
  { <jobs>, %<<translate build run script>>, <target>, "-j",
    "<count>", "Maximum parallel translation and compilation jobs", 0,
    .alias = "--jobs" },
  { <output>, %<<build run>>, <output>, "--output", "<file>",
    "Name the executable, library, or single object", 0,
    CLI_FIELD(<text>, output) },
  { <rebuild>, %<<script>>, <output>, "--rebuild", NULL,
    "Build the script even when its cached executable is current", 0,
    CLI_FIELD(<flag>, rebuild) },
  { <clean>, %<<script>>, <output>, "--clean", NULL,
    "Remove the script's cached build and exit without running it", 0,
    CLI_FIELD(<flag>, clean) },
  { <build-dir>, %<<build run>>, <output>, "--build-dir",
    "<dir>", "Store generated C, objects, deps, and state here", 0,
    CLI_FIELD(<text>, build_dir) },
  { <cc-db>, %<<build run>>, <output>, "--compile-commands",
    "<file>", "Write native compile commands and retain generated files", 0 },
  { <save-temp>, %<<build run>>, <output>,
    "--save-temps", NULL,
    "Keep generated C and other intermediate files", 0,
    .label = "--save-temps[=<dir>]", CLI_FIELD(<flag>, save_temps) },
  { <sha256>, %<<install>>, <package>, "--sha256", "<hex>",
    "Require this digest of a downloaded or local archive", 0,
    CLI_FIELD(<text>, sha256) },
  { <index>, %<<install build run>>, <package>, "--index",
    "<url-or-path>",
    "Resolve package names through this index", 0, CLI_FIELD(<text>, index) },
  { <force>, %<<install>>, <package>, "--force", NULL,
    "Install a bundle built for another x2c version", 0,
    CLI_FIELD(<flag>, force) },
  { <include>, %<<translate build run script>>, <source>,
    "-I", "<dir>", "Add a shared x2c/C include directory", 0,
    .package_native = 1 },
  { <x-include>, %<<translate build run script>>, <source>,
    "--x-include-dir", "<dir>", "Add an x2c-only include directory", 0 },
  { <c-include>, %<<build run script>>, <source>,
    "--c-include-dir", "<dir>", "Add a C-only ordinary include directory", 0,
    .package_native = 1 },
  { <c-system>, %<<build run script>>, <source>,
    "--c-system-dir", "<dir>", "Add a C-only system include directory", 0,
    .package_native = 1 },
  { <pkg-dir>, %<<translate build run script env>>, <source>,
    "--package-dir", "<dir>", "Add a directory of x2c packages", 0,
    CLI_FIELD(<list>, package_dirs) },
  { <native>, %<<translate build run>>, <source>,
    "--native-module", "<file>",
    "Load a native module for compile-time calls", 0,
    CLI_FIELD(<list>, native_modules) },
  { <extension>, %<<build>>, <source>,
    "--extension", "<dir>",
    "Link a package's compile-time part into a compiler", 0,
    CLI_FIELD(<list>, extensions) },
  { <no-cpp>, %<<translate build run>>, <source>,
    "--no-cpp", NULL, "Skip symbol collection and preprocessing", 0,
    CLI_FIELD(<flag>, no_cpp) },
  { <live-syms>, %<<translate build run>>, <source>,
    "--live-symbols", NULL,
    "Collect symbols through the host preprocessor", 0,
    CLI_FIELD(<flag>, live_symbols) },
  { <cpp-syms>, %<<translate build run>>, <source>,
    "--cpp-symbols", NULL, "Use CPP collection for this translation", 0,
    CLI_FIELD(<flag>, cpp_symbols) },
  { <cc>, %<<build run script env>>, <c-compiler>,
    "--cc", "<program>",
    "Use <program> as the host C compiler", 0, CLI_FIELD(<text>, cc) },
  { <meta-cc>, %<<translate build run script>>, <c-compiler>,
    "--meta-cc", "<program>",
    "Use <program> to build meta code, whatever --cc is", 0,
    CLI_FIELD(<text>, meta_cc) },
  { <ar>, %<<build env>>, <c-compiler>,
    "--ar", "<program>",
    "Use <program> as the static-library archiver", 0, CLI_FIELD(<text>, ar) },
  { <opt>, %<<build run script>>,
    <c-compiler>,
    "-O", NULL, "Set C optimization", 0,
    .label = "-O0, -O1, -O2, -O3, -Os", .prefix = 1 },
  { <g>, %<<build run script>>, <c-compiler>, "-g", NULL,
    "Emit debug information", 0 },
  { <define>, %<<build run script>>, <c-compiler>, "-D",
    "<name>[=<value>]", "Define a C preprocessor macro", 0,
    .package_native = 1 },
  { <undefine>, %<<build run script>>, <c-compiler>, "-U", "<name>",
    "Undefine a C preprocessor macro", 0, .package_native = 1 },
  { <xcc>, %<<build run script>>, <c-compiler>, "-Xcc", "<arg>",
    "Pass one argument only to C compilation", 0 },
  { <lib-dir>, %<<build run script>>, <linker>, "-L", "<dir>",
    "Add a library search directory", 0, .package_native = 1 },
  { <library>, %<<build run script>>, <linker>, "-l", "<name>",
    "Link library <name>", 0, .package_native = 1 },
  { <rpath>, %<<build run script>>, <linker>, "--rpath", "<dir>",
    "Search <dir> for shared libraries when the program runs", 0,
    .package_native = 1 },
  { <wl>, %<<build run script>>, <linker>, "-Wl,",
    NULL, "Pass comma-separated arguments to the linker", 0,
    .label = "-Wl,<arg>[,<arg>...]", .prefix = 1, .package_native = 1 },
  { <pthread>, %<<build run script>>, <c-compiler>, "-pthread", NULL,
    "Enable native threading for compilation and linking", 0,
    .package_native = 1 },
  { <framework>, %<<build run script>>, <linker>, "-framework", "<name>",
    "Link a native framework on macOS", 0, .package_native = 1 },
  { <xlinker>, %<<build run script>>, <linker>, "-Xlinker", "<arg>",
    "Pass one argument to the linker", 0, .package_native = 1 },
  { <tokens>, %<<translate>>, <inspection>, "--dump-tokens",
    NULL, "Print source tokens and stop", 0 },
  { <dump-cpp>, %<<translate>>, <inspection>, "--dump-cpp", NULL,
    "Print host-preprocessed text and stop", 0 },
  { <dump-cpp>, %<<translate>>, <inspection>,
    "--dump-cpp-text", NULL, "Alias for --dump-cpp", 0 },
  { <cpp-tokens>, %<<translate>>, <inspection>,
    "--dump-cpp-tokens", NULL, "Print host-preprocessed tokens and stop", 0 },
  { <dump-ast>, %<<translate>>, <inspection>, "--dump-ast", NULL,
    "Print the parsed AST and stop", 0 },
  { <transforms>, %<<translate>>, <inspection>,
    "--dump-transforms", NULL, "Print the transformed AST and stop", 0 },
  { <dump-defs>, %<<translate>>, <inspection>, "--dump-definitions", NULL,
    "Print each definition's location and documentation and stop", 0 },
  { <dump-code>, %<<translate>>, <inspection>, "--dump-code", NULL,
    "Print unformatted generated code and stop", 0 },
  { <symbols>, %<<translate>>, <inspection>, "--dump-symbols",
    NULL, "Print the source symbol table and stop", 0 },
  { <dump-csym>, %<<translate>>, <inspection>,
    "--dump-cpp-symbols", NULL, "Print the CPP symbol table and stop", 0 },
  { <dump-cache>, %<<translate>>, <inspection>, "--dump-cache", NULL,
    "Print the compiler cache and stop", 0 },
  { <conform>, %<<translate>>, <inspection>,
    "--dump-conformance", NULL, "Print protocol conformance and stop", 0 },
  { 0 }
};

/* The command spelled `word`, or NULL. `help` never matches: it parses no
   options and is not a subject of `x2c help <command>`. */
static CliCommand *_command_row(const char *word) {
  for (CliCommand *row = cli_commands; row.name; row++)
    if (row.name != <help> && strcmp(word, row.name.str()) == 0) return row;
  return NULL;
}

// parsing

/** Expands response files and parses `argv[1..]` into one validated request.
    Help and version requests print and exit with status zero. An empty command
    line prints help and exits with status two; other invalid input reports an
    error and exits with status two. The result has the active `Scope` and
    canonical-pool lifetimes described by `CliRequest`.

    Raises: `<alloc-fail>` or `<size-limit>` while expanding response files or
    constructing request values.
*/
CliRequest CliRequest.parse(int argc, char **argv) {
  Array args = $auto(CliRequest.read_arguments(argc, argv));
  return CliRequest.parse_arguments(args);
}

/** Parses already-read arguments, preserving deferred script expansion. */
CliRequest CliRequest.parse_arguments(Array args) {
  if (!args.len()) _help_exit(0, 2);
  String first = args[0];
  if (!first)
    Diagnostics.driver_error("expected a command, found an empty argument");
  CliCommand *command = _command_row(first);
  if (command) return _parse_command(args, *command);
  if (first == "--help" || first == "-h") _help_exit(0, 0);
  if (first == "--version" || first == "-V") {
    puts(Compiler.version());
    exit(0);
  }
  if (first == "help") _help_command(args);
  if (first == "-o") _cli_fail_removed_output();
  String spelling = _two_dash(first);
  if (spelling) _cli_fail_one_dash_removed(first, %"x2c translate $spelling ...");
  if (first[0] != '-') _cli_fail_expected_command(first);
  $fail.cli_command_unknown(first);
}

/** Reads initial arguments. Script options defer response-file expansion
    until parsing, so program arguments remain literal. The caller owns
    the returned Array. */
Array CliRequest.read_arguments(int argc, char **argv) {
  Array args = [];
  int script = argc > 1 && !strcmp(argv[1], "script");
  for (int i = 1; i < argc; i++) {
    if (script) args.push(String.new(argv[i]));
    else _expand_argument(args, String.new(argv[i]), NULL);
  }
  return args;
}

/* One argument list read into a request. Options extend the argument lists
   in the order they are written. `operands` is set after `--`, and a
   script's words before `expanded` came from a response file. */
static typedef struct Parse {
  CliRequest request, Array args, int operands, expanded;
  Array inputs, run_args, include_dirs, cpp_args, cc_args, ld_args;
} Parse;

static CliRequest _parse_command(Array args, CliCommand &command) {
  Parse p = {
    .request = CliRequest.new(command.name), .args = args,
    .inputs = [], .run_args = [], .include_dirs = [], .cpp_args = [],
    .cc_args = [], .ld_args = []};
  for (int i = 1; i < args.len(); i++) _word(p, i);
  _finish_request(p);
  _check(p.request);
  return p.request;
}

/* Reads the word at `i` and leaves `i` on the last word it used. */
static void _word(Parse &p, int &i) {
  String arg = p.args[i];
  if (!p.operands && arg == "--") p.operands = 1;
  else if (_expands(p, arg, i)) _expand(p, arg, i);
  else if (p.operands || !arg || arg[0] != '-') _operand(p, arg, i);
  else _option(p, arg, i);
}

/* A script expands a response file among its options. The expanded words
   replace the reference and are read next, but never expanded again. */
static int _expands(Parse &p, String arg, int i) =>
  p.request.command == <script> && !p.operands && i >= p.expanded &&
  arg.startswith("@");

static void _expand(Parse &p, String arg, int &i) {
  Array words = [];
  _expand_argument(words, arg, NULL);
  p.args.splice(i, 1, words);
  p.expanded = i + words.len();
  i--;
}

/* An operand is an input, or after `--` a program argument for `run`.
   Every word after a script belongs to the script, `@` and `--` too. */
static void _operand(Parse &p, String arg, int &i) {
  if (p.operands && p.request.command == <run>) p.run_args.push(arg);
  else p.inputs.push(arg);
  if (p.request.command == <script>)
    while (++i < p.args.len()) p.run_args.push(p.args[i]);
}

/* The argument lists become the request's. The table conses its list
   fields newest first. */
static void _finish_request(Parse &p) {
  CliRequest r = p.request;
  r.inputs = p.inputs.list_free();
  r.run_args = p.run_args.list_free();
  r.include_dirs = p.include_dirs.list_free();
  r.cpp_args = p.cpp_args.list_free();
  r.cc_args = p.cc_args.list_free();
  r.ld_args = p.ld_args.list_free();
  r.package_dirs = r.package_dirs.reverse();
  r.native_modules = r.native_modules.reverse();
  r.extensions = r.extensions.reverse();
}

/* Operand counts and option conflicts, once every word is read. */
static void _check(CliRequest r) {
  Symbol name = r.command, List inputs = r.inputs;
  if (name == <translate> && !inputs)
    Diagnostics.driver_error("translate requires at least one input");
  if (inputs.cdr() && (r.dep_file || r.dep_target))
    Diagnostics.driver_error(
      "--dep-file and --dep-target require exactly one input");
  if (r.no_deps && (r.dep_file || r.dep_target || r.no_phony_deps))
    Diagnostics.driver_error(
      "--no-deps conflicts with dependency output options");
  if (r.compile_only && r.kind != <executable>)
    Diagnostics.driver_error(
      "--compile-only conflicts with a library target kind");
  if (name == <env> && inputs.cdr())
    Diagnostics.driver_error("env accepts at most one name");
  if ((name in %<<install remove new>>) &&
      (!inputs || inputs.cdr()))
    $fail.cli_operand_required(name);
  if (name == <list> && inputs)
    $fail.cli_operands_forbidden(name);
  if (name == <script> && !inputs)
    Diagnostics.driver_error("script requires a script file");
}

static void _help_command(Array args) {
  if (args.len() == 1) _help_exit(0, 0);
  if (args.len() > 2)
    Diagnostics.driver_error("help accepts at most one command");
  String name = args[1];
  if (name == "help" || name == "--help" || name == "-h")
    _help_exit(<help>, 0);
  CliCommand *asked = name ? _command_row(name) : NULL;
  if (!asked) $fail.cli_help_unknown(name);
  _help_exit(asked.name, 0);
}

// options

/* One option as written: its table row, its spelling up to any `=`, its
   value, and whether the value shares the spelling's word, as `-Idir`
   does. The C compiler and linker receive an option as it was written. */
static typedef struct Given {
  CliOption *option, String spelling, value, int attached;
} Given;

/* A dashed word is the removed `-o`, `--save-temps=<dir>`, or an option
   from the table. */
static void _option(Parse &p, String arg, int &i) {
  if (arg == "-o") _cli_fail_removed_output();
  if ((p.request.command in %<<build run>>) && arg.startswith("--save-temps=")) {
    _save_temps_dir(p.request, arg);
    return;
  }
  Given given = _take_option(p.args, i, p.request.command);
  if (!given.option) _unknown_option(arg, p.request.command);
  _apply(p, given);
}

/* build and run take `--save-temps=<dir>`, although the table's
   `--save-temps` takes no value. */
static void _save_temps_dir(CliRequest r, String arg) {
  r.save_temps = 1;
  r.temps_dir = arg.remove_prefix("--save-temps=");
  if (!r.temps_dir)
    Diagnostics.driver_error("--save-temps= requires a directory");
}

/* Reads the option at `i` for `command`, advancing `i` past a separate value.
   A long option may carry its value after `=`, as `--out-dir=gen`; an empty
   one is the option's own missing value, not the next word. An unknown
   spelling gives no option, so each caller phrases its own diagnostic. */
static Given _take_option(Array args, int &i, Symbol command) {
  String arg = args[i], written = arg, joined = NULL, suffix = NULL;
  int equals = arg.startswith("--") ? arg.find("=") : -1;
  if (equals > 2) {
    written = arg[:equals];
    joined = arg[equals + 1:];
  }
  Given given = {_find_option(written, command, suffix), written};
  if (!given.option) return given;
  if (equals > 2 && !given.option.value)
    $fail.cli_option_value_forbidden(arg);
  given.value = equals > 2 ? joined : suffix;
  given.attached = suffix != NULL;
  if (given.option.value && !given.value && equals <= 2) {
    if (++i == args.len()) $fail.cli_option_value_required(arg);
    given.value = args[i];
  }
  if (!given.value &&
      (given.option.id == <output> || given.option.id == <out-dir>))
    $fail.cli_option_value_required(written);
  return given;
}

/* Finds the option `spelling` names for `command`. A two-letter option that
   takes a value also accepts it in the same argument, as `-Idir`, and
   reports the remainder through `attached`. */
static CliOption *_find_option(
  String spelling, Symbol command, String &attached) {
  attached = NULL;
  for (CliOption *option = cli_options; option.spelling; option++) {
    if (!(command in option.commands)) continue;
    String form = option.spelling;
    int longer = spelling.len() > form.len() && spelling.startswith(form);
    if (option.prefix) {
      if (longer) return option;
      continue;
    }
    if (spelling == form || spelling == option.alias) return option;
    if (option.value && form.len() == 2 && longer) {
      attached = spelling[2:];
      return option;
    }
  }
  return NULL;
}

/* An option without an arm here sets the request field its row names. */
static void _apply(Parse &p, Given given) {
  CliRequest r = p.request;
  String spelling = given.spelling, value = given.value;
  $switch(given.option.id)
  {
    case <help>: _help_exit(r.command, 0);
    case <color>: r.color_mode = _color_mode(value);
    case <include>: _include_dir(p, value);
    case <x-include>: p.include_dirs.push(value);
    case <tokens>: case <dump-cpp>: case <cpp-tokens>: case <dump-ast>:
    case <transforms>: case <dump-code>: case <symbols>: case <dump-csym>:
    case <dump-cache>: case <conform>: case <dump-defs>:
      r.dump = given.option.id;
    case <kind>: r.kind_explicit = 1; r.kind = _target_kind(value);
    case <jobs>: r.jobs = _count(value, 1, "job count");
    case <max-errors>: r.max_errors = _count(value, 0, "error limit");
    case <cc-db>: r.compile_commands = value; r.save_temps = 1;
    case <c-include>: _push_pair(p.cc_args, "-I", value);
    case <c-system>: _push_pair(p.cc_args, "-isystem", value);
    case <opt>: case <g>: p.cc_args.push(spelling);
    case <define>: case <undefine>:
      _forward(p.cpp_args, given); _forward(p.cc_args, given);
    case <xcc>: p.cc_args.push(_xcc_argument(value));
    case <lib-dir>: case <library>: _forward(p.ld_args, given);
    case <rpath>: p.ld_args.push(%"-Wl,-rpath,$value");
    case <pthread>: p.cc_args.push(spelling); p.ld_args.push(spelling);
    case <framework>: case <xlinker>: _push_pair(p.ld_args, spelling, value);
    case <wl>: p.ld_args.push(spelling);
    default: _set_field(r, *given.option, value);
  }
}

static Symbol _color_mode(String value) {
  if (!value)
    Diagnostics.driver_error("--color requires auto, always, or never");
  if (value == "auto") return <auto>;
  if (value == "always") return <always>;
  if (value == "never") return <never>;
  $fail.cli_color_invalid(value);
}

static Symbol _target_kind(String value) {
  String refusal = NULL;
  Symbol kind = TargetKind.named(value, refusal);
  if (refusal) Diagnostics.driver_error(refusal);
  if (!kind) $fail.cli_target_unknown(value);
  return kind;
}

// native products

static TargetKind target_kinds[] = {
  { <executable>, "executable",     "executable",     "",    ""    },
  { <static-lib>, "static-library", "static library", "lib", ".a"  },
  { <module>,     "meta-module",    "native module",  "",    ".so" },
  { 0 }
};

/** Returns the target kind spelled `spelling`, or 0 when no kind has that
    spelling. `refusal` says why this compiler refuses a known spelling, and
    is NULL otherwise. */
Symbol TargetKind.named(String spelling, String &refusal) {
  refusal = spelling == "shared-library" ?
    "shared-library is not supported by this compiler" : NULL;
  for (TargetKind *row = target_kinds; row.kind; row++)
    if (spelling == row.spelling) return row.kind;
  return 0;
}

/** Returns the row of target kind `kind`; any other kind reads as an
    executable. */
TargetKind *TargetKind.of(Symbol kind) {
  for (TargetKind *row = target_kinds; row.kind; row++)
    if (row.kind == kind) return row;
  return target_kinds;
}

static int _count(String value, int minimum, String noun) {
  char *end = NULL;
  errno = 0;
  long count = value ? strtol(value, &end, 10) : 0;
  if (!value || errno || *end || count < minimum || count > INT_MAX)
    $fail.cli_value_invalid(noun, value);
  return (int) count;
}

/* Commands other than translate also hand a shared include directory to
   the C compiler. */
static void _include_dir(Parse &p, String dir) {
  p.include_dirs.push(dir);
  if (p.request.command != <translate>) _push_pair(p.cc_args, "-I", dir);
}

/* `-DX` stays one word, and `-D X` two. */
static void _forward(Array out, Given given) {
  if (given.attached) out.push(given.spelling);
  else _push_pair(out, given.spelling, given.value);
}

static void _push_pair(Array out, String option, String value) {
  out.push(option);
  out.push(value);
}

/* The driver owns C dependency output, so `-Xcc` cannot pass it. */
static String _xcc_argument(String value) {
  if (CliRequest.dependency_option(value))
    $fail.cli_dependency_owned(value);
  return value;
}

/** Returns whether `s` contains a driver-owned dependency option.
    Recognizes `-MMD`, `-MP`, `-MF`, and `-MT` as leading spellings or in a
    comma-delimited pass-through argument; `NULL` returns zero.
*/
int CliRequest.dependency_option(String s) {
  return s && (
    s.startswith("-MMD") || s.startswith("-MP") ||
    s.startswith("-MF") || s.startswith("-MT") ||
    ",-MMD" in s || ",-MP" in s || ",-MF" in s || ",-MT" in s
  );
}

static void _set_field(
  CliRequest r, CliOption &option, String value) {
  char *field = (char *) r + option.offset;
  $switch(option.apply)
  {
    case <flag>: *(int *) field = 1;
    case <text>: *(String *) field = value;
    case <list>: *(List *) field = cons(value, *(List *) field);
  }
}

// package native arguments

/** Reads a package's native response options, expanding literal `{package}`
    after tokenization. Only native include/define/thread options, ordered
    archive/library/framework inputs, run-time library search directories,
    and the `-Wl,` and `-Xlinker` linker pass-throughs are admitted.
    `cc_args` and `ld_args` serve native actions; no source-preprocessing
    options are returned.
*/
CliRequest CliRequest.package_options(String path, String package) {
  Array words = $auto([]);
  foreach (String word, _response_arguments(path))
    words.push(word.replace("{package}", package));
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <build>;
  Parse p = {
    .request = request, .args = words, .include_dirs = [],
    .cpp_args = [], .cc_args = [], .ld_args = []};
  for (int i = 0; i < words.len(); i++) _native(p, i);
  p.include_dirs.free();
  p.cpp_args.free();
  request.cc_args = p.cc_args.list_free();
  request.ld_args = p.ld_args.list_free();
  return request;
}

/* A package's native word is an archive to link or an option a package may
   carry. */
static void _native(Parse &p, int &i) {
  String arg = p.args[i];
  if (!arg) Diagnostics.driver_error("empty package native argument");
  if (arg[0] != '-' && arg[0] != '@' && arg.endswith(".a")) {
    p.ld_args.push(arg);
    return;
  }
  Given given = _take_option(p.args, i, p.request.command);
  if (!given.option || !given.option.package_native)
    $fail.cli_native_unsupported(arg);
  _apply(p, given);
}

// response files

/* `@file` expands to the file's words, recursively, and `@@word` is the
   literal `@word`. `stack` holds the absolute paths being expanded, so a
   file that includes itself, directly or not, is an error. */
static void _expand_argument(Array out, String arg, List stack) {
  if (!arg || arg[0] != '@') {
    out.push(arg);
    return;
  }
  if (arg[1] == '@') {
    out.push(arg[1:]);
    return;
  }
  if (arg.len() == 1)
    Diagnostics.driver_error("empty response-file reference '@'");
  String path = arg[1:], identity = Path.absolute(path);
  if (identity in stack)
    _fail(%"recursive response-file inclusion: $path", NULL);
  List nested = cons(identity, stack);
  foreach (String word, _response_arguments(path))
    _expand_argument(out, word, nested);
}

/* Reads response-file tokens with ordinary quoting and UTF-8 checks.
   Returns canonical Strings without expanding `@` references. Paths and
   arguments retain the producing pool lifetime. */
static List _response_arguments(String path) {
  size_t length = 0, char *text = _read_response_file(path, length);
  Array words = _response_words(path, text, length);
  Scope.free(text);
  return words.list_free();
}

/* The whole file, which must be UTF-8 without a NUL byte. */
static char *_read_response_file(String path, size_t &length) {
  FILE *file = fopen(path, "rb");
  if (!file) _response_error(path, 1, strerror(errno));
  long end = _response_size(file, path);
  char *text = Scope.malloc((size_t) end + 1);
  size_t got = fread(text, 1, (size_t) end, file), int failed = ferror(file);
  fclose(file);
  if (failed || got != (size_t) end)
    _response_error(path, 1, "could not read complete file");
  text[got] = 0;
  if (memchr(text, 0, got)) _response_error(path, 1, "embedded NUL byte");
  if (!_valid_utf8((unsigned char *) text))
    _response_error(path, 1, "input is not valid UTF-8");
  length = got;
  return text;
}

/* The size of the open file, with its position back at the start. */
static long _response_size(FILE *file, String path) {
  long end = -1;
  if (!fseek(file, 0, SEEK_END)) end = ftell(file);
  if (end < 0 || fseek(file, 0, SEEK_SET)) {
    int error = errno;
    fclose(file);
    _response_error(path, 1, strerror(error));
  }
  return end;
}

/* Shortest forms of scalar values only: no overlong sequence, surrogate, or
   code point above U+10FFFF. `text` is NUL-terminated and has no other NUL. */
static int _valid_utf8(const unsigned char *text) {
  while (*text) {
    int length = scan_utf8_length(text);
    if (length < 0) return 0;
    text += length;
  }
  return 1;
}

/* Response-file words. Whitespace separates words; quotes and a backslash
   keep what they cover, newlines included; and `#` as the first nonspace
   character of a line starts a comment. `blank` holds until a line's first
   nonspace character, and `started` marks a word begun, perhaps by empty
   quotes. */
static typedef struct Words {
  Array out, String path, Buffer word;
  int line, blank, started, quote, escaped, comment;
} Words;

static Array _response_words(String path, const char *text, size_t length) {
  Words w = {
    .out = [], .path = path, .word = Buffer.new(0), .line = 1, .blank = 1};
  for (size_t i = 0; i < length; i++) _scan(w, (unsigned char) text[i]);
  _finish_words(w);
  w.word.free();
  return w.out;
}

/* Inside a comment only a newline counts. A backslash escapes the next
   character, in quotes or out. */
static void _scan(Words &w, int c) {
  if (w.comment) {
    if (c == '\n') _newline(w);
  }
  else if (w.escaped) {
    w.escaped = 0;
    _put(w, c);
  }
  else if (c == '\\') {
    w.escaped = 1;
    w.blank = 0;
  }
  else if (w.quote) {
    if (c == w.quote) w.quote = 0;
    else _put(w, c);
  }
  else _bare(w, c);
}

/* Outside quotes, a quote opens, `#` on a blank line starts a comment, and
   whitespace ends a word. */
static void _bare(Words &w, int c) {
  if (c == '\'' || c == '"') {
    w.quote = c;
    w.started = 1;
    w.blank = 0;
  }
  else if (w.blank && c == '#') w.comment = 1;
  else if (isspace(c)) {
    _flush(w);
    if (c == '\n') _newline(w);
  }
  else {
    w.blank = 0;
    _put(w, c);
  }
}

/* Quoted and escaped newlines stay in the word and still count as lines. */
static void _put(Words &w, int c) {
  w.word.write_char(c);
  w.started = 1;
  if (c == '\n') w.line++;
}

static void _newline(Words &w) {
  w.comment = 0;
  w.blank = 1;
  w.line++;
}

static void _flush(Words &w) {
  if (!w.started) return;
  w.out.push(w.word.str());
  w.word.clear();
  w.started = 0;
}

/* The text may end in a comment, but not in quotes or after a backslash. */
static void _finish_words(Words &w) {
  if (w.comment) return;
  if (w.escaped) _response_error(w.path, w.line, "trailing backslash");
  if (w.quote) _response_error(w.path, w.line, "unterminated quote");
  _flush(w);
}

// help

/* Prints top-level help for command 0, or one command's help, and exits. */
static void _help_exit(Symbol command, int status) {
  if (!command) _print_top_help();
  else if (command == <help>) _print_help_usage();
  else _print_page(*_help_page(command));
  exit(status);
}

static void _print_help_usage(void) {
  puts(
    "Usage:\n"
    "  x2c help [command]\n"
    "\n"
    "Show top-level help, or help for translate, build, run, new, script, "
    "repl,\nenv, install, remove, or list.");
}

static void _print_top_help(void) {
  puts(
    $dedent(%"
      Usage:
        x2c <command> [options]

      x2c translates x2c source to C and can optionally compile and link the
      result with the host C toolchain.

      Commands:
    "));
  for (CliCommand *command = cli_commands; command.name; command++)
    printf("  %-12s%s\n", command.name.str(), command.description);
  _print_external_commands();
  _print_options(0);
  puts("\nInput syntax:\n");
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  _print_help_row("--", "End option parsing", 2);
  puts("");
  puts(
    $dedent(%"
      Run 'x2c help <command>' or 'x2c <command> --help' for command help."));
}

/* Installed external commands list themselves in `commands.txt`, one
   `name|maturity|summary` line each. */
static void _print_external_commands(void) {
  String libexec = Compiler.home_libexec();
  File manifest = libexec ? fopen(%"$libexec/commands.txt", "r") : NULL;
  if (!manifest) return;
  char *line = NULL, size_t capacity = 0;
  while (getline(&line, &capacity, manifest) >= 0) {
    char *maturity = strchr(line, '|');
    if (!maturity) continue;
    *maturity++ = 0;
    if (CliRequest.is_builtin(line)) continue;
    char *summary = strchr(maturity, '|');
    if (!summary) continue;
    *summary++ = 0;
    summary[strcspn(summary, "\r\n")] = 0;
    printf("  %-12s%s\n", line, summary);
  }
  free(line);
  manifest.close();
}

/* A command's help page: its usage, its options, the rows for `@<file>` and,
   when the command reads it, `--`, then any closing notes. */
static typedef struct HelpPage {
  Symbol command, const char *usage, *response, *end, *notes;
} HelpPage;

static HelpPage help_pages[] = {
  { <translate>,
    $dedent(%"
      Usage:
        x2c translate [options] <input.x>...

      Translate each x2c input into a matching C source and header."),
    "Read additional arguments from a response file", "End option parsing",
    $dedent(%"
      The output directory defaults to the current directory and must already
      exist. Use --out-dir to select another directory.
      Shell wildcards are allowed because the shell expands them; x2c does not
      interpret wildcard characters in input operands.
      Inputs translate in parallel, one job per online processor. Under Make
      the default is one job; -j 1 translates serially.") },
  { <build>,
    $dedent(%"
      Usage:
        x2c build [options] <input>...
        x2c build [options] [--target <name>]

      Translate x2c sources, compile C sources, and link one target.
      With explicit inputs, the default target is an executable. Without
      inputs, x2c reads the nearest x2c.toml and builds its default
      target."),
    "Read additional arguments from a response file", "End option parsing",
    $dedent(%"
      Inputs may be .x, .c, .o, or .a files. x2c links its runtime and
      required platform libraries automatically. Directory operands and
      unexpanded wildcard operands are rejected.") },
  { <run>,
    $dedent(%"
      Usage:
        x2c run [build-options] <input>... [-- <argument>...]
        x2c run [build-options] [--target <name>] [-- <argument>...]

      Build one executable and run it. Arguments after -- are passed
      unchanged to the executable."),
    "Read additional arguments from a response file",
    "End build options and begin program arguments",
    $dedent(%"
      The selected target must be executable. After a successful build,
      x2c returns the program's exit status.") },
  { <new>,
    $dedent(%"
      Usage:
        x2c new [options] <dir>

      Create a project in <dir> that builds and runs as written: x2c.toml,
      src/main.x, and .gitignore. The directory may be missing or empty."),
    "Read additional arguments from a response file", NULL,
    $dedent(%"
      The target is named after the last component of <dir>, which may
      contain letters, digits, '_', and '-'. Run 'x2c run' in <dir> next.") },
  { <script>,
    $dedent(%"
      Usage:
        x2c script [options] <file> [<argument>...]

      Run an x2c source file as a script. The first run builds an executable in
      the per-user cache; later runs start it directly until the script, a file
      it includes or imports, the compiler, the runtime, or an option changes."),
    "Read additional options from a response file", NULL,
    $dedent(%"
      Every word after <file> is passed unchanged to the script, including
      words that begin with - or @. A script whose first line is the shebang
      '#!/usr/bin/env -S x2c script' runs directly. The cache is X2C_CACHE_DIR,
      XDG_CACHE_HOME/x2c, or ~/.cache/x2c. Builds remove the entries of
      scripts that no longer exist.") },
  { <env>,
    $dedent(%"
      Usage:
        x2c env [options] [name]

      Print the home, executable, include directory, runtime archive, command
      directory, identity, package roots, host tools, and script cache this
      compiler resolved, one 'name = value' line each, or only one value."),
    "Read additional arguments from a response file", NULL,
    $dedent(%"
      The home is X2C_HOME when set; otherwise the nearest directory above
      the executable, then above the current directory, holding include/
      and etc/compiler-sdk.xlisp. Package roots join with ':'.") },
  { <install>,
    $dedent(%"
      Usage:
        x2c install [options] <package>

      Install one package under <home>/packages. The package is a local
      directory, a local .tar.gz, a URL with --sha256, or a name resolved
      through the package index. A bundle installs as built; a pure-x2c
      source package is built by this compiler."),
    "Read additional arguments from a response file", NULL,
    $dedent(%"
      A bundle records the x2c version that built it and is refused for
      another version unless --force. A source package with native
      dependencies is refused; install its bundle instead.") },
  { <remove>,
    $dedent(%"
      Usage:
        x2c remove [options] <name>

      Remove one installed package from <home>/packages."),
    "Read additional arguments from a response file" },
  { <list>,
    $dedent(%"
      Usage:
        x2c list

      List installed packages as 'name version kind' lines."),
    "Read additional arguments from a response file" },
  { 0 }
};

static HelpPage *_help_page(Symbol command) {
  for (HelpPage *page = help_pages; page.command; page++)
    if (page.command == command) return page;
  $fail.cli_help_unknown(command);
}

static void _print_page(HelpPage &page) {
  puts(page.usage);
  _print_options(page.command);
  _print_help_row("@<file>", page.response, 2);
  if (page.end) _print_help_row("--", page.end, 2);
  if (!page.notes) return;
  puts("");
  puts(page.notes);
}

/* Top-level help lists its few options under one title; a command's help
   groups its options under titles in a fixed order. */
static void _print_options(Symbol command) {
  if (!command) command = <top>;
  if (command == <top>) {
    puts("\nGlobal options:");
    for (CliOption *option = cli_options; option.spelling; option++)
      if (_listed(*option, command)) _print_option(*option);
    return;
  }
  for (CliGroup *group = cli_groups; group.group; group++)
    _print_group(command, *group);
}

/* A group's title prints only above options the command lists. Translate
   names its source group for what it reads. */
static void _print_group(Symbol command, CliGroup &group) {
  CliOption *option = cli_options;
  while (option.spelling && !_in_group(*option, command, group.group))
    option++;
  if (!option.spelling) return;
  const char *title = command == <translate> && group.group == <source> ?
                      "Source options:" : group.title;
  printf("\n%s\n", title);
  for (; option.spelling; option++)
    if (_in_group(*option, command, group.group)) _print_option(*option);
}

static int _listed(CliOption &option, Symbol command) =>
  !option.hidden && (command in option.commands);

static int _in_group(CliOption &option, Symbol command, Symbol group) =>
  _listed(option, command) && option.group == group;

static void _print_option(const CliOption &option) {
  String spelled = option.label ? option.label :
                   option.alias ? %"${option.spelling}, ${option.alias}" :
                   option.spelling;
  String label = option.value ? %"$spelled ${option.value}" : spelled;
  _print_help_row(label, option.description, label.startswith("--") ? 6 : 2);
}

static void _print_help_row(
  const char *label, const char *description, int indent) {
  const int description_column = 30, int width = indent + (int) strlen(label);
  if (width >= description_column) {
    printf("%*s%s\n", indent, "", label);
    printf("%*s%s\n", description_column, "", description);
  }
  else {
    printf("%*s%s", indent, "", label);
    printf("%*s%s\n", description_column - width, "", description);
  }
}

// diagnostics

/* Prints an error and perhaps a note, then exits with status 2. The exit
   runs the atexit handlers, which Diagnostics.driver_error skips. */
static void _fail(String message, String note) {
  fprintf(stderr, "x2c: error: %s\n", message);
  if (note) fprintf(stderr, "note: %s\n", note);
  exit(2);
}

static void _cli_fail_removed_output(void) {
  _fail(
    "option '-o' was removed",
    "use '--out-dir' with translate or '--output' with build and run");
}

static void _cli_fail_expected_command(String arg) {
  _fail(
    %"expected a command before '$arg'",
    %"use 'x2c translate --out-dir <dir> $arg'");
}

/* translate corrects a one-dash long option. */
static void _unknown_option(String arg, Symbol command) {
  String spelling = command == <translate> ? _two_dash(arg) : NULL;
  if (spelling) _cli_fail_one_dash_removed(arg, spelling);
  $fail.cli_option_unknown(arg);
}

/* The two-dash translate option that a one-dash spelling such as
   `-out-dir` means, or NULL. */
static String _two_dash(String arg) {
  if (arg.len() <= 2 || arg[0] != '-' || arg[1] == '-') return NULL;
  String spelling = %"-$arg", attached;
  return _find_option(spelling, <translate>, attached) ? spelling : NULL;
}

static void _cli_fail_one_dash_removed(String arg, String use) {
  _fail(%"one-dash long option '$arg' was removed", %"use '$use'");
}

static void _response_error(String path, int line, const char *message) {
  fprintf(
    stderr, "x2c: error: response file '%s':%d: %s\n", path, line, message);
  exit(2);
}

// requests

/** Constructs a request with the command's ordinary CLI defaults. */
CliRequest CliRequest.new(Symbol command) {
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = command;
  request.jobs = _default_jobs();
  request.max_errors = 20;
  if (command in %<<build run script>>) request.kind = <executable>;
  return request;
}

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

/** Reports whether a raw command name belongs to the built-in parser. */
int CliRequest.is_builtin(const char *word) =>
  !strcmp(word, "help") || _command_row(word) != NULL;

/** Returns the version line `--version` prints, without a newline. */
String Compiler.version(void) => "x2c 0.15.0";

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

static macro Stmt $fail.cli_input_not_file(Expr $input) =>
  Diagnostics.driver_error(%"input is not a regular file: ${$input}");

static macro Stmt $report.cli_input_directory(Expr $input) {
  fprintf(stderr, "x2c: error: input is a directory: %s\n", $input);
  fputs(
    "note: pass source files, use a shell wildcard, or define a "
    "manifest target\n", stderr);
}

static macro Stmt $report.cli_input_missing(Expr $input) =>
  fprintf(stderr, "x2c: error: input does not exist: %s\n", $input);

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
