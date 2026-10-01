/*  cli.x -- x2c command-line parsing and presentation.

    Copyright (c) 2026 Gary William Flake.

    Each option is one table row: the commands that accept it, its
    spellings, its help text, and the request field it sets. Parsing and
    help read the same rows.
*/

#pragma once
#include "sourceview.x"

/** Holds one compiler command and its command-specific inputs and options.
    `List`s produced by `cli_parse` preserve CLI order. Copies are shallow:
    request storage and referenced canonical values keep their producing
    `Scope` and pool lifetimes.
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

#pragma private

$(import "../lib/system-macros.xmacro")

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

// commands and options

enum {
  CLI_TOP       = 1,
  CLI_TRANSLATE = 2,
  CLI_BUILD     = 4,
  CLI_RUN       = 8,
  CLI_SCRIPT    = 16,
  CLI_ENV       = 64,
  CLI_INSTALL   = 128,
  CLI_REMOVE    = 256,
  CLI_LIST      = 512,
  CLI_NEW       = 1024,
  // Commands that build native code from options on the command line.
  CLI_NATIVE    = CLI_BUILD | CLI_RUN | CLI_SCRIPT
};

typedef struct CliCommand {
  Symbol name, int mask, const char *description;
} CliCommand;

// `help` parses no options of its own, so it carries the top-level mask.
static CliCommand cli_commands[] = {
  { <translate>, CLI_TRANSLATE, "Translate .x files to .c and .h files" },
  { <build>,     CLI_BUILD,
    "Translate, compile, and optionally link a target" },
  { <run>,       CLI_RUN,       "Build an executable and run it" },
  { <new>,       CLI_NEW,       "Create a project that builds and runs" },
  { <script>,    CLI_SCRIPT,    "Build a script when it changes and run it" },
  { <env>,       CLI_ENV,       "Show the resolved home, layout, and tools" },
  { <install>,   CLI_INSTALL,   "Install a package into the home" },
  { <remove>,    CLI_REMOVE,    "Remove an installed package" },
  { <list>,      CLI_LIST,      "List installed packages" },
  { <help>,      CLI_TOP,       "Show help for x2c or one command" },
  { 0 }
};

/* `spelling` is the text an argument must match, and is also the help label
   unless `label` overrides it. `alias` is a second accepted spelling, and
   `prefix` matches an option whose text continues in the same argument.
   An option with a request field sets it as `apply` says; each other
   option has an arm in Parse.apply. */
typedef struct CliOption {
  Symbol id, int commands, Symbol group, String spelling;
  const char *value, *description, int hidden;
  String alias, label, int prefix;
  int apply, package_native;
  size_t offset;
} CliOption;

enum { FIELD_FLAG = 1, FIELD_TEXT, FIELD_LIST };

#define CLI_FIELD_FLAG(field) .apply = FIELD_FLAG, \
  .offset = offsetof(struct CliRequest, field)
#define CLI_FIELD_TEXT(field) .apply = FIELD_TEXT, \
  .offset = offsetof(struct CliRequest, field)
#define CLI_FIELD_LIST(field) .apply = FIELD_LIST, \
  .offset = offsetof(struct CliRequest, field)

