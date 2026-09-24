/*  cli.x -- x2c command-line parsing and presentation.

    Copyright (c) 2026 Gary William Flake.

    Response expansion, command selection, option validation, diagnostics,
    and help rendering all produce or read the typed CliRequest.
*/

#pragma once
#include "sourceview.x"

/** Holds one compiler command and its command-specific inputs and options.
    `List`s produced by `cli_parse` preserve CLI order. Copies are shallow:
    request storage and referenced canonical values keep their producing
    `Scope`
    and pool lifetimes.
*/
typedef struct CliRequest {
  Symbol command, List inputs, run_args, include_dirs, package_dirs, cpp_args;
  List cc_args, ld_args, native_modules, String out_dir, dep_file, dep_target;
  String manifest;
  String target, profile, output, build_dir, temps_dir, label, state_seed;
  String prefix, cc, ar, compile_commands, sha256, index, Symbol kind;
  String diagnostics_file;
  Symbol color_mode;
  // The one --dump-* option in force, or 0. Each prints and stops.
  Symbol dump;
  int jobs, debugging, verbose, dry_run, quiet, plain, no_deps;
  int no_phony_deps, compile_only, kind_explicit, save_temps, no_cpp;
  int repl_dump, repl_stats, repl_verbose_stats;
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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "buffer.x"
#include "report.x"
#include "utils.x"

// cli metadata

enum {
  CLI_TOP       = 1,
  CLI_TRANSLATE = 2,
  CLI_BUILD     = 4,
  CLI_RUN       = 8,
  CLI_SCRIPT    = 16,
  CLI_BOOTSTRAP = 32,
  CLI_ENV       = 64,
  CLI_INSTALL   = 128,
  CLI_REMOVE    = 256,
  CLI_LIST      = 512,
  CLI_NEW       = 1024,
  CLI_REPL      = 2048,
  // Commands that build native code from options on the command line.
  CLI_NATIVE    = CLI_BUILD | CLI_RUN | CLI_SCRIPT
};

/* `spelling` is the text an argument must match, and is also the help label
   unless `label` overrides it. `alias` is a second accepted spelling, and
   `prefix` matches an option whose text continues in the same argument. */
typedef struct CliOption {
  Symbol id, int commands, Symbol group, String spelling;
  const char *value, *description, int hidden;
  String alias, label, int prefix;
} CliOption;

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
  { <repl>,      CLI_REPL,
    "Evaluate a supported x2c subset (experimental)" },
  { <bootstrap>, CLI_BOOTSTRAP, "Install a native x2c from an APE binary" },
  { <env>,       CLI_ENV,       "Show the resolved home, layout, and tools" },
  { <install>,   CLI_INSTALL,   "Install a package into the home" },
  { <remove>,    CLI_REMOVE,    "Remove an installed package" },
  { <list>,      CLI_LIST,      "List installed packages" },
  { <help>,      CLI_TOP,       "Show help for x2c or one command" },
  { 0 }
};

