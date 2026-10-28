/*  parsing.x -- command and option parsing

    Copyright (c) 2026 Gary William Flake.
*/

// commands and options

module typedef struct CliCommand {
  Symbol name, const char *description;
} CliCommand;

module CliCommand cli_commands[] = {
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
module typedef struct CliOption {
  Symbol id, SymbolSet commands, Symbol group, String spelling;
  const char *value, *description, int hidden;
  String alias, label, int prefix;
  Symbol apply, int package_native;
  size_t offset;
} CliOption;

#define CLI_FIELD(kind, field) .apply = kind, \
  .offset = offsetof(struct CliRequest, field)

module CliOption cli_options[] = {
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
    "Use stable output without terminal rendering", 0,
    CLI_FIELD(<flag>, plain) },
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
    "Fail a unit that reports a warning", 1,
    CLI_FIELD(<flag>, fatal_warnings) },
  { <no-iface>, %<<translate>>, <source>, "--no-interfaces", NULL,
    "Collect every unit cold without reading .xi interfaces", 1,
    CLI_FIELD(<flag>, no_interfaces) },
  { <out-dir>, %<<translate>>, <output>, "--out-dir", "<dir>",
    "Write generated files under <dir> (default: .)", 0,
    CLI_FIELD(<text>, out_dir) },
  { <src-map>, %<<translate build run script>>, <output>, "--source-map",
    NULL, "Map generated C locations to original x2c sources", 0,
    CLI_FIELD(<flag>, source_map) },
  { <no-srcmap>, %<<build run>>, <output>, "--no-source-map", NULL,
    "Keep generated C locations in native diagnostics", 0 },
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
  { <output>, %<<build run>>, <output>, "-o", "<file>",
    "Name the executable, library, or single object", 0,
    .alias = "--output", CLI_FIELD(<text>, output) },
  { <rebuild>, %<<run script>>, <output>, "--rebuild", NULL,
    "Build even when the cached executable is current", 0,
    CLI_FIELD(<flag>, rebuild) },
  { <clean>, %<<run script>>, <output>, "--clean", NULL,
    "Remove the cached build and exit without running it", 0,
    CLI_FIELD(<flag>, clean) },
  { <build-dir>, %<<build run>>, <output>, "--build-dir",
    "<dir>", "Store generated C, objects, deps, and state here", 0,
    CLI_FIELD(<text>, build_dir) },
  { <cc-db>, %<<build run>>, <output>, "--compile-commands",
    "<file>", "Write native compile commands and retain generated files", 0 },
  { <save-temp>, %<<build run>>, <output>,
    "--save-temps", NULL,
    "Retain and reuse intermediates (default: .x2c-build)", 0,
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

/* One argument list read into a request. Options extend the argument lists
   in the order they are written. `operands` is set after `--`, and a
   script's words before `expanded` came from a response file. */
static typedef struct Parse {
  CliRequest request, Array args, int operands, expanded;
  Array inputs, run_args, include_dirs, cpp_args, cc_args, ld_args;
} Parse;

// options

/* One option as written: its table row, its spelling up to any `=`, its
   value, and whether the value shares the spelling's word, as `-Idir`
   does. The C compiler and linker receive an option as it was written. */
static typedef struct Given {
  CliOption *option, String spelling, value, int attached;
} Given;

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
  Array args = auto CliRequest.read_arguments(argc, argv);
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
  if (first == "-o") _cli_fail_output_command();
  String spelling = _two_dash(first);
  if (spelling)
    _cli_fail_one_dash_removed(first, %"x2c translate $spelling ...");
  if (first[0] != '-') _cli_fail_expected_command(first);
  $fail.cli_command_unknown(first);
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
  Array words = auto [];
  foreach (String word in _response_arguments(path))
    words.push(word.replace("{package}", package));
  CliRequest request = xcalloc(1, sizeof(struct CliRequest));
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

// diagnostics

/** Reports whether a raw command name belongs to the built-in parser. */
int CliRequest.is_builtin(const char *word) =>
  !strcmp(word, "help") || _command_row(word) != NULL;

// command and option parsing

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

/* The command spelled `word`, or NULL. `help` never matches: it parses no
   options and is not a subject of `x2c help <command>`. */
static CliCommand *_command_row(const char *word) {
  for (CliCommand *row = cli_commands; row.name; row++)
    if (row.name != <help> && strcmp(word, row.name.str()) == 0) return row;
  return NULL;
}

/* Named retention selects the build directory; other options use the table. */
static void _option(Parse &p, String arg, int &i) {
  if (arg == "-o" && p.request.command == <translate>)
    _cli_fail_output_command();
  if ((p.request.command in %<<build run>>) &&
      arg.startswith("--save-temps=")) {
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
  r.build_dir = arg.remove_prefix("--save-temps=");
  if (!r.build_dir)
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
      (given.option.id in %<<output out-dir build-dir>>))
    $fail.cli_option_value_required(written);
  return given;
}

/* An option without an arm here sets the request field its row names. */
static void _apply(Parse &p, Given given) {
  CliRequest r = p.request;
  String spelling = given.spelling, value = given.value;
  switch (given.option.id) {
    case <help>: _help_exit(r.command, 0); break;
    case <no-srcmap>: r.source_map = 0; break;
    case <color>: r.color_mode = _color_mode(value); break;
    case <include>: _include_dir(p, value); break;
    case <x-include>: p.include_dirs.push(value); break;
    case <tokens>: case <dump-cpp>: case <cpp-tokens>: case <dump-ast>:
    case <transforms>: case <dump-code>: case <symbols>: case <dump-csym>:
    case <dump-cache>: case <conform>: case <dump-defs>:
      r.dump = given.option.id; break;
    case <kind>: r.kind_explicit = 1; r.kind = _target_kind(value); break;
    case <jobs>: r.jobs = _count(value, 1, "job count"); break;
    case <max-errors>: r.max_errors = _count(value, 0, "error limit"); break;
    case <cc-db>: r.compile_commands = value; r.save_temps = 1; break;
    case <c-include>: _push_pair(p.cc_args, "-I", value); break;
    case <c-system>: _push_pair(p.cc_args, "-isystem", value); break;
    case <opt>: case <g>: p.cc_args.push(spelling); break;
    case <define>: case <undefine>:
      _forward(p.cpp_args, given); _forward(p.cc_args, given); break;
    case <xcc>: p.cc_args.push(_xcc_argument(value)); break;
    case <lib-dir>: case <library>: _forward(p.ld_args, given); break;
    case <rpath>: p.ld_args.push(%"-Wl,-rpath,$value"); break;
    case <pthread>: p.cc_args.push(spelling); p.ld_args.push(spelling); break;
    case <framework>: case <xlinker>:
      _push_pair(p.ld_args, spelling, value); break;
    case <wl>: p.ld_args.push(spelling); break;
    default: _set_field(r, *given.option, value); break;
  }
}

static Symbol _color_mode(String value) {
  if (!value)
    Diagnostics.driver_error("--color requires auto, always, or never");
  switch (value) {
    case "auto": return <auto>;
    case "always": return <always>;
    case "never": return <never>;
  }
  $fail.cli_color_invalid(value);
}

static Symbol _target_kind(String value) {
  String refusal = NULL;
  Symbol kind = TargetKind.named(value, refusal);
  if (refusal) Diagnostics.driver_error(refusal);
  if (!kind) $fail.cli_target_unknown(value);
  return kind;
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

static void _set_field(CliRequest r, CliOption &option, String value) {
  char *field = (char *) r + option.offset;
  switch (option.apply) {
    case <flag>: *(int *) field = 1; break;
    case <text>: *(String *) field = value; break;
    case <list>: *(List *) field = cons(value, *(List *) field); break;
  }
}

static void _cli_fail_output_command(void) {
  _fail(
    "option '-o' needs build or run",
    "use '--out-dir' for translation directories");
}

static void _cli_fail_expected_command(String arg) {
  _fail(
    %"expected a command before '$arg'",
    %"use 'x2c translate $arg'");
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

/* Finds the option `spelling` names for `command`. A two-letter option that
   takes a value also accepts it in the same argument, as `-Idir`, and
   reports the remainder through `attached`. */
static CliOption *_find_option(
  String spelling, Symbol command, String &attached) {
  attached = NULL;
  int length = spelling.len();
  for (CliOption *option = cli_options; option.spelling; option++) {
    if (!(command in option.commands)) continue;
    String form = option.spelling;
    int form_length = form.len();
    int longer = length > form_length && spelling.startswith(form);
    if (option.prefix) {
      if (longer) return option;
      continue;
    }
    if (spelling == form || spelling == option.alias) return option;
    if (option.value && form_length == 2 && longer) {
      attached = spelling[2:];
      return option;
    }
  }
  return NULL;
}

static void _cli_fail_one_dash_removed(String arg, String use) {
  _fail(%"one-dash long option '$arg' was removed", %"use '$use'");
}



/* Prints an error and perhaps a note, then exits with status 2. The exit
   runs the atexit handlers, which Diagnostics.driver_error skips. */
module void _fail(String message, String note) {
  fprintf(stderr, "x2c: error: %s\n", message);
  if (note) fprintf(stderr, "note: %s\n", note);
  exit(2);
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
