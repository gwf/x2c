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
  List cc_args, ld_args, String out_dir, dep_file, dep_target, manifest;
  String target, profile, output, build_dir, temps_dir, label, state_seed;
  String prefix, cc, ar, compile_commands, Symbol kind, color_mode;
  // The one --dump-* option in force, or 0. Each prints and stops.
  Symbol dump;
  int jobs, debugging, verbose, dry_run, quiet, plain, nested, no_deps;
  int no_phony_deps, compile_only, kind_explicit, save_temps, no_cpp;
  int live_symbols, cpp_symbols, source_map, source_facts;
  SourceView sources;
} *CliRequest;

#pragma private

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "buffer.x"
#include "utils.x"

// cli metadata

enum {
  CLI_TOP       = 1,
  CLI_TRANSLATE = 2,
  CLI_BUILD     = 4,
  CLI_RUN       = 8,
  CLI_BOOTSTRAP = 32
};

typedef struct CliOption {
  Symbol id, int commands, Symbol group, const char *spelling, *value;
  const char *description, int hidden;
} CliOption;

typedef struct CliCommand {
  Symbol name, int mask, const char *description;
} CliCommand;

// `help` parses no options of its own, so it carries the top-level mask.
static CliCommand cli_commands[] = {
  { <translate>, CLI_TRANSLATE, "Translate .x files to .c and .h files" },
  { <build>,     CLI_BUILD,     "Translate, compile, and optionally link a target" },
  { <run>,       CLI_RUN,       "Build an executable and run it" },
  { <bootstrap>, CLI_BOOTSTRAP, "Install a native x2c from a APE binary" },
  { <help>,      CLI_TOP,       "Show help for x2c or one command" },
  { 0 }
};