static CliOption cli_options[] = {
  { <help>, CLI_TOP | CLI_TRANSLATE | CLI_NATIVE | CLI_BOOTSTRAP |
    CLI_ENV | CLI_INSTALL | CLI_REMOVE | CLI_LIST | CLI_NEW | CLI_REPL,
    <general>,
    "-h", NULL, "Show help and exit", 0, .alias = "--help" },
  { <version>, CLI_TOP, <global>, "-V", NULL,
    "Show the x2c version and exit", 0, .alias = "--version" },
  { <verbose>, CLI_TRANSLATE | CLI_NATIVE | CLI_BOOTSTRAP,
    <general>, "-v", NULL,
    "Show commands as they are executed", 0, .alias = "--verbose" },
  { <dry-run>, CLI_TRANSLATE | CLI_NATIVE,
    <general>, "-###", NULL, "Show commands without executing them", 0 },
  { <quiet>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN | CLI_BOOTSTRAP |
    CLI_INSTALL | CLI_REMOVE | CLI_NEW,
    <general>, "-q", NULL,
    "Suppress successful progress and receipts", 0, .alias = "--quiet" },
  { <plain>, CLI_TRANSLATE | CLI_NATIVE | CLI_BOOTSTRAP,
    <general>, "--plain", NULL,
    "Use stable output without terminal rendering", 0 },
  { <color>, CLI_TRANSLATE | CLI_NATIVE | CLI_BOOTSTRAP,
    <general>, "--color", "<auto|always|never>", "Control terminal color", 0 },
  { <debug>, CLI_TRANSLATE | CLI_NATIVE,
    <general>, "--debug", NULL, "Enable compiler debug logging", 0 },
  { <max-errors>, CLI_TRANSLATE | CLI_NATIVE, <general>, "--max-errors",
    "<count>", "Stop after <count> errors per unit (default: 20)", 0 },
  { <diag-file>, CLI_TRANSLATE | CLI_NATIVE, <general>,
    "--diagnostics-file", "<file>",
    "Write compiler diagnostics to <file> as JSON Lines", 0 },
  { <fatal-warn>, CLI_TRANSLATE, <general>, "--fatal-warnings", NULL,
    "Fail a unit that reports a warning", 1 },
  { <no-iface>, CLI_TRANSLATE, <source>, "--no-interfaces", NULL,
    "Collect every unit cold without reading .xi interfaces", 1 },
  { <repl-dump>, CLI_REPL, <inspection>, "--dump", NULL,
    "Print typed syntax and lowered Lisp for each submission", 0 },
  { <repl-stats>, CLI_REPL, <inspection>, "--stats", NULL,
    "Print Lisp execution counters", 0 },
  { <vstats>, CLI_REPL, <inspection>, "--verbose-stats", NULL,
    "Print detailed runtime statistics", 0 },
  { <out-dir>, CLI_TRANSLATE, <output>, "--out-dir", "<dir>",
    "Write generated files under <dir> (default: .)", 0 },
  { <src-map>, CLI_TRANSLATE | CLI_NATIVE, <output>, "--source-map",
    NULL, "Map generated C locations to original x2c sources", 0 },
  { <no-deps>, CLI_TRANSLATE, <output>, "--no-deps", NULL,
    "Do not write x2c dependency files", 0 },
  { <dep-file>, CLI_TRANSLATE, <output>, "--dep-file", "<file>",
    "Override the depfile path (one input only)", 0 },
  { <dep-target>, CLI_TRANSLATE, <output>, "--dep-target",
    "<target>", "Override the depfile target (one input only)", 0 },
  { <no-phony>, CLI_TRANSLATE, <output>,
    "--no-phony-deps", NULL, "Omit phony rules for included files", 0 },
  { <manifest>, CLI_BUILD | CLI_RUN, <target>, "--manifest-path",
    "<file>", "Use <file> instead of discovering x2c.toml", 0 },
  { <target>, CLI_BUILD | CLI_RUN, <target>, "--target", "<name>",
    "Build the named manifest target", 0 },
  { <profile>, CLI_BUILD | CLI_RUN, <target>, "--profile", "<name>",
    "Apply the named manifest build profile", 0 },
  { <kind>, CLI_BUILD, <target>, "--kind", "<kind>",
    "executable, static-library, or meta-module", 0 },
  { <compile>, CLI_BUILD, <target>, "-c",
    NULL, "Produce object files without linking", 0,
    .alias = "--compile-only" },
  { <jobs>, CLI_TRANSLATE | CLI_NATIVE, <target>, "-j",
    "<count>", "Maximum parallel translation and compilation jobs", 0,
    .alias = "--jobs" },
  { <output>, CLI_BUILD | CLI_RUN, <output>, "--output", "<file>",
    "Name the executable, library, or single object", 0 },
  { <rebuild>, CLI_SCRIPT, <output>, "--rebuild", NULL,
    "Build the script even when its cached executable is current", 0 },
  { <clean>, CLI_SCRIPT, <output>, "--clean", NULL,
    "Remove the script's cached build and exit without running it", 0 },
  { <build-dir>, CLI_BUILD | CLI_RUN, <output>, "--build-dir",
    "<dir>", "Store generated C, objects, deps, and state here", 0 },
  { <cc-db>, CLI_BUILD | CLI_RUN, <output>, "--compile-commands",
    "<file>", "Write native compile commands and retain generated files", 0 },
  { <save-temp>, CLI_BUILD | CLI_RUN, <output>,
    "--save-temps", NULL,
    "Keep generated C and other intermediate files", 0,
    .label = "--save-temps[=<dir>]" },
  { <sha256>, CLI_INSTALL, <package>, "--sha256", "<hex>",
    "Require this digest of a downloaded or local archive", 0 },
  { <index>, CLI_INSTALL | CLI_BUILD | CLI_RUN, <package>, "--index",
    "<url-or-path>",
    "Resolve package names through this index", 0 },
  { <force>, CLI_INSTALL, <package>, "--force", NULL,
    "Install a bundle built for another x2c version", 0 },
  { <prefix>, CLI_BOOTSTRAP, <output>, "--prefix", "<dir>",
    "Install native x2c and sources under <dir>", 0 },
  { <include>, CLI_TRANSLATE | CLI_NATIVE, <source>,
    "-I", "<dir>", "Add a shared x2c/C include directory", 0 },
  { <x-include>, CLI_TRANSLATE | CLI_NATIVE, <source>,
    "--x-include-dir", "<dir>", "Add an x2c-only include directory", 0 },
  { <c-include>, CLI_NATIVE, <source>,
    "--c-include-dir", "<dir>", "Add a C-only ordinary include directory", 0 },
  { <c-system>, CLI_NATIVE, <source>,
    "--c-system-dir", "<dir>", "Add a C-only system include directory", 0 },
  { <pkg-dir>, CLI_TRANSLATE | CLI_NATIVE | CLI_ENV, <source>,
    "--package-dir", "<dir>", "Add a directory of x2c packages", 0 },
  { <native>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN | CLI_REPL, <source>,
    "--native-module", "<file>",
    "Load a native module for compile-time calls", 0 },
  { <no-cpp>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--no-cpp", NULL, "Skip symbol collection and preprocessing", 0 },
  { <live-syms>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--live-symbols", NULL,
    "Collect symbols through the host preprocessor", 0 },
  { <cpp-syms>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--cpp-symbols", NULL, "Use CPP collection for this translation", 0 },
  { <cc>, CLI_NATIVE | CLI_BOOTSTRAP | CLI_ENV, <c-compiler>,
    "--cc", "<program>",
    "Use <program> as the host C compiler", 0 },
  { <ar>, CLI_BUILD | CLI_BOOTSTRAP | CLI_ENV, <c-compiler>,
    "--ar", "<program>",
    "Use <program> as the static-library archiver", 0 },
  { <opt>, CLI_NATIVE | CLI_BOOTSTRAP,
    <c-compiler>,
    "-O", NULL, "Set C optimization", 0,
    .label = "-O0, -O1, -O2, -O3, -Os", .prefix = 1 },
  { <g>, CLI_NATIVE, <c-compiler>, "-g", NULL,
    "Emit debug information", 0 },
  { <define>, CLI_NATIVE, <c-compiler>, "-D",
    "<name>[=<value>]", "Define a C preprocessor macro", 0 },
  { <undefine>, CLI_NATIVE, <c-compiler>, "-U", "<name>",
    "Undefine a C preprocessor macro", 0 },
  { <xcc>, CLI_NATIVE, <c-compiler>, "-Xcc", "<arg>",
    "Pass one argument only to C compilation", 0 },
  { <lib-dir>, CLI_NATIVE, <linker>, "-L", "<dir>",
    "Add a library search directory", 0 },
  { <library>, CLI_NATIVE, <linker>, "-l", "<name>",
    "Link library <name>", 0 },
  { <rpath>, CLI_NATIVE, <linker>, "--rpath", "<dir>",
    "Search <dir> for shared libraries when the program runs", 0 },
  { <wl>, CLI_NATIVE, <linker>, "-Wl,",
    NULL, "Pass comma-separated arguments to the linker", 0,
    .label = "-Wl,<arg>[,<arg>...]", .prefix = 1 },
  { <pthread>, CLI_NATIVE, <c-compiler>, "-pthread", NULL,
    "Enable native threading for compilation and linking", 0 },
  { <framework>, CLI_NATIVE, <linker>, "-framework", "<name>",
    "Link a native framework on macOS", 0 },
  { <xlinker>, CLI_NATIVE, <linker>, "-Xlinker", "<arg>",
    "Pass one argument to the linker", 0 },
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

// diagnostics

static void _removed_output(void) {
  fputs(
    "x2c: error: option '-o' was removed\n"
    "note: use '--out-dir' with translate or '--output' with build and run\n",
    stderr);
  exit(2);
}

static void _expected_command(const char *arg) {
  fprintf(stderr, "x2c: error: expected a command before '%s'\n", arg);
  fprintf(stderr, "note: use 'x2c translate --out-dir <dir> %s'\n", arg);
  exit(2);
}

static void _response_error(
  const char *path, int line, const char *message) {
  fprintf(
    stderr, "x2c: error: response file '%s':%d: %s\n",
    path, line, message);
  exit(2);
}

// help

static int _command_mask(Symbol command) {
  for (CliCommand *row = cli_commands; row.name; row++)
    if (row.name == command) return row.mask;
  return CLI_TOP;
}

// The command spelled `word`, or NULL. `help` never matches: it parses no
// options and is not a subject of `x2c help <command>`.
static CliCommand *_command_row(const char *word) {
  for (CliCommand *row = cli_commands; row.name; row++)
    if (row.mask != CLI_TOP && strcmp(word, row.name.str()) == 0) return row;
  return NULL;
}

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

static void _print_option(const CliOption *option) {
  String spelled = option.label ? option.label :
                   option.alias ? %"${option.spelling}, ${option.alias}" :
                   option.spelling;
  String label = option.value ? %"$spelled ${option.value}" : spelled;
  _print_help_row(label, option.description, label.startswith("--") ? 6 : 2);
}

static void _print_options(Symbol command) {
  int mask = _command_mask(command);
  if (mask == CLI_TOP) {
    puts("\nGlobal options:");
    for (CliOption *option = cli_options; option.spelling; option++)
      if (!option.hidden && (option.commands & mask)) _print_option(option);
    return;
  }
  Symbol groups[] = {
    <global>, <target>, <output>, <source>, <package>, <c-compiler>,
    <linker>, <inspection>, <general>
  };
  for (int i = 0; i < 9; i++) {
    Symbol group = groups[i], int found = 0;
    for (CliOption *option = cli_options; option.spelling; option++)
      if (!option.hidden && (option.commands & mask) &&
          option.group == group) found = 1;
    if (!found) continue;
    printf("\n%s\n", _group_title(command, group));
    for (CliOption *option = cli_options; option.spelling; option++)
      if (!option.hidden && (option.commands & mask) &&
          option.group == group) _print_option(option);
  }
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
  _print_options(0);
  puts("");
  puts($dedent(%"
    Input syntax:
  "));
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  _print_help_row("--", "End option parsing", 2);
  puts("");
  puts($dedent(%"
    Run 'x2c help <command>' or 'x2c <command> --help' for command help."));
}

static void _print_translate_help(void) {
  puts(
    $dedent(%"
      Usage:
        x2c translate [options] <input.x>...

      Translate each x2c input into a matching C source and header."));
  _print_options(<translate>);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  _print_help_row("--", "End option parsing", 2);
  puts("");
  puts(
    $dedent(%"
      The output directory defaults to the current directory and must already
      exist. Use --out-dir to select another directory.
      Shell wildcards are allowed because the shell expands them; x2c does not
      interpret wildcard characters in input operands."));
}

static void _print_driver_help(Symbol command) {
  if (command == <build>)
    puts(
      $dedent(%"
        Usage:
          x2c build [options] <input>...
          x2c build [options] [--target <name>]

        Translate x2c sources, compile C sources, and link one target.
        With explicit inputs, the default target is an executable. Without
        inputs, x2c reads the nearest x2c.toml and builds its default
        target."));
  else
    puts(
      $dedent(%"
        Usage:
          x2c run [build-options] <input>... [-- <argument>...]
          x2c run [build-options] [--target <name>] [-- <argument>...]

        Build one executable and run it. Arguments after -- are passed
        unchanged to the executable."));
  _print_options(command);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  if (command == <run>)
    _print_help_row("--", "End build options and begin program arguments", 2);
  else _print_help_row("--", "End option parsing", 2);
  puts("");
  if (command == <build>)
    puts(
      $dedent(%"
        Inputs may be .x, .c, .o, or .a files. x2c links its runtime and
        required platform libraries automatically. Directory operands and
        unexpanded wildcard operands are rejected."));
  else
    puts(
      $dedent(%"
        The selected target must be executable. After a successful build,
        x2c returns the program's exit status."));
}

static void _print_bootstrap_help(void) {
  puts(
    $dedent(%"
      Usage:
        x2c bootstrap --prefix <dir> [options]

      Extract the source distribution carried by this APE and use the host
      C compiler and archiver to install a native x2c under <dir>."));
  _print_options(<bootstrap>);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  puts("");
  puts(
    $dedent(%"
      The seed supplies x2c sources and headers. A GCC- or Clang-compatible
      C compiler and a compatible archiver must be installed."));
}

static void _print_env_help(void) {
  puts(
    $dedent(%"
      Usage:
        x2c env [options] [name]

      Print the home, executable, include directory, runtime archive,
      package roots, host tools, and script cache this compiler resolved, one
      'name = value' line each, or only the value of one name."));
  _print_options(<env>);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  puts("");
  puts(
    $dedent(%"
      The home is X2C_HOME when set; otherwise the nearest directory above
      the executable, then above the current directory, holding include/
      and etc/compiler-sdk.xlisp. Package roots join with ':'."));
}

static void _print_package_help(Symbol command) {
  if (command == <install>)
    puts(
      $dedent(%"
        Usage:
          x2c install [options] <package>

        Install one package under <home>/packages. The package is a local
        directory, a local .tar.gz, a URL with --sha256, or a name resolved
        through the package index. A bundle installs as built; a pure-x2c
        source package is built by this compiler."));
  else if (command == <remove>)
    puts(
      $dedent(%"
        Usage:
          x2c remove [options] <name>

        Remove one installed package from <home>/packages."));
  else
    puts(
      $dedent(%"
        Usage:
          x2c list

        List installed packages as 'name version kind' lines."));
  _print_options(command);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  if (command != <install>) return;
  puts("");
  puts(
    $dedent(%"
      A bundle records the x2c version that built it and is refused for
      another version unless --force. A source package with native
      dependencies is refused; install its bundle instead."));
}

static void _print_new_help(void) {
  puts(
    $dedent(%"
      Usage:
        x2c new [options] <dir>

      Create a project in <dir> that builds and runs as written: x2c.toml,
      src/main.x, and .gitignore. The directory may be missing or empty."));
  _print_options(<new>);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  puts("");
  puts(
    $dedent(%"
      The target is named after the last component of <dir>, which may
      contain letters, digits, '_', and '-'. Run 'x2c run' in <dir> next."));
}

static void _print_script_help(void) {
  puts(
    $dedent(%"
      Usage:
        x2c script [options] <file> [<argument>...]

      Run an x2c source file as a script. The first run builds an executable in
      the per-user cache; later runs start it directly until the script, a file
      it includes or imports, the compiler, the runtime, or an option changes."));
  _print_options(<script>);
  _print_help_row(
    "@<file>", "Read additional options from a response file", 2);
  puts("");
  puts(
    $dedent(%"
      Every word after <file> is passed unchanged to the script, including
      words that begin with - or @. A script whose first line is the shebang
      '#!/usr/bin/env -S x2c script' runs directly. The cache is X2C_CACHE_DIR,
      XDG_CACHE_HOME/x2c, or ~/.cache/x2c. Builds remove the entries of
      scripts that no longer exist."));
}

static void _print_repl_help(void) {
  puts(
    $dedent(%"
      Usage:
        x2c repl [options]

      Evaluate a supported x2c subset in an experimental interactive session.
      Read submissions from standard input. Enter :help for session commands."));
  _print_options(<repl>);
  _print_help_row(
    "@<file>", "Read additional options from a response file", 2);
}

static void _print_help(Symbol command) {
  $switch(command)
  {
    case 0:            _print_top_help();
    case <translate>:  _print_translate_help();
    case <build>:
    case <run>:        _print_driver_help(command);
    case <new>:        _print_new_help();
    case <script>:     _print_script_help();
    case <repl>:       _print_repl_help();
    case <bootstrap>:  _print_bootstrap_help();
    case <env>:        _print_env_help();
    case <install>:
    case <remove>:
    case <list>:       _print_package_help(command);
    case <help>:
      puts(
        $dedent(%"
          Usage:
            x2c help [command]

          Show top-level help, or help for translate, build, run, new, script, repl,
          bootstrap, env, install, remove, or list."));
    default: x2c_driver_error(%"unknown help command '${command}'");
  }
}

static void _print_version(void) {
  puts(cli_version());
}

// response files

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

static char *_read_response_file(const char *path, size_t *length) {
  FILE *file = fopen(path, "rb");
  if (!file) _response_error(path, 1, strerror(errno));
  if (fseek(file, 0, SEEK_END)) {
    int error = errno;
    fclose(file);
    _response_error(path, 1, strerror(error));
  }
  long end = ftell(file);
  if (end < 0 || fseek(file, 0, SEEK_SET)) {
    int error = errno;
    fclose(file);
    _response_error(path, 1, strerror(error));
  }
  char *text = Scope.malloc((size_t) end + 1);
  size_t got = fread(text, 1, (size_t) end, file), int failed = ferror(file);
  fclose(file);
  if (failed || got != (size_t) end)
    _response_error(path, 1, "could not read complete file");
  text[got] = 0;
  if (memchr(text, 0, got)) _response_error(path, 1, "embedded NUL byte");
  if (!_valid_utf8((unsigned char *) text, got))
    _response_error(path, 1, "input is not valid UTF-8");
  *length = got;
  return text;
}

static int _response_on_stack(List stack, String path) {
  foreach (String entry, stack) if (entry == path) return 1;
  return 0;
}

static void _tokenize_response(
  Array output, String path, const char *text, size_t length) {
  Buffer token = Buffer.new(0), int quote = 0, escaped = 0, line = 1, have = 0;
  int first_nonspace = 1, comment = 0;
  for (size_t i = 0; i <= length; i++) {
    int c = i == length ? 0 : (unsigned char) text[i];
    if (comment) {
      if (c == '\n') {
        comment = 0;
        first_nonspace = 1;
        line++;
      }
      else if (!c) break;
      continue;
    }
    if (escaped) {
      if (!c) _response_error(path, line, "trailing backslash");
      token.write_char(c);
      have = 1;
      escaped = 0;
      if (c == '\n') line++;
      continue;
    }
    if (c == '\\') {
      escaped = 1;
      first_nonspace = 0;
      continue;
    }
    if (quote) {
      if (!c) _response_error(path, line, "unterminated quote");
      if (c == quote) quote = 0;
      else {
        token.write_char(c);
        have = 1;
        if (c == '\n') line++;
      }
      continue;
    }
    if (c == '\'' || c == '"') {
      quote = c;
      have = 1;
      first_nonspace = 0;
      continue;
    }
    if (first_nonspace && c == '#') {
      comment = 1;
      continue;
    }
    if (!c || isspace(c)) {
      if (have) {
        output.push(token.str());
        token.clear();
        have = 0;
      }
      if (c == '\n') {
        first_nonspace = 1;
        line++;
      }
      else if (c && first_nonspace) first_nonspace = 1;
      if (!c) break;
      continue;
    }
    first_nonspace = 0;
    token.write_char(c);
    have = 1;
  }
  token.free();
}

/** Reads response-file tokens with ordinary quoting and UTF-8 checks.
    Returns canonical Strings without expanding `@` references. Paths and
    arguments retain the producing pool lifetime.
*/
List cli_response_arguments(String path) {
  size_t length = 0, char *text = _read_response_file(path, &length);
  Array arguments = [];
  _tokenize_response(arguments, path, text, length);
  Scope.free(text);
  return arguments.list_free();
}

static void _expand_argument(Array output, String argument, List stack) {
  if (!argument || argument[0] != '@') {
    output.push(argument);
    return;
  }
  if (argument[1] == '@') {
    output.push(String.new(argument + 1));
    return;
  }
  if (!argument[1]) x2c_driver_error("empty response-file reference '@'");
  String path = String.new(argument + 1);
  String identity = Path.absolute(path);
  if (_response_on_stack(stack, identity)) {
    fprintf(
      stderr,
      "x2c: error: recursive response-file inclusion: %s\n", path);
    exit(2);
  }
  List nested = cons(identity, stack);
  foreach (String word, cli_response_arguments(path))
    _expand_argument(output, word, nested);
}

// parsing

/* Finds the option `spelling` names for `mask`. A two-letter option that
   takes a value also accepts it in the same argument, as `-Idir`, and
   reports the remainder through `attached`. */
static CliOption *_find_option(
  String spelling, int command_mask, String *attached) {
  *attached = NULL;
  for (CliOption *option = cli_options; option.spelling; option++) {
    if (!(option.commands & command_mask)) continue;
    String form = option.spelling;
    int longer = spelling.len() > form.len() && spelling.startswith(form);
    if (option.prefix) {
      if (longer) return option;
      continue;
    }
    if (spelling == form || spelling == option.alias) return option;
    if (option.value && form.len() == 2 && longer) {
      *attached = spelling[2:];
      return option;
    }
  }
  return NULL;
}

/* Reads the option at `*index` for `mask`, advancing it past a separate
   value argument. Returns NULL for an unknown spelling so each command can
   phrase its own diagnostic. The driver asks for `spelling` and `attached`
   because it forwards the argument as written to the C compiler and
   linker. */
static CliOption *_take_option(
  Array args, int *index, int mask,
  String *spelling, String *value, int *attached) {
  // A long option may carry its value after '=', as `--out-dir=gen`. An
  // empty one is the option's own missing-value case, not the next word.
  String arg = args[*index], written = arg, joined = NULL;
  int equals = arg.startswith("--") ? arg.find("=") : -1;
  if (equals > 2) {
    written = arg[:equals];
    joined = arg[equals + 1:];
    if (joined && !joined[0]) joined = NULL;
  }
  String suffix = NULL;
  CliOption *option = _find_option(written, mask, &suffix);
  if (!option) return NULL;
  if (equals > 2 && !option.value)
    x2c_driver_error(%"option takes no value '$arg'");
  if (spelling) *spelling = written;
  if (attached) *attached = suffix != NULL;
  *value = equals > 2 ? joined : suffix;
  if (option.value && !*value && equals <= 2) {
    if (++*index == args.len())
      x2c_driver_error(%"option requires a value '$arg'");
    *value = args[*index];
  }
  return option;
}

static void _push_pair(Array arguments, String option, String value) {
  arguments.push(option);
  arguments.push(value);
}

/** Returns whether `argument` contains a driver-owned dependency option.
    Recognizes `-MMD`, `-MP`, `-MF`, and `-MT` as leading spellings or in a
    comma-delimited pass-through argument; `NULL` returns zero.
*/
int cli_dependency_pass_through(String s) {
  return s && (
    s.startswith("-MMD") || s.startswith("-MP") ||
    s.startswith("-MF") || s.startswith("-MT") ||
    s.contains(",-MMD") || s.contains(",-MP") ||
    s.contains(",-MF") || s.contains(",-MT")
  );
}

static void _driver_kind(CliRequest request, String value) {
  request.kind_explicit = 1;
  if (value == "executable") request.kind = <executable>;
  else if (value == "static-library") request.kind = <static-lib>;
  else if (value == "meta-module") request.kind = <module>;
  else if (value == "shared-library")
    x2c_driver_error("shared-library is not supported by this compiler");
  else x2c_driver_error(%"unknown target kind '$value'");
}

static int _driver_count(String value, int minimum, String noun) {
  char *end = NULL;
  errno = 0;
  long count = value ? strtol(value, &end, 10) : 0;
  if (!value || errno || *end || count < minimum || count > INT_MAX)
    x2c_driver_error(%"invalid $noun '$value'");
  return (int) count;
}

static void _apply_option(
  CliRequest c, CliOption *option, String spelling, String value,
  int attached, Array x_paths, Array cpp_args, Array cc_args, Array ld_args) {
  $switch(option.id)
  {
    case <help>: _print_help(c.command);
      exit(0);
    case <verbose>: c.verbose = 1;
    case <dry-run>: c.dry_run = 1;
    case <quiet>: c.quiet = 1;
    case <plain>: c.plain = 1;
    case <color>:
      if (!value)
        x2c_driver_error("--color requires auto, always, or never");
      if (value == "auto") c.color_mode = <auto>;
      else if (value == "always") c.color_mode = <always>;
      else if (value == "never") c.color_mode = <never>;
      else x2c_driver_error(%"invalid color mode '$value'");
    case <debug>: c.debugging = 1;
    case <repl-dump>: c.repl_dump = 1;
    case <repl-stats>: c.repl_stats = 1;
    case <vstats>: c.repl_verbose_stats = 1;
    case <out-dir>: c.out_dir = value;
    case <src-map>: c.source_map = 1;
    case <rebuild>: c.rebuild = 1;
    case <clean>: c.clean = 1;
    case <no-deps>: c.no_deps = 1;
    case <dep-file>: c.dep_file = value;
    case <dep-target>: c.dep_target = value;
    case <no-phony>: c.no_phony_deps = 1;
    case <include>: x_paths.push(value);
      // build and run also hand the directory to the C compiler.
      if (c.command != <translate>) _push_pair(cc_args, "-I", value);
    case <x-include>: x_paths.push(value);
    case <pkg-dir>:
      c.package_dirs = cons(value, c.package_dirs);
    case <native>: c.native_modules = cons(value, c.native_modules);
    case <no-cpp>: c.no_cpp = 1;
    case <live-syms>: c.live_symbols = 1;
    case <cpp-syms>: c.cpp_symbols = 1;
    case <tokens>: case <dump-cpp>: case <cpp-tokens>: case <dump-ast>:
    case <transforms>: case <dump-code>: case <symbols>: case <dump-csym>:
    case <dump-cache>: case <conform>: case <dump-defs>:
      c.dump = option.id;
    case <prefix>: c.prefix = value;
    case <sha256>: c.sha256 = value;
    case <index>: c.index = value;
    case <force>: c.force = 1;
    case <manifest>: c.manifest = value;
    case <target>: c.target = value;
    case <profile>: c.profile = value;
    case <kind>: _driver_kind(c, value);
    case <compile>: c.compile_only = 1;
    case <jobs>: c.jobs = _driver_count(value, 1, "job count");
    case <max-errors>:
      c.max_errors = _driver_count(value, 0, "error limit");
    case <diag-file>: c.diagnostics_file = value;
    case <fatal-warn>: c.fatal_warnings = 1;
    case <no-iface>: c.no_interfaces = 1;
    case <output>: c.output = value;
    case <build-dir>: c.build_dir = value;
    case <cc-db>:
      c.compile_commands = value;
      c.save_temps = 1;
    case <save-temp>: c.save_temps = 1;
    case <c-include>: _push_pair(cc_args, "-I", value);
    case <c-system>: _push_pair(cc_args, "-isystem", value);
    case <cc>: c.cc = value;
    case <ar>: c.ar = value;
    case <opt>: case <g>: cc_args.push(spelling);
    case <define>:
    case <undefine>:
      if (attached) {
        cpp_args.push(spelling);
        cc_args.push(spelling);
      }
      else {
        _push_pair(cpp_args, spelling, value);
        _push_pair(cc_args, spelling, value);
      }
    case <xcc>:
      if (cli_dependency_pass_through(value))
        x2c_driver_error(%"C dependency option is driver-owned '$value'");
      cc_args.push(value);
    case <lib-dir>: case <library>: if (attached) ld_args.push(spelling);
      else _push_pair(ld_args, spelling, value);
    case <rpath>: ld_args.push(%"-Wl,-rpath,$value");
    case <pthread>: cc_args.push(spelling); ld_args.push(spelling);
    case <framework>:
    case <xlinker>: _push_pair(ld_args, spelling, value);
    case <wl>: ld_args.push(spelling);
  }
}

/** Reads a package's native response options, expanding literal `{package}`
    after tokenization. Only native include/define/thread options, ordered
    archive/library/framework inputs, run-time library search directories,
    and the `-Wl,` and `-Xlinker` linker pass-throughs are admitted.
    `cc_args` and `ld_args`
    serve native actions; no source-preprocessing options are returned.
*/
CliRequest cli_package_options(String path, String package) {
  Array words = $auto([]);
  foreach (String word, cli_response_arguments(path))
    words.push(word.replace("{package}", package));
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <build>;
  Array includes = [], cpp = [], compile = [], link = [];
  for (int i = 0; i < words.len(); i++) {
    String argument = words[i];
    if (!argument) x2c_driver_error("empty package native argument");
    if (argument[0] != '-' && argument[0] != '@' &&
        argument.endswith(".a")) {
      link.push(argument);
      continue;
    }
    String spelling = NULL, value = NULL, int attached = 0;
    CliOption *option = _take_option(
      words, &i, CLI_BUILD, &spelling, &value, &attached);
    if (!option)
      x2c_driver_error(%"unsupported package native argument '$argument'");
    switch (option.id) {
      case <include>: case <c-include>: case <c-system>:
      case <define>: case <undefine>: case <lib-dir>: case <library>:
      case <rpath>: case <pthread>: case <framework>:
      case <wl>: case <xlinker>: break;
      default:
        x2c_driver_error(%"unsupported package native argument '$argument'");
    }
    _apply_option(request, option, spelling, value, attached,
      includes, cpp, compile, link);
  }
  includes.free();
  cpp.free();
  request.cc_args = compile.list_free();
  request.ld_args = link.list_free();
  return request;
}

// An outer Make owns concurrency unless the caller explicitly supplies -j.
static int _default_build_jobs(void) {
  if (report_make_owned()) return 1;
  long count = sysconf(_SC_NPROCESSORS_ONLN);
  return count > 0 && count <= INT_MAX ? (int) count : 1;
}

/* translate reports the diagnostic for x2c's single-dash long-option
   spellings. */
static void _one_dash_removed(String arg) {
  String attached;
  if (arg.len() > 2 && arg[0] == '-' && arg[1] != '-' &&
      _find_option(%"-$arg", CLI_TRANSLATE, &attached)) {
    fprintf(
      stderr,
      "x2c: error: one-dash long option '%s' was removed\n", arg);
    fprintf(stderr, "note: use '--%s'\n", arg + 1);
    exit(2);
  }
}

static CliRequest _parse_command(Array args, CliCommand *command) {
  Symbol name = command.name, int mask = command.mask;
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = name;
  request.jobs = mask & CLI_NATIVE ? _default_build_jobs() : 1;
  request.max_errors = 20;
  if (mask & CLI_NATIVE) request.kind = <executable>;
  Array inputs = [], run_args = [], x_paths = [];
  Array cpp_args = [], cc_args = [], ld_args = [], int operands = 0;
  int expanded_end = 0;
  for (int i = 1; i < args.len(); i++) {
    String arg = args[i], int dashed = arg && arg[0] == '-';
    /* bootstrap has no operand syntax, so `--`, `-o`, and a bare word are
       all unknown to it where the other commands accept them. */
    if (mask != CLI_BOOTSTRAP && !operands && dashed &&
        arg == "--") {
      operands = 1;
      continue;
    }
    if (mask == CLI_BOOTSTRAP && !dashed)
      x2c_driver_error(%"unexpected bootstrap operand '$arg'");
    // Expanded words are parsed next but never expanded again.
    if (mask == CLI_SCRIPT && !operands && i >= expanded_end &&
        arg.startswith("@")) {
      Array expanded = [];
      _expand_argument(expanded, arg, NULL);
      args.splice(i, 1, expanded);
      expanded_end = i + expanded.len();
      i--;
      continue;
    }
    if (operands || !dashed) {
      if (operands && name == <run>) run_args.push(arg);
      else inputs.push(arg);
      // Every word after a script belongs to the script, `@` and `--` too.
      if (mask == CLI_SCRIPT)
        while (++i < args.len()) run_args.push(args[i]);
      continue;
    }
    if (mask != CLI_BOOTSTRAP && arg == "-o") _removed_output();
    if ((mask & (CLI_BUILD | CLI_RUN)) && arg.startswith("--save-temps=")) {
      request.save_temps = 1;
      request.temps_dir = arg.remove_prefix("--save-temps=");
      if (!request.temps_dir)
        x2c_driver_error("--save-temps= requires a directory");
      continue;
    }
    String spelling = NULL, value = NULL, int attached = 0;
    CliOption *option =
      _take_option(args, &i, mask, &spelling, &value, &attached);
    if (!option) {
      if (mask == CLI_TRANSLATE) _one_dash_removed(arg);
      x2c_driver_error(%"unknown option '$arg'");
    }
    _apply_option(
      request, option, spelling, value, attached,
      x_paths,
      cpp_args, cc_args, ld_args);
  }
  request.inputs = inputs.list_free();
  request.run_args = run_args.list_free();
  request.include_dirs = x_paths.list_free();
  request.cpp_args = cpp_args.list_free();
  if (mask == CLI_BOOTSTRAP && !cc_args.len()) cc_args.push("-O2");
  request.cc_args = cc_args.list_free();
  request.ld_args = ld_args.list_free();
  if (request.package_dirs)
    request.package_dirs = request.package_dirs.reverse();
  request.native_modules = request.native_modules.reverse();
  if (mask == CLI_TRANSLATE && !request.inputs)
    x2c_driver_error("translate requires at least one input");
  if (request.inputs.cdr() && (request.dep_file || request.dep_target))
    x2c_driver_error("--dep-file and --dep-target require exactly one input");
  if (request.no_deps && (request.dep_file || request.dep_target ||
                          request.no_phony_deps))
    x2c_driver_error("--no-deps conflicts with dependency output options");
  if (request.compile_only && request.kind != <executable>)
    x2c_driver_error("--compile-only conflicts with a library target kind");
  if (mask == CLI_BOOTSTRAP && !request.prefix)
    x2c_driver_error("bootstrap requires --prefix <dir>");
  if (mask == CLI_ENV && request.inputs.cdr())
    x2c_driver_error("env accepts at most one name");
  if ((mask == CLI_INSTALL || mask == CLI_REMOVE || mask == CLI_NEW) &&
      (!request.inputs || request.inputs.cdr()))
    x2c_driver_error(%"${name} requires exactly one operand");
  if ((mask == CLI_LIST || mask == CLI_REPL) && request.inputs)
    x2c_driver_error(%"${name} accepts no operands");
  if (mask == CLI_SCRIPT && !request.inputs)
    x2c_driver_error("script requires a script file");
  return request;
}

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
  // A script's arguments are its own, so `script` expands response files
  // only while it parses its options.
  int script = argc > 1 && !strcmp(argv[1], "script");
  for (int i = 1; i < argc; i++) {
    if (script) args.push(String.new(argv[i]));
    else _expand_argument(args, String.new(argv[i]), NULL);
  }
  if (!args.len()) {
    _print_help(0);
    exit(2);
  }
  String first = args[0];
  if (!first)
    x2c_driver_error("expected a command, found an empty argument");
  if (first == "--help" || first == "-h") {
    _print_help(0);
    exit(0);
  }
  if (first == "--version" || first == "-V") {
    _print_version();
    exit(0);
  }
  if (first == "help") {
    if (args.len() == 1) {
      _print_help(0);
      exit(0);
    }
    if (args.len() > 2) x2c_driver_error("help accepts at most one command");
    String name = args[1];
    CliCommand *asked = _command_row(name);
    if (name == "help" || name == "--help" || name == "-h")
      _print_help(<help>);
    else if (asked) _print_help(asked.name);
    else x2c_driver_error(%"unknown help command '$name'");
    exit(0);
  }
  CliCommand *command = _command_row(first);
  if (command) return _parse_command(args, command);
  if (first == "-o") _removed_output();
  String attached;
  if (first.len() > 2 && first[0] == '-' && first[1] != '-' &&
      _find_option(%"-$first", CLI_TRANSLATE, &attached)) {
    fprintf(
      stderr,
      "x2c: error: one-dash long option '%s' was removed\n", first);
    fprintf(stderr, "note: use 'x2c translate --%s ...'\n", first + 1);
    exit(2);
  }
  if (first[0] != '-') _expected_command(first);
  x2c_driver_error(%"unknown command or global option '$first'");
}

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
  String home = x2c_home_packages();
  if (!Path.is_dir(home)) return request.package_dirs;
  return request.package_dirs.append(cons(home, NULL));
}