static CliOption cli_options[] = {
  { <help>, CLI_TOP | CLI_TRANSLATE | CLI_NATIVE |
    CLI_ENV | CLI_INSTALL | CLI_REMOVE | CLI_LIST | CLI_NEW,
    <general>,
    "-h", NULL, "Show help and exit", 0, .alias = "--help" },
  { <version>, CLI_TOP, <global>, "-V", NULL,
    "Show the x2c version and exit", 0, .alias = "--version" },
  { <verbose>, CLI_TRANSLATE | CLI_NATIVE,
    <general>, "-v", NULL,
    "Show commands as they are executed", 0, .alias = "--verbose",
    CLI_FIELD_FLAG(verbose) },
  { <dry-run>, CLI_TRANSLATE | CLI_NATIVE,
    <general>, "-###", NULL, "Show commands without executing them", 0,
    CLI_FIELD_FLAG(dry_run) },
  { <quiet>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN |
    CLI_INSTALL | CLI_REMOVE | CLI_NEW,
    <general>, "-q", NULL,
    "Suppress successful progress and receipts", 0, .alias = "--quiet",
    CLI_FIELD_FLAG(quiet) },
  { <plain>, CLI_TRANSLATE | CLI_NATIVE,
    <general>, "--plain", NULL,
    "Use stable output without terminal rendering", 0, CLI_FIELD_FLAG(plain) },
  { <color>, CLI_TRANSLATE | CLI_NATIVE,
    <general>, "--color", "<auto|always|never>", "Control terminal color", 0 },
  { <debug>, CLI_TRANSLATE | CLI_NATIVE,
    <general>, "--debug", NULL, "Enable compiler debug logging", 0,
    CLI_FIELD_FLAG(debugging) },
  { <max-errors>, CLI_TRANSLATE | CLI_NATIVE, <general>, "--max-errors",
    "<count>", "Stop after <count> errors per unit (default: 20)", 0 },
  { <diag-file>, CLI_TRANSLATE | CLI_NATIVE, <general>,
    "--diagnostics-file", "<file>",
    "Write compiler diagnostics to <file> as JSON Lines", 0,
    CLI_FIELD_TEXT(diagnostics_file) },
  { <fatal-warn>, CLI_TRANSLATE, <general>, "--fatal-warnings", NULL,
    "Fail a unit that reports a warning", 1, CLI_FIELD_FLAG(fatal_warnings) },
  { <no-iface>, CLI_TRANSLATE, <source>, "--no-interfaces", NULL,
    "Collect every unit cold without reading .xi interfaces", 1,
    CLI_FIELD_FLAG(no_interfaces) },
  { <out-dir>, CLI_TRANSLATE, <output>, "--out-dir", "<dir>",
    "Write generated files under <dir> (default: .)", 0,
    CLI_FIELD_TEXT(out_dir) },
  { <src-map>, CLI_TRANSLATE | CLI_NATIVE, <output>, "--source-map",
    NULL, "Map generated C locations to original x2c sources", 0,
    CLI_FIELD_FLAG(source_map) },
  { <no-deps>, CLI_TRANSLATE, <output>, "--no-deps", NULL,
    "Do not write x2c dependency files", 0, CLI_FIELD_FLAG(no_deps) },
  { <dep-file>, CLI_TRANSLATE, <output>, "--dep-file", "<file>",
    "Override the depfile path (one input only)", 0,
    CLI_FIELD_TEXT(dep_file) },
  { <dep-target>, CLI_TRANSLATE, <output>, "--dep-target",
    "<target>", "Override the depfile target (one input only)", 0,
    CLI_FIELD_TEXT(dep_target) },
  { <no-phony>, CLI_TRANSLATE, <output>,
    "--no-phony-deps", NULL, "Omit phony rules for included files", 0,
    CLI_FIELD_FLAG(no_phony_deps) },
  { <manifest>, CLI_BUILD | CLI_RUN, <target>, "--manifest-path",
    "<file>", "Use <file> instead of discovering x2c.toml", 0,
    CLI_FIELD_TEXT(manifest) },
  { <target>, CLI_BUILD | CLI_RUN, <target>, "--target", "<name>",
    "Build the named manifest target", 0, CLI_FIELD_TEXT(target) },
  { <profile>, CLI_BUILD | CLI_RUN, <target>, "--profile", "<name>",
    "Apply the named manifest build profile", 0, CLI_FIELD_TEXT(profile) },
  { <kind>, CLI_BUILD, <target>, "--kind", "<kind>",
    "executable, static-library, or meta-module", 0 },
  { <compile>, CLI_BUILD, <target>, "-c",
    NULL, "Produce object files without linking", 0,
    .alias = "--compile-only", CLI_FIELD_FLAG(compile_only) },
  { <jobs>, CLI_TRANSLATE | CLI_NATIVE, <target>, "-j",
    "<count>", "Maximum parallel translation and compilation jobs", 0,
    .alias = "--jobs" },
  { <output>, CLI_BUILD | CLI_RUN, <output>, "--output", "<file>",
    "Name the executable, library, or single object", 0,
    CLI_FIELD_TEXT(output) },
  { <rebuild>, CLI_SCRIPT, <output>, "--rebuild", NULL,
    "Build the script even when its cached executable is current", 0,
    CLI_FIELD_FLAG(rebuild) },
  { <clean>, CLI_SCRIPT, <output>, "--clean", NULL,
    "Remove the script's cached build and exit without running it", 0,
    CLI_FIELD_FLAG(clean) },
  { <build-dir>, CLI_BUILD | CLI_RUN, <output>, "--build-dir",
    "<dir>", "Store generated C, objects, deps, and state here", 0,
    CLI_FIELD_TEXT(build_dir) },
  { <cc-db>, CLI_BUILD | CLI_RUN, <output>, "--compile-commands",
    "<file>", "Write native compile commands and retain generated files", 0 },
  { <save-temp>, CLI_BUILD | CLI_RUN, <output>,
    "--save-temps", NULL,
    "Keep generated C and other intermediate files", 0,
    .label = "--save-temps[=<dir>]", CLI_FIELD_FLAG(save_temps) },
  { <sha256>, CLI_INSTALL, <package>, "--sha256", "<hex>",
    "Require this digest of a downloaded or local archive", 0,
    CLI_FIELD_TEXT(sha256) },
  { <index>, CLI_INSTALL | CLI_BUILD | CLI_RUN, <package>, "--index",
    "<url-or-path>",
    "Resolve package names through this index", 0, CLI_FIELD_TEXT(index) },
  { <force>, CLI_INSTALL, <package>, "--force", NULL,
    "Install a bundle built for another x2c version", 0,
    CLI_FIELD_FLAG(force) },
  { <include>, CLI_TRANSLATE | CLI_NATIVE, <source>,
    "-I", "<dir>", "Add a shared x2c/C include directory", 0,
    .package_native = 1 },
  { <x-include>, CLI_TRANSLATE | CLI_NATIVE, <source>,
    "--x-include-dir", "<dir>", "Add an x2c-only include directory", 0 },
  { <c-include>, CLI_NATIVE, <source>,
    "--c-include-dir", "<dir>", "Add a C-only ordinary include directory", 0,
    .package_native = 1 },
  { <c-system>, CLI_NATIVE, <source>,
    "--c-system-dir", "<dir>", "Add a C-only system include directory", 0,
    .package_native = 1 },
  { <pkg-dir>, CLI_TRANSLATE | CLI_NATIVE | CLI_ENV, <source>,
    "--package-dir", "<dir>", "Add a directory of x2c packages", 0,
    CLI_FIELD_LIST(package_dirs) },
  { <native>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--native-module", "<file>",
    "Load a native module for compile-time calls", 0,
    CLI_FIELD_LIST(native_modules) },
  { <extension>, CLI_BUILD, <source>,
    "--extension", "<dir>",
    "Link a package's compile-time part into a compiler", 0,
    CLI_FIELD_LIST(extensions) },
  { <no-cpp>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--no-cpp", NULL, "Skip symbol collection and preprocessing", 0,
    CLI_FIELD_FLAG(no_cpp) },
  { <live-syms>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--live-symbols", NULL,
    "Collect symbols through the host preprocessor", 0,
    CLI_FIELD_FLAG(live_symbols) },
  { <cpp-syms>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--cpp-symbols", NULL, "Use CPP collection for this translation", 0,
    CLI_FIELD_FLAG(cpp_symbols) },
  { <cc>, CLI_NATIVE | CLI_ENV, <c-compiler>,
    "--cc", "<program>",
    "Use <program> as the host C compiler", 0, CLI_FIELD_TEXT(cc) },
  { <meta-cc>, CLI_TRANSLATE | CLI_NATIVE, <c-compiler>,
    "--meta-cc", "<program>",
    "Use <program> to build meta code, whatever --cc is", 0,
    CLI_FIELD_TEXT(meta_cc) },
  { <ar>, CLI_BUILD | CLI_ENV, <c-compiler>,
    "--ar", "<program>",
    "Use <program> as the static-library archiver", 0, CLI_FIELD_TEXT(ar) },
  { <opt>, CLI_NATIVE,
    <c-compiler>,
    "-O", NULL, "Set C optimization", 0,
    .label = "-O0, -O1, -O2, -O3, -Os", .prefix = 1 },
  { <g>, CLI_NATIVE, <c-compiler>, "-g", NULL,
    "Emit debug information", 0 },
  { <define>, CLI_NATIVE, <c-compiler>, "-D",
    "<name>[=<value>]", "Define a C preprocessor macro", 0,
    .package_native = 1 },
  { <undefine>, CLI_NATIVE, <c-compiler>, "-U", "<name>",
    "Undefine a C preprocessor macro", 0, .package_native = 1 },
  { <xcc>, CLI_NATIVE, <c-compiler>, "-Xcc", "<arg>",
    "Pass one argument only to C compilation", 0 },
  { <lib-dir>, CLI_NATIVE, <linker>, "-L", "<dir>",
    "Add a library search directory", 0, .package_native = 1 },
  { <library>, CLI_NATIVE, <linker>, "-l", "<name>",
    "Link library <name>", 0, .package_native = 1 },
  { <rpath>, CLI_NATIVE, <linker>, "--rpath", "<dir>",
    "Search <dir> for shared libraries when the program runs", 0,
    .package_native = 1 },
  { <wl>, CLI_NATIVE, <linker>, "-Wl,",
    NULL, "Pass comma-separated arguments to the linker", 0,
    .label = "-Wl,<arg>[,<arg>...]", .prefix = 1, .package_native = 1 },
  { <pthread>, CLI_NATIVE, <c-compiler>, "-pthread", NULL,
    "Enable native threading for compilation and linking", 0,
    .package_native = 1 },
  { <framework>, CLI_NATIVE, <linker>, "-framework", "<name>",
    "Link a native framework on macOS", 0, .package_native = 1 },
  { <xlinker>, CLI_NATIVE, <linker>, "-Xlinker", "<arg>",
    "Pass one argument to the linker", 0, .package_native = 1 },
  { <tokens>, CLI_TRANSLATE, <inspection>, "--dump-tokens",
    NULL, "Print source tokens and stop", 0 },
  { <dump-cpp>, CLI_TRANSLATE, <inspection>, "--dump-cpp", NULL,
    "Print host-preprocessed text and stop", 0 },
  { <dump-cpp>, CLI_TRANSLATE, <inspection>,
    "--dump-cpp-text", NULL, "Alias for --dump-cpp", 0 },
  { <cpp-tokens>, CLI_TRANSLATE, <inspection>,
    "--dump-cpp-tokens", NULL, "Print host-preprocessed tokens and stop", 0 },
  { <dump-ast>, CLI_TRANSLATE, <inspection>, "--dump-ast", NULL,
    "Print the parsed AST and stop", 0 },
  { <transforms>, CLI_TRANSLATE, <inspection>,
    "--dump-transforms", NULL, "Print the transformed AST and stop", 0 },
  { <dump-defs>, CLI_TRANSLATE, <inspection>, "--dump-definitions", NULL,
    "Print each definition's location and documentation and stop", 0 },
  { <dump-code>, CLI_TRANSLATE, <inspection>, "--dump-code", NULL,
    "Print unformatted generated code and stop", 0 },
  { <symbols>, CLI_TRANSLATE, <inspection>, "--dump-symbols",
    NULL, "Print the source symbol table and stop", 0 },
  { <dump-csym>, CLI_TRANSLATE, <inspection>,
    "--dump-cpp-symbols", NULL, "Print the CPP symbol table and stop", 0 },
  { <dump-cache>, CLI_TRANSLATE, <inspection>, "--dump-cache", NULL,
    "Print the compiler cache and stop", 0 },
  { <conform>, CLI_TRANSLATE, <inspection>,
    "--dump-conformance", NULL, "Print protocol conformance and stop", 0 },
  { 0 }
};

