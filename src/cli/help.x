/*  help.x -- command help and option rendering

    Copyright (c) 2026 Gary William Flake.
*/

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
      The output directory defaults to the current directory. Use --out-dir
      to select another directory; missing directories are created.
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
      unexpanded wildcard operands are rejected.
      Direct builds default to a.out, lib<first-input-stem>.a, or
      <first-input-stem>.so. Compile-only builds default to <stem>.o in the
      current directory; a named build directory keeps multiple objects there.
      Manifest products default to <project>/.x2c-build/<target-product>.
      One manifest target is selected automatically; several need --target
      or project.default-target. Profiles apply only when selected.
      Direct intermediates are temporary. --save-temps retains and reuses them
      in .x2c-build; --save-temps=<dir> and --build-dir <dir> select a directory.
      The last named directory wins. Under Make, jobs default to one;
      otherwise they default to the online processor count.
      --debug logs compiler activity; -g emits native debug information.
      Source mapping is on by default; -g -O0 debugs original x2c sources.
      --no-source-map uses generated C locations.") },
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
      x2c returns the program's exit status.
      Explicit inputs use runs/ in the script cache, with argv[0] set to
      the first input's absolute path. Unchanged runs skip the build.
      --rebuild builds again; --clean removes the entry without running it.
      -o, --build-dir, --save-temps, and --compile-commands bypass that cache.
      --save-temps retains and reuses intermediates in .x2c-build.
      --save-temps=<dir> and --build-dir <dir> select the retained directory;
      the last named directory wins. Manifest products default to
      <project>/.x2c-build/<target-product>.
      --debug logs compiler activity; use -g -O0 for source debugging.
      --no-source-map uses generated C locations.
      See 'x2c help build' for other build defaults.") },
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
      and etc/compiler-prelude.x. Package roots join with ':'.") },
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

// help

/* Prints top-level help for command 0, or one command's help, and exits. */
module void _help_exit(Symbol command, int status) {
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

static int _in_group(CliOption &option, Symbol command, Symbol group) =>
  _listed(option, command) && option.group == group;

static int _listed(CliOption &option, Symbol command) =>
  !option.hidden && (command in option.commands);

static void _print_option(const CliOption &option) {
  String spelled;
  if (option.label) spelled = option.label;
  else if (option.alias) spelled = %"$(option.spelling), $(option.alias)";
  else spelled = option.spelling;
  String label = option.value ? %"$spelled $(option.value)" : spelled;
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