static CliOption cli_options[] = {
  { <help>, CLI_TOP | CLI_TRANSLATE | CLI_BUILD | CLI_RUN | CLI_BOOTSTRAP,
    <general>, "-h, --help", NULL, "Show help and exit", 0 },
  { <version>, CLI_TOP, <global>, "-V, --version", NULL,
    "Show the x2c version and exit", 0 },
  { <verbose>, CLI_TOP | CLI_TRANSLATE | CLI_BUILD | CLI_RUN | CLI_BOOTSTRAP,
    <general>, "-v, --verbose", NULL, "Show commands as they are executed", 0 },
  { <dry-run>, CLI_TOP | CLI_TRANSLATE | CLI_BUILD | CLI_RUN,
    <general>, "-###", NULL, "Show commands without executing them", 0 },
  { <quiet>, CLI_TOP | CLI_TRANSLATE | CLI_BUILD | CLI_RUN | CLI_BOOTSTRAP,
    <general>, "-q, --quiet", NULL, "Suppress successful progress and receipts", 0 },
  { <plain>, CLI_TOP | CLI_TRANSLATE | CLI_BUILD | CLI_RUN | CLI_BOOTSTRAP,
    <general>, "--plain", NULL, "Use stable output without terminal rendering", 0 },
  { <color>, CLI_TOP | CLI_TRANSLATE | CLI_BUILD | CLI_RUN | CLI_BOOTSTRAP,
    <general>, "--color", "<auto|always|never>", "Control terminal color", 0 },
  { <debug>, CLI_TOP | CLI_TRANSLATE | CLI_BUILD | CLI_RUN,
    <general>, "--debug", NULL, "Enable compiler debug logging", 0 },
  { <out-dir>, CLI_TRANSLATE, <output>, "--out-dir", "<dir>",
    "Write generated files under <dir> (default: .)", 0 },
  { <src-map>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <output>, "--source-map",
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
    "executable or static-library", 0 },
  { <compile>, CLI_BUILD, <target>, "-c, --compile-only",
    NULL, "Produce object files without linking", 0 },
  { <jobs>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <target>, "-j, --jobs",
    "<count>", "Maximum parallel translation and compilation jobs", 0 },
  { <output>, CLI_BUILD | CLI_RUN, <output>, "--output", "<file>",
    "Name the executable, library, or single object", 0 },
  { <build-dir>, CLI_BUILD | CLI_RUN, <output>, "--build-dir",
    "<dir>", "Store generated C, objects, deps, and state here", 0 },
  { <cc-db>, CLI_BUILD | CLI_RUN, <output>, "--compile-commands",
    "<file>", "Write native compile commands and retain generated files", 0 },
  { <save-temp>, CLI_BUILD | CLI_RUN, <output>,
    "--save-temps[=<dir>]", NULL,
    "Keep generated C and other intermediate files", 0 },
  { <prefix>, CLI_BOOTSTRAP, <output>, "--prefix", "<dir>",
    "Install native x2c and sources under <dir>", 0 },
  { <include>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "-I", "<dir>", "Add a shared x2c/C include directory", 0 },
  { <x-include>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--x-include-dir", "<dir>", "Add an x2c-only include directory", 0 },
  { <c-include>, CLI_BUILD | CLI_RUN, <source>,
    "--c-include-dir", "<dir>", "Add a C-only ordinary include directory", 0 },
  { <c-system>, CLI_BUILD | CLI_RUN, <source>,
    "--c-system-dir", "<dir>", "Add a C-only system include directory", 0 },
  { <pkg-dir>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--package-dir", "<dir>", "Add a directory of x2c packages", 0 },
  { <no-cpp>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--no-cpp", NULL, "Skip symbol collection and preprocessing", 0 },
  { <live-syms>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--live-symbols", NULL,
    "Collect symbols through the host preprocessor", 0 },
  { <cpp-syms>, CLI_TRANSLATE | CLI_BUILD | CLI_RUN, <source>,
    "--cpp-symbols", NULL, "Use CPP collection for this translation", 0 },
  { <cc>, CLI_BUILD | CLI_RUN | CLI_BOOTSTRAP, <c-compiler>,
    "--cc", "<program>",
    "Use <program> as the host C compiler", 0 },
  { <ar>, CLI_BUILD | CLI_BOOTSTRAP, <c-compiler>,
    "--ar", "<program>",
    "Use <program> as the static-library archiver", 0 },
  { <opt>, CLI_BUILD | CLI_RUN | CLI_BOOTSTRAP,
    <c-compiler>,
    "-O0, -O1, -O2, -O3, -Os", NULL, "Set C optimization", 0 },
  { <g>, CLI_BUILD | CLI_RUN, <c-compiler>, "-g", NULL,
    "Emit debug information", 0 },
  { <define>, CLI_BUILD | CLI_RUN, <c-compiler>, "-D",
    "<name>[=<value>]", "Define a C preprocessor macro", 0 },
  { <undefine>, CLI_BUILD | CLI_RUN, <c-compiler>, "-U", "<name>",
    "Undefine a C preprocessor macro", 0 },
  { <xcc>, CLI_BUILD | CLI_RUN, <c-compiler>, "-Xcc", "<arg>",
    "Pass one argument only to C compilation", 0 },
  { <lib-dir>, CLI_BUILD | CLI_RUN, <linker>, "-L", "<dir>",
    "Add a library search directory", 0 },
  { <library>, CLI_BUILD | CLI_RUN, <linker>, "-l", "<name>",
    "Link library <name>", 0 },
  { <wl>, CLI_BUILD | CLI_RUN, <linker>, "-Wl,<arg>[,<arg>...]",
    NULL, "Pass comma-separated arguments to the linker", 0 },
  { <pthread>, CLI_BUILD | CLI_RUN, <c-compiler>, "-pthread", NULL,
    "Enable native threading for compilation and linking", 0 },
  { <framework>, CLI_BUILD | CLI_RUN, <linker>, "-framework", "<name>",
    "Link a native framework on macOS", 0 },
  { <xlinker>, CLI_BUILD | CLI_RUN, <linker>, "-Xlinker", "<arg>",
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
  { <snapshot>, CLI_TRANSLATE, <inspection>,
    "--dump-symbol-snapshot", NULL,
    "Print a complete symbol snapshot and stop", 0 },
  { <hdr-syms>, CLI_TRANSLATE, <inspection>,
    "--dump-header-symbols", NULL,
    "Print the header-symbol artifact and stop", 0 },
  { 0 }
};

// diagnostics

static void _removed_output(void) {
  fputs("x2c: error: option '-o' was removed\n", stderr);
  fputs(
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
  char label[128];
  if (option.value)
    snprintf(label, sizeof(label), "%s %s", option.spelling, option.value);
  else snprintf(label, sizeof(label), "%s", option.spelling);
  int indent = label[0] == '-' && label[1] == '-' ? 6 : 2;
  _print_help_row(label, option.description, indent);
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
    <global>, <target>, <output>, <source>, <c-compiler>,
    <linker>, <inspection>, <general>
  };
  for (int i = 0; i < 8; i++) {
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
    %"Usage:
  x2c <command> [options]

x2c translates x2c source to C and can optionally compile and link the
result with the host C toolchain.

Commands:
");
  for (CliCommand *command = cli_commands; command.name; command++)
    printf("  %-12s%s\n", command.name.str(), command.description);
  _print_options(0);
  puts(
    %"
Input syntax:
");
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  _print_help_row("--", "End option parsing", 2);
  puts(
    %"
Run 'x2c help <command>' or 'x2c <command> --help' for command help.");
}

static void _print_translate_help(void) {
  puts(
    %"Usage:
  x2c translate [options] <input.x>...

Translate each x2c input into a matching C source and header.");
  _print_options(<translate>);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  _print_help_row("--", "End option parsing", 2);
  puts("");
  puts(
    %"The output directory defaults to the current directory and must already
exist. Use --out-dir to select another directory.
Shell wildcards are allowed because the shell expands them; x2c does not
interpret wildcard characters in input operands.");
}

static void _print_driver_help(Symbol command) {
  if (command == <build>)
    puts(
      %"Usage:
  x2c build [options] <input>...
  x2c build [options] [--target <name>]

Translate x2c sources, compile C sources, and link one target.
With explicit inputs, the default target is an executable. Without
inputs, x2c reads the nearest x2c.toml and builds its default
target.");
  else
    puts(
      %"Usage:
  x2c run [build-options] <input>... [-- <argument>...]
  x2c run [build-options] [--target <name>] [-- <argument>...]

Build one executable and run it. Arguments after -- are passed
unchanged to the executable.");
  _print_options(command);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  if (command == <run>)
    _print_help_row("--", "End build options and begin program arguments", 2);
  else _print_help_row("--", "End option parsing", 2);
  puts("");
  if (command == <build>)
    puts(
      %"Inputs may be .x, .c, .o, or .a files. x2c links its runtime and
required platform libraries automatically. Directory operands and
unexpanded wildcard operands are rejected.");
  else
    puts(
      %"The selected target must be executable. After a successful build,
x2c returns the program's exit status.");
}

static void _print_bootstrap_help(void) {
  puts(
    %"Usage:
  x2c bootstrap --prefix <dir> [options]

Extract the source distribution carried by this APE and use the host
C compiler and archiver to install a native x2c under <dir>.");
  _print_options(<bootstrap>);
  _print_help_row(
    "@<file>", "Read additional arguments from a response file", 2);
  puts("");
  puts(
    %"The seed supplies x2c sources and headers. A GCC- or Clang-compatible
C compiler and a compatible archiver must be installed.");
}

static void _print_help(Symbol command) {
  switch (command) {
    case 0:            _print_top_help();             break;
    case <translate>:  _print_translate_help();       break;
    case <build>:
    case <run>:        _print_driver_help(command);   break;
    case <bootstrap>:  _print_bootstrap_help();       break;
    case <help>:
      puts(
        %"Usage:
  x2c help [command]

Show top-level help, or help for translate, build, run, or
bootstrap.");
      break;
    default: x2c_driver_error(%"unknown help command '${command.str()}'");
  }
}

static void _print_version(void) {
  printf("x2c 0.12.0\n");
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
  foreach (String entry, stack) if (strcmp(entry, path) == 0) return 1;
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
  Array arguments = %[];
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
  char *resolved = realpath(path, NULL);
  String identity = resolved ? String.new(resolved) : path;
  if (resolved) free(resolved);
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

static CliOption *_find_option(
  const char *spelling, int command_mask, const char **attached) {
  size_t spelling_length = strlen(spelling);
  *attached = NULL;
  for (CliOption *option = cli_options; option.spelling; option++) {
    if (!(option.commands & command_mask)) continue;
    const char *start = option.spelling;
    while (*start) {
      const char *comma = strstr(start, ", ");
      const char *end = comma ? comma : start + strlen(start);
      const char *suffix = strchr(start, '[');
      if (suffix && suffix < end) end = suffix;
      const char *placeholder = strchr(start, '<');
      if (placeholder && placeholder < end &&
          strncmp(spelling, start, (size_t) (placeholder - start)) == 0)
        return option;
      size_t length = (size_t) (end - start);
      if (spelling_length == length && strncmp(spelling, start, length) == 0)
        return option;
      if (option.value && length == 2 &&
          spelling_length > 2 &&
          strncmp(spelling, start, 2) == 0) {
        *attached = spelling + 2;
        return option;
      }
      if (length >= 2 && start[0] == '-' && start[1] == 'O' &&
          spelling[0] == '-' && spelling[1] == 'O' && spelling[2])
        return option;
      if (!comma) break;
      start = comma + 2;
    }
  }
  return NULL;
}

/* Reads the option at `*index` for `mask`, advancing it past a separate
   value argument. Returns NULL for an unknown spelling so each command can
   phrase its own diagnostic. The driver asks for `spelling` and `attached`
   because it forwards the argument as written to the C compiler and linker;
   translate and bootstrap pass NULL. */
static CliOption *_take_option(
  Array args, int *index, int mask,
  String *spelling, String *value, int *attached) {
  String arg = args[*index], written = arg, color = NULL, int color_equal = 0;
  if (arg.startswith("--color=")) {
    color_equal = 1;
    color = arg.remove_prefix("--color=");
    written = "--color";
  }
  const char *suffix = NULL;
  CliOption *option = _find_option(written, mask, &suffix);
  if (!option) return NULL;
  if (spelling) *spelling = written;
  if (attached) *attached = suffix != NULL;
  *value = suffix;
  if (option.value && !*value && !color_equal) {
    if (++*index == args.len())
      x2c_driver_error(%"option requires a value '$arg'");
    *value = args[*index];
  }
  if (color_equal) *value = color;
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
  else if (value == "shared-library")
    x2c_driver_error("shared-library is not supported by this compiler");
  else x2c_driver_error(%"unknown target kind '$value'");
}

static void _driver_jobs(CliRequest request, String value) {
  if (!value || !value[0])
    x2c_driver_error("--jobs requires a positive count");
  char *end = NULL;
  errno = 0;
  long jobs = strtol(value, &end, 10);
  if (errno || *end || jobs < 1 || jobs > INT_MAX)
    x2c_driver_error(%"invalid job count '$value'");
  request.jobs = (int) jobs;
}

static void _apply_option(
  CliRequest c, CliOption *option, String spelling, String value,
  int attached, Array x_paths, Array cpp_args, Array cc_args, Array ld_args) {
  switch (option.id) {
    case <help>: _print_help(c.command);
      exit(0);
    case <verbose>: c.verbose = 1; break;
    case <dry-run>: c.dry_run = 1; break;
    case <quiet>: c.quiet = 1; break;
    case <plain>: c.plain = 1; break;
    case <color>:
      if (!value)
        x2c_driver_error("--color requires auto, always, or never");
      if (value == "auto") c.color_mode = <auto>;
      else if (value == "always") c.color_mode = <always>;
      else if (value == "never") c.color_mode = <never>;
      else x2c_driver_error(%"invalid color mode '$value'");
      break;
    case <debug>: c.debugging = 1; break;
    case <out-dir>: c.out_dir = value; break;
    case <src-map>: c.source_map = 1; break;
    case <no-deps>: c.no_deps = 1; break;
    case <dep-file>: c.dep_file = value; break;
    case <dep-target>: c.dep_target = value; break;
    case <no-phony>: c.no_phony_deps = 1; break;
    case <include>: x_paths.push(value);
      // build and run also hand the directory to the C compiler.
      if (c.command != <translate>) _push_pair(cc_args, "-I", value);
      break;
    case <x-include>: x_paths.push(value); break;
    case <pkg-dir>:
      c.package_dirs = cons(value, c.package_dirs);
      break;
    case <no-cpp>: c.no_cpp = 1; break;
    case <live-syms>: c.live_symbols = 1; break;
    case <cpp-syms>: c.cpp_symbols = 1; break;
    case <tokens>: case <dump-cpp>: case <cpp-tokens>: case <dump-ast>:
    case <transforms>: case <dump-code>: case <symbols>: case <dump-csym>:
    case <dump-cache>: case <conform>: case <snapshot>: case <hdr-syms>:
      c.dump = option.id;
      break;
    case <prefix>: c.prefix = value; break;
    case <manifest>: c.manifest = value; break;
    case <target>: c.target = value; break;
    case <profile>: c.profile = value; break;
    case <kind>: _driver_kind(c, value); break;
    case <compile>: c.compile_only = 1; break;
    case <jobs>: _driver_jobs(c, value); break;
    case <output>: c.output = value; break;
    case <build-dir>: c.build_dir = value; break;
    case <cc-db>:
      c.compile_commands = value;
      c.save_temps = 1;
      break;
    case <save-temp>: c.save_temps = 1; break;
    case <c-include>: _push_pair(cc_args, "-I", value);
      break;
    case <c-system>: _push_pair(cc_args, "-isystem", value);
      break;
    case <cc>: c.cc = value; break;
    case <ar>: c.ar = value; break;
    case <opt>: case <g>: cc_args.push(spelling);
      break;
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
      break;
    case <xcc>:
      if (cli_dependency_pass_through(value))
        x2c_driver_error(%"C dependency option is driver-owned '$value'");
      cc_args.push(value);
      break;
    case <lib-dir>: case <library>: if (attached) ld_args.push(spelling);
      else _push_pair(ld_args, spelling, value);
      break;
    case <pthread>: cc_args.push(spelling); ld_args.push(spelling); break;
    case <framework>:
    case <xlinker>: _push_pair(ld_args, spelling, value);
      break;
    case <wl>: ld_args.push(spelling); break;
  }
}

/** Reads a package's native response options, expanding literal `{package}`
    after tokenization. Only native include/define/thread options and ordered
    archive/library/framework inputs are admitted. `cc_args` and `ld_args`
    serve native actions; no source-preprocessing options are returned.
*/
CliRequest cli_package_options(String path, String package) {
  Array words = $auto(%[]);
  foreach (String word, cli_response_arguments(path))
    words.push(word.replace("{package}", package));
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <build>;
  Array includes = %[], cpp = %[], compile = %[], link = %[];
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
      case <pthread>: case <framework>: break;
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

/* translate reports the diagnostic for x2c's single-dash long-option
   spellings. */
static void _one_dash_removed(String arg) {
  const char *attached;
  if (strlen(arg) > 2 && arg[0] == '-' && arg[1] != '-' &&
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
  request.jobs = 1;
  if (mask & (CLI_BUILD | CLI_RUN)) request.kind = <executable>;
  Array inputs = %[], run_args = %[], x_paths = %[];
  Array cpp_args = %[], cc_args = %[], ld_args = %[], int operands = 0;
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
    if (operands || !dashed) {
      if (operands && name == <run>) run_args.push(arg);
      else inputs.push(arg);
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
  if (mask == CLI_BOOTSTRAP && !cc_args.length) cc_args.push("-O2");
  request.cc_args = cc_args.list_free();
  request.ld_args = ld_args.list_free();
  if (request.package_dirs)
    request.package_dirs = request.package_dirs.reverse();
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
  Array args = $auto(%[]);
  for (int i = 1; i < argc; i++)
    _expand_argument(args, String.new(argv[i]), NULL);
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
  const char *attached;
  if (strlen(first) > 2 && first[0] == '-' && first[1] != '-' &&
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

/** Returns whether `request` selects a terminating inspection or dump mode. */
int CliRequest.inspects(CliRequest request) => request.dump != 0;