/* The command spelled `word`, or NULL. `help` never matches: it parses no
   options and is not a subject of `x2c help <command>`. */
static CliCommand *_command_row(const char *word) {
  for (CliCommand *row = cli_commands; row.name; row++)
    if (row.mask != CLI_TOP && strcmp(word, row.name.str()) == 0) return row;
  return NULL;
}

/* A command outside the table, such as 0 for top-level help, has the
   top-level mask. */
static int _command_mask(Symbol command) {
  for (CliCommand *row = cli_commands; row.name; row++)
    if (row.name == command) return row.mask;
  return CLI_TOP;
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
CliRequest cli_parse(int argc, char **argv) {
  Array args = $auto([]);
  _read_arguments(args, argc, argv);
  if (!args.len()) _help_exit(0, 2);
  String first = args[0];
  if (!first) driver_error("expected a command, found an empty argument");
  CliCommand *command = _command_row(first);
  if (command) return _parse_command(args, command);
  if (first == "--help" || first == "-h") _help_exit(0, 0);
  if (first == "--version" || first == "-V") {
    puts(cli_version());
    exit(0);
  }
  if (first == "help") _help_command(args);
  if (first == "-o") _removed_output();
  String spelling = _two_dash(first);
  if (spelling) _one_dash_removed(first, %"x2c translate $spelling ...");
  if (first[0] != '-') _expected_command(first);
  driver_error(%"unknown command or global option '$first'");
}

/* A script's arguments are its own, so `script` expands response files
   only while it parses its options. */
static void _read_arguments(Array args, int argc, char **argv) {
  int script = argc > 1 && !strcmp(argv[1], "script");
  for (int i = 1; i < argc; i++) {
    if (script) args.push(String.new(argv[i]));
    else _expand_argument(args, String.new(argv[i]), NULL);
  }
}

/* One argument list read into a request. Options extend the argument lists
   in the order they are written. `operands` is set after `--`, and a
   script's words before `expanded` came from a response file. */
typedef struct Parse {
  CliRequest request, Array args, int mask, operands, expanded;
  Array inputs, run_args, include_dirs, cpp_args, cc_args, ld_args;
} Parse;

static CliRequest _parse_command(Array args, CliCommand *command) {
  Parse p = {
    .request = cli_request(command.name), .args = args, .mask = command.mask,
    .inputs = [], .run_args = [], .include_dirs = [], .cpp_args = [],
    .cc_args = [], .ld_args = []};
  for (int i = 1; i < args.len(); i++) p.word(i);
  p.finish();
  p.request._check(p.mask);
  return p.request;
}

/* Reads the word at `i` and leaves `i` on the last word it used. */
static void Parse.word(Parse *p, int &i) {
  String arg = p.args[i];
  if (!p.operands && arg == "--") p.operands = 1;
  else if (p.expands(arg, i)) p.expand(arg, i);
  else if (p.operands || !arg || arg[0] != '-') p.operand(arg, i);
  else p.option(arg, i);
}

/* A script expands a response file among its options. The expanded words
   replace the reference and are read next, but never expanded again. */
static int Parse.expands(Parse *p, String arg, int i) =>
  p.mask == CLI_SCRIPT && !p.operands && i >= p.expanded &&
  arg.startswith("@");

static void Parse.expand(Parse *p, String arg, int &i) {
  Array words = [];
  _expand_argument(words, arg, NULL);
  p.args.splice(i, 1, words);
  p.expanded = i + words.len();
  i--;
}

/* An operand is an input, or after `--` a program argument for `run`.
   Every word after a script belongs to the script, `@` and `--` too. */
static void Parse.operand(Parse *p, String arg, int &i) {
  if (p.operands && p.mask == CLI_RUN) p.run_args.push(arg);
  else p.inputs.push(arg);
  if (p.mask == CLI_SCRIPT)
    while (++i < p.args.len()) p.run_args.push(p.args[i]);
}

/* The argument lists become the request's. The table conses its list
   fields newest first. */
static void Parse.finish(Parse *p) {
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
static void CliRequest._check(CliRequest r, int mask) {
  Symbol name = r.command, List inputs = r.inputs;
  if (mask == CLI_TRANSLATE && !inputs)
    driver_error("translate requires at least one input");
  if (inputs.cdr() && (r.dep_file || r.dep_target))
    driver_error("--dep-file and --dep-target require exactly one input");
  if (r.no_deps && (r.dep_file || r.dep_target || r.no_phony_deps))
    driver_error("--no-deps conflicts with dependency output options");
  if (r.compile_only && r.kind != <executable>)
    driver_error("--compile-only conflicts with a library target kind");
  if (mask == CLI_ENV && inputs.cdr())
    driver_error("env accepts at most one name");
  if ((mask == CLI_INSTALL || mask == CLI_REMOVE || mask == CLI_NEW) &&
      (!inputs || inputs.cdr()))
    driver_error(%"${name} requires exactly one operand");
  if (mask == CLI_LIST && inputs)
    driver_error(%"${name} accepts no operands");
  if (mask == CLI_SCRIPT && !inputs)
    driver_error("script requires a script file");
}

static void _help_command(Array args) {
  if (args.len() == 1) _help_exit(0, 0);
  if (args.len() > 2) driver_error("help accepts at most one command");
  String name = args[1];
  if (name == "help" || name == "--help" || name == "-h")
    _help_exit(<help>, 0);
  CliCommand *asked = name ? _command_row(name) : NULL;
  if (!asked) driver_error(%"unknown help command '$name'");
  _help_exit(asked.name, 0);
}

// options

/* One option as written: its table row, its spelling up to any `=`, its
   value, and whether the value shares the spelling's word, as `-Idir`
   does. The C compiler and linker receive an option as it was written. */
typedef struct Given {
  CliOption *option, String spelling, value, int attached;
} Given;

/* A dashed word is the removed `-o`, `--save-temps=<dir>`, or an option
   from the table. */
static void Parse.option(Parse *p, String arg, int &i) {
  if (arg == "-o") _removed_output();
  if ((p.mask & (CLI_BUILD | CLI_RUN)) && arg.startswith("--save-temps=")) {
    p.request._save_temps_dir(arg);
    return;
  }
  Given given = _take_option(p.args, i, p.mask);
  if (!given.option) _unknown_option(arg, p.mask);
  p.apply(given);
}

/* build and run take `--save-temps=<dir>`, although the table's
   `--save-temps` takes no value. */
static void CliRequest._save_temps_dir(CliRequest r, String arg) {
  r.save_temps = 1;
  r.temps_dir = arg.remove_prefix("--save-temps=");
  if (!r.temps_dir) driver_error("--save-temps= requires a directory");
}

/* Reads the option at `i` for `mask`, advancing `i` past a separate value.
   A long option may carry its value after `=`, as `--out-dir=gen`; an empty
   one is the option's own missing value, not the next word. An unknown
   spelling gives no option, so each caller phrases its own diagnostic. */
static Given _take_option(Array args, int &i, int mask) {
  String arg = args[i], written = arg, joined = NULL, suffix = NULL;
  int equals = arg.startswith("--") ? arg.find("=") : -1;
  if (equals > 2) {
    written = arg[:equals];
    joined = arg[equals + 1:];
  }
  Given given = {_find_option(written, mask, suffix), written};
  if (!given.option) return given;
  if (equals > 2 && !given.option.value)
    driver_error(%"option takes no value '$arg'");
  given.value = equals > 2 ? joined : suffix;
  given.attached = suffix != NULL;
  if (given.option.value && !given.value && equals <= 2) {
    if (++i == args.len()) driver_error(%"option requires a value '$arg'");
    given.value = args[i];
  }
  return given;
}

/* Finds the option `spelling` names for `mask`. A two-letter option that
   takes a value also accepts it in the same argument, as `-Idir`, and
   reports the remainder through `attached`. */
static CliOption *_find_option(String spelling, int mask, String &attached) {
  attached = NULL;
  for (CliOption *option = cli_options; option.spelling; option++) {
    if (!(option.commands & mask)) continue;
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
static void Parse.apply(Parse *p, Given given) {
  CliRequest r = p.request;
  String spelling = given.spelling, value = given.value;
  $switch(given.option.id)
  {
    case <help>: _help_exit(r.command, 0);
    case <color>: r.color_mode = _color_mode(value);
    case <include>: p.include_dir(value);
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
    default: r._set_field(given.option, value);
  }
}

static Symbol _color_mode(String value) {
  if (!value) driver_error("--color requires auto, always, or never");
  if (value == "auto") return <auto>;
  if (value == "always") return <always>;
  if (value == "never") return <never>;
  driver_error(%"invalid color mode '$value'");
}

static Symbol _target_kind(String value) {
  if (value == "executable") return <executable>;
  if (value == "static-library") return <static-lib>;
  if (value == "meta-module") return <module>;
  if (value == "shared-library")
    driver_error("shared-library is not supported by this compiler");
  driver_error(%"unknown target kind '$value'");
}

static int _count(String value, int minimum, String noun) {
  char *end = NULL;
  errno = 0;
  long count = value ? strtol(value, &end, 10) : 0;
  if (!value || errno || *end || count < minimum || count > INT_MAX)
    driver_error(%"invalid $noun '$value'");
  return (int) count;
}

/* Commands other than translate also hand a shared include directory to
   the C compiler. */
static void Parse.include_dir(Parse *p, String dir) {
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
  if (cli_dependency_pass_through(value))
    driver_error(%"C dependency option is driver-owned '$value'");
  return value;
}

/** Returns whether `s` contains a driver-owned dependency option.
    Recognizes `-MMD`, `-MP`, `-MF`, and `-MT` as leading spellings or in a
    comma-delimited pass-through argument; `NULL` returns zero.
*/
int cli_dependency_pass_through(String s) {
  return s && (
    s.startswith("-MMD") || s.startswith("-MP") ||
    s.startswith("-MF") || s.startswith("-MT") ||
    ",-MMD" in s || ",-MP" in s || ",-MF" in s || ",-MT" in s
  );
}

static void CliRequest._set_field(
  CliRequest r, CliOption *option, String value) {
  char *field = (char *) r + option.offset;
  $switch(option.apply)
  {
    case FIELD_FLAG: *(int *) field = 1;
    case FIELD_TEXT: *(String *) field = value;
    case FIELD_LIST: *(List *) field = cons(value, *(List *) field);
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
CliRequest cli_package_options(String path, String package) {
  Array words = $auto([]);
  foreach (String word, cli_response_arguments(path))
    words.push(word.replace("{package}", package));
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <build>;
  Parse p = {
    .request = request, .args = words, .mask = CLI_BUILD, .include_dirs = [],
    .cpp_args = [], .cc_args = [], .ld_args = []};
  for (int i = 0; i < words.len(); i++) p.native(i);
  p.include_dirs.free();
  p.cpp_args.free();
  request.cc_args = p.cc_args.list_free();
  request.ld_args = p.ld_args.list_free();
  return request;
}

/* A package's native word is an archive to link or an option a package may
   carry. */
static void Parse.native(Parse *p, int &i) {
  String arg = p.args[i];
  if (!arg) driver_error("empty package native argument");
  if (arg[0] != '-' && arg[0] != '@' && arg.endswith(".a")) {
    p.ld_args.push(arg);
    return;
  }
  Given given = _take_option(p.args, i, p.mask);
  if (!given.option || !given.option.package_native)
    driver_error(%"unsupported package native argument '$arg'");
  p.apply(given);
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
  if (arg.len() == 1) driver_error("empty response-file reference '@'");
  String path = arg[1:], identity = Path.absolute(path);
  if (identity in stack)
    _fail(%"recursive response-file inclusion: $path", NULL);
  List nested = cons(identity, stack);
  foreach (String word, cli_response_arguments(path))
    _expand_argument(out, word, nested);
}

/** Reads response-file tokens with ordinary quoting and UTF-8 checks.
    Returns canonical Strings without expanding `@` references. Paths and
    arguments retain the producing pool lifetime.
*/
List cli_response_arguments(String path) {
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
  if (!_valid_utf8((unsigned char *) text, got))
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
   code point above U+10FFFF. */
static int _valid_utf8(const unsigned char *text, size_t length) {
  size_t i = 0;
  while (i < length) {
    unsigned char c = text[i++];
    if (c < 0x80) continue;
    int extra = 0, minimum = 0;
    unsigned code = 0;
    if ((c & 0xe0) == 0xc0) {
      extra = 1;
      minimum = 0x80;
      code = c & 0x1f;
    }
    else if ((c & 0xf0) == 0xe0) {
      extra = 2;
      minimum = 0x800;
      code = c & 0x0f;
    }
    else if ((c & 0xf8) == 0xf0) {
      extra = 3;
      minimum = 0x10000;
      code = c & 0x07;
    }
    else return 0;
    if (i + extra > length) return 0;
    while (extra--) {
      unsigned char next = text[i++];
      if ((next & 0xc0) != 0x80) return 0;
      code = (code << 6) | (next & 0x3f);
    }
    if (code < minimum || (code >= 0xd800 && code <= 0xdfff) ||
        code > 0x10ffff)
      return 0;
  }
  return 1;
}

/* Response-file words. Whitespace separates words; quotes and a backslash
   keep what they cover, newlines included; and `#` as the first nonspace
   character of a line starts a comment. `blank` holds until a line's first
   nonspace character, and `started` marks a word begun, perhaps by empty
   quotes. */
typedef struct Words {
  Array out, String path, Buffer word;
  int line, blank, started, quote, escaped, comment;
} Words;

static Array _response_words(String path, const char *text, size_t length) {
  Words w = {
    .out = [], .path = path, .word = Buffer.new(0), .line = 1, .blank = 1};
  for (size_t i = 0; i < length; i++) w.scan((unsigned char) text[i]);
  w.finish();
  w.word.free();
  return w.out;
}

/* Inside a comment only a newline counts. A backslash escapes the next
   character, in quotes or out. */
static void Words.scan(Words *w, int c) {
  if (w.comment) {
    if (c == '\n') w.newline();
  }
  else if (w.escaped) {
    w.escaped = 0;
    w.put(c);
  }
  else if (c == '\\') {
    w.escaped = 1;
    w.blank = 0;
  }
  else if (w.quote) {
    if (c == w.quote) w.quote = 0;
    else w.put(c);
  }
  else w.bare(c);
}

/* Outside quotes, a quote opens, `#` on a blank line starts a comment, and
   whitespace ends a word. */
static void Words.bare(Words *w, int c) {
  if (c == '\'' || c == '"') {
    w.quote = c;
    w.started = 1;
    w.blank = 0;
  }
  else if (w.blank && c == '#') w.comment = 1;
  else if (isspace(c)) {
    w.flush();
    if (c == '\n') w.newline();
  }
  else {
    w.blank = 0;
    w.put(c);
  }
}

/* Quoted and escaped newlines stay in the word and still count as lines. */
static void Words.put(Words *w, int c) {
  w.word.write_char(c);
  w.started = 1;
  if (c == '\n') w.line++;
}

static void Words.newline(Words *w) {
  w.comment = 0;
  w.blank = 1;
  w.line++;
}

static void Words.flush(Words *w) {
  if (!w.started) return;
  w.out.push(w.word.str());
  w.word.clear();
  w.started = 0;
}

/* The text may end in a comment, but not in quotes or after a backslash. */
static void Words.finish(Words *w) {
  if (w.comment) return;
  if (w.escaped) _response_error(w.path, w.line, "trailing backslash");
  if (w.quote) _response_error(w.path, w.line, "unterminated quote");
  w.flush();
}

// help

/* Prints top-level help for command 0, or one command's help, and exits. */
static void _help_exit(Symbol command, int status) {
  if (!command) _print_top_help();
  else if (command == <help>) _print_help_usage();
  else _print_page(_help_page(command));
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
  String libexec = home_libexec();
  File manifest = libexec ? fopen(%"$libexec/commands.txt", "r") : NULL;
  if (!manifest) return;
  char *line = NULL, size_t capacity = 0;
  while (getline(&line, &capacity, manifest) >= 0) {
    char *maturity = strchr(line, '|');
    if (!maturity) continue;
    *maturity++ = 0;
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
typedef struct HelpPage {
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
      interpret wildcard characters in input operands.") },
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
  driver_error(%"unknown help command '${command}'");
}

static void _print_page(HelpPage *page) {
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
  int mask = _command_mask(command);
  if (mask == CLI_TOP) {
    puts("\nGlobal options:");
    for (CliOption *option = cli_options; option.spelling; option++)
      if (_listed(option, mask)) _print_option(option);
    return;
  }
  Symbol groups[] = {
    <global>, <target>, <output>, <source>, <package>, <c-compiler>,
    <linker>, <inspection>, <general>, 0
  };
  for (Symbol *group = groups; *group; group++)
    _print_group(command, mask, *group);
}

/* A group's title prints only above options the command lists. */
static void _print_group(Symbol command, int mask, Symbol group) {
  CliOption *option = cli_options;
  while (option.spelling && !_in_group(option, mask, group)) option++;
  if (!option.spelling) return;
  printf("\n%s\n", _group_title(command, group));
  for (; option.spelling; option++)
    if (_in_group(option, mask, group)) _print_option(option);
}

static int _listed(CliOption *option, int mask) =>
  !option.hidden && (option.commands & mask);

static int _in_group(CliOption *option, int mask, Symbol group) =>
  _listed(option, mask) && option.group == group;

static const char *_group_title(Symbol command, Symbol group) {
  switch (group) {
    case <target>:     return "Target options:";
    case <output>:     return "Output options:";
    case <source>:
      return command == <translate> ?
             "Source options:" : "Translation options:";
    case <package>:    return "Package options:";
    case <c-compiler>: return "C compiler options:";
    case <linker>:     return "Linker options:";
    case <inspection>: return "Inspection options:";
    case <general>:    return "General options:";
  }
  return "Global options:";
}

static void _print_option(const CliOption *option) {
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
   runs the atexit handlers, which driver_error skips. */
static void _fail(String message, String note) {
  fprintf(stderr, "x2c: error: %s\n", message);
  if (note) fprintf(stderr, "note: %s\n", note);
  exit(2);
}

static void _removed_output(void) {
  _fail(
    "option '-o' was removed",
    "use '--out-dir' with translate or '--output' with build and run");
}

static void _expected_command(String arg) {
  _fail(
    %"expected a command before '$arg'",
    %"use 'x2c translate --out-dir <dir> $arg'");
}

/* translate corrects a one-dash long option. */
static void _unknown_option(String arg, int mask) {
  String spelling = mask == CLI_TRANSLATE ? _two_dash(arg) : NULL;
  if (spelling) _one_dash_removed(arg, spelling);
  driver_error(%"unknown option '$arg'");
}

/* The two-dash translate option that a one-dash spelling such as
   `-out-dir` means, or NULL. */
static String _two_dash(String arg) {
  if (arg.len() <= 2 || arg[0] != '-' || arg[1] == '-') return NULL;
  String spelling = %"-$arg", attached;
  return _find_option(spelling, CLI_TRANSLATE, attached) ? spelling : NULL;
}

static void _one_dash_removed(String arg, String use) {
  _fail(%"one-dash long option '$arg' was removed", %"use '$use'");
}

static void _response_error(String path, int line, const char *message) {
  fprintf(
    stderr, "x2c: error: response file '%s':%d: %s\n", path, line, message);
  exit(2);
}

// requests

/** Constructs a request with the command's ordinary CLI defaults. */
CliRequest cli_request(Symbol command) {
  int mask = _command_mask(command);
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = command;
  request.jobs = mask & CLI_NATIVE ? _default_build_jobs() : 1;
  request.max_errors = 20;
  if (mask & CLI_NATIVE) request.kind = <executable>;
  return request;
}

// An outer Make owns concurrency unless the caller explicitly supplies -j.
static int _default_build_jobs(void) {
  if (report_make_owned()) return 1;
  long count = sysconf(_SC_NPROCESSORS_ONLN);
  return count > 0 && count <= INT_MAX ? (int) count : 1;
}

/** Reports whether a raw command name belongs to the built-in parser. */
int cli_builtin_command(const char *word) =>
  !strcmp(word, "help") || _command_row(word) != NULL;

/** Returns the version line `--version` prints, without a newline. */
String cli_version(void) => "x2c 0.14.0";

/** Returns whether `request` selects a terminating inspection or dump mode. */
int CliRequest.inspects(CliRequest request) => request.dump != 0;

/** Returns the package roots `request` searches: its explicit `--package-dir`
    and manifest directories in order, then the home's `packages/` directory
    when it exists. A root named twice is searched twice and resolves the
    same entries. Explicit directories are borrowed; the result is a fresh
    `List` only when the home directory is appended.
*/
List CliRequest.package_roots(CliRequest request) {
  String home = home_packages();
  if (!Path.is_dir(home)) return request.package_dirs;
  return request.package_dirs.append(cons(home, NULL));
}
