#pragma indent
/*  x2c-lint.x -- report x2c source that is not this repository's idiom

    Usage: x2c-lint [--all | --rule CODE]... [--fix] [-I DIR]... FILE...
           x2c-lint --fmt-check [--fmt-diff] FILE...
           x2c-lint --rules

    Prints one line per finding, `FILE:LINE: KIND CODE: MESSAGE`, in line
    order. The language rules run unless `--all` or `--rule` selects rules;
    `--rules` prints the table of codes, families, kinds, and style-guide
    sections. Each file is scanned for the token rules and parsed by the
    compiler for the declaration rules. The compiler's diagnostics go to
    standard error; a file that does not parse gets the token rules only and
    makes the exit status 1. Findings alone leave the exit status 0.

    `--fix` rewrites each file with the proposed fixes of the selected
    rules that leave its generated C and header byte-identical, and prints
    `FILE: fixed N of M` after its findings.

    `--fmt-check` reports, for each file whose spacing formatting would
    change, `FILE: N lines to format`, and exits 1 when any would change;
    `--fmt-diff` also prints the unified difference. Neither writes; see
    `format.x` for what formatting changes.

    The command links the compiler's objects through `make commands`.
    `make commands-check` checks its findings on `tests/`.
*/
#include "frontend.x"
#include "lint.x"
#include "tokens.x"
#include "declarations.x"
#include "idioms.x"
#include "comments.x"
#include "validation.x"
#include "structure.x"
#include "fix.x"
#include "format.x"
#include "diff.x"
#include <stdio.h>
#include <string.h>

static void _usage(void):
  fputs("usage: x2c-lint [--all | --rule CODE]... [--fix] [-I DIR]... "
        "FILE...\n"
        "       x2c-lint --fmt-check [--fmt-diff] FILE...\n"
        "       x2c-lint --rules\n", stderr)

static void _preprocessor_errors(String text):
  fputs(text, stderr)

/* Parses `path` and runs the declaration rules. Returns 0 and prints the
   compiler's diagnostics when the unit does not parse. */
static int _parse(Lint l, Frontend frontend, String path):
  ParsedUnit parsed
  int ok = frontend.start(path, parsed)
  if ok:
    parsed.compiler.own_diagnostics()
    ok = parsed.collect(frontend) && parsed.parse()
  if ok:
    l.declaration_rules(parsed.compiler, parsed.ast)
    foreach List finding in l.findings: finding.promote()
    foreach List function in l.functions: function.promote()
  else if !parsed.compiler.diagnostics.printer:
    foreach Var entry in parsed.compiler.diagnostics():
      parsed.compiler.print_diagnostic(entry)
  parsed.close()
  return ok

/* Reports the files of `inputs` whose spacing formatting would change. */
static int _format_check(Array inputs, int diff):
  int status = 0, total = 0
  foreach String path in inputs:
    Path file = path
    Lint l = Lint.new(path, file.read_text(), {})
    int changed = l.format_changes()
    String text = diff && changed > 0 ? l.formatted() : NULL
    if text: fputs(Diff.unified(l.text, text, path, path), stdout)
    if changed < 0:
      printf("%s: not formatted; spacing changes would alter tokens\n", path)
      status = 1
    else if changed:
      printf("%s: %d lines to format\n", path, changed)
      status = 1
    if changed > 0: total += changed
  if total: printf("%d lines to format\n", total)
  return status

String x2c_embedded_identity(void)

int main(int argc, char **argv):
  x2c_initialize_command_environment(argv[0], x2c_embedded_identity())
  Map selected = {}
  Array inputs = [], include_dirs = []
  int fix = 0, format = 0, diff = 0
  for (int at = 1; at < argc; at++):
    String arg = argv[at]
    if arg == "--rules":
      Rule.print_table()
      return 0
    if arg == "-h" || arg == "--help":
      _usage()
      return 0
    if arg == "--fmt-check": format = 1
    else if arg == "--fmt-diff": format = diff = 1
    else if arg == "--fix": fix = 1
    else if arg == "--all":
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
  if format: return _format_check(inputs, diff)
  if !selected.len(): Rule.select_family(selected, <language>)
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest))
  request.command = <translate>
  request.include_dirs = include_dirs.list_free()
  Frontend frontend = Frontend.new(request)
  frontend.preprocessor_errors = _preprocessor_errors
  if !frontend.preload_macro_libraries(): return 1
  Path x2c = Path.dirname(Path.dirname(x2c_get_executable())).join("x2c")
  Array translate = [x2c, "translate", "--no-deps", "-q", "--plain"]
  foreach String dir in request.include_dirs:
    translate.push("-I")
    translate.push(dir)
  Path work = fix ? Path.temp_dir() : NULL
  int status = 0, count = inputs.len()
  Lint *lints = Scope.calloc(count + 1, sizeof(Lint))
  for (int at = 0; at < count; at++):
    Path file = inputs[at]
    Lint l = lints[at] = Lint.new(file, file.read_text(), selected)
    l.token_rules()
    l.idiom_rules()
    l.comment_rules()
    if !_parse(l, frontend, file): status = 1
    l.validation_rules()
    l.structure_rules()
  lint_corpus_rules(lints, count)
  for (int at = 0; at < count; at++):
    Lint l = lints[at]
    l.print()
    if !fix || !l.edits.len(): continue
    int proposed = l.edits.len()
    int fixed = l.apply_fixes(translate, work)
    if fixed < 0:
      printf("%s: not fixed; the file does not translate\n", l.path)
    else:
      printf("%s: fixed %d of %d\n", l.path, fixed, proposed)
  if work: Path.remove_tree(work)
  return status
