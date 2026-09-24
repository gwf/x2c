#pragma indent
/*  x2c-lint.x -- report x2c source that is not this repository's idiom

    Usage: x2c-lint [--all | --rule CODE]... [-I DIR]... FILE...
           x2c-lint --rules

    Prints one line per finding, `FILE:LINE: KIND CODE: MESSAGE`, in line
    order. The language rules run unless `--all` or `--rule` selects rules;
    `--rules` prints the table of codes, families, kinds, and style-guide
    sections. Each file is scanned for the token rules and parsed by the
    compiler for the declaration rules. The compiler's diagnostics go to
    standard error; a file that does not parse gets the token rules only and
    makes the exit status 1. Findings alone leave the exit status 0.

    The command links the compiler's objects through `make commands`.
    `make commands-check` checks its findings on `tests/`.
*/
#include "frontend.x"
#include "lint.x"
#include "tokens.x"
#include "declarations.x"
#include <stdio.h>
#include <string.h>

static void _usage(void):
  fputs("usage: x2c-lint [--all | --rule CODE]... [-I DIR]... FILE...\n"
        "       x2c-lint --rules\n", stderr)

static void _preprocessor_errors(String text):
  fputs(text, stderr)

/* Parses `path` and runs the declaration rules. Returns 0 and prints the
   compiler's diagnostics when the unit does not parse. */
static int _parse(Lint l, Frontend frontend, String path):
  ParsedUnit parsed
  int ok = frontend.start(path, &parsed)
  if ok:
    parsed.compiler.own_diagnostics()
    ok = parsed.collect(frontend) && parsed.parse()
  if ok: l.declaration_rules(parsed.compiler, parsed.ast)
  else if !parsed.compiler.diagnostics.printer:
    foreach Var entry in parsed.compiler.diagnostics():
      parsed.compiler.print_diagnostic(entry)
  parsed.close()
  return ok

String x2c_embedded_identity(void)

int main(int argc, char **argv):
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity())
  Map selected = {}
  Array inputs = [], include_dirs = []
  for (int at = 1; at < argc; at++):
    String arg = argv[at]
    if arg == "--rules":
      Rule.print_table()
      return 0
    if arg == "-h" || arg == "--help":
      _usage()
      return 0
    if arg == "--all":
      Rule.select_family(selected, <language>)
      Rule.select_family(selected, <style>)
    else if (arg == "--rule" || arg == "-I") && at + 1 < argc:
      String value = argv[++at]
      if arg == "-I": include_dirs.push(value)
      else if Rule.find(value): selected[value] = 1
      else:
        fprintf(stderr, "x2c-lint: unknown rule '%s'\n", value)
        return 2
    else if arg[0] == '-':
      _usage()
      return 2
    else: inputs.push(arg)
  if !inputs.len():
    _usage()
    return 2
  if !selected.len(): Rule.select_family(selected, <language>)
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest))
  request.command = <translate>
  request.include_dirs = include_dirs.list_free()
  Frontend frontend = Frontend.new(request)
  frontend.preprocessor_errors = _preprocessor_errors
  if !frontend.preload_macro_libraries(): return 1
  int status = 0
  foreach String path in inputs:
    Path file = path
    Lint l = Lint.new(path, file.read_text(), selected)
    l.token_rules()
    if !_parse(l, frontend, path): status = 1
    l.print()
  return status
