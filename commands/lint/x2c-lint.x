#pragma indent
/*  x2c-lint.x -- report x2c source that is not this repository's idiom

    Usage: x2c-lint [--all | --rule CODE]... [--fix] [-I DIR]... FILE...
           x2c-lint --fmt-check [--fmt-diff] FILE...
           x2c-lint --rules

    Prints each finding as `FILE:LINE: KIND CODE RULE-ID: MESSAGE`, in line
    order. The language rules run unless `--all` or `--rule` selects rules;
    `--rules` prints the table of codes, families, kinds, and standard rule
    IDs. Each file is scanned for the token rules and parsed by the
    compiler for the declaration and member-arrow rules. The compiler's
    diagnostics go to standard error; a file that does not parse gets the
    token rules only and makes the exit status 1. Findings alone leave the
    exit status 0. An unreadable input reports its path on standard error,
    makes the exit status 1, and leaves other readable inputs available.
    `-` names an ordinary file in both lint and formatting modes.

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
#include "meta-project.x"
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
#include "args.x"
#include <stdio.h>
#include <string.h>

static void _usage(void):
  fputs("usage: x2c-lint [--all | --rule CODE]... [--fix] [-I DIR]... "
        "FILE...\n"
        "       x2c-lint --fmt-check [--fmt-diff] FILE...\n"
        "       x2c-lint --rules\n", stderr)

static void _preprocessor_errors(String text):
  fputs(text, stderr)

static void _input_error(List detail):
  Var path = detail.assoc(<path>), error = detail.assoc(<errno>)
  fprintf(stderr, "x2c-lint: %s: %s\n",
          path is <string> ? path.string() : "compiler support files",
          error.is_integer() ? strerror(error.int()) : "cannot read input")

static int _read(Path path, String &text):
  try text = path.read_text()
  catch %((!or not-found io-fail) *detail):
    _input_error(detail)
    return 0
  return 1

/* Parses `path` and runs the rules that read its parse. Returns 0 and
   prints the compiler's diagnostics when the unit does not parse. */
static int _parse(Lint l, Frontend frontend, String path):
  ParsedUnit parsed
  if !frontend.open_reporting(path, parsed): return 0
  l.declaration_rules(parsed.compiler, parsed.ast)
  l.member_arrows(parsed.compiler, parsed.ast)
  l.validation_rules(parsed.compiler, parsed.ast)
  foreach List finding in l.findings: finding.promote()
  foreach List edit in l.edits: edit.promote()
  foreach List function in l.functions: function.promote()
  parsed.close()
  return 1

/* Reports the files of `inputs` whose spacing formatting would change. */
static int _format_check(Array inputs, int diff):
  int status = 0, total = 0
  foreach String path in inputs:
    String source
    if !_read(path, source):
      status = 1
      continue
    Lint l = Lint.new(path, source, {})
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
  Map options = NULL
  try options = Args.parse(Args.from_argv(argc, argv), %(
    (-h --help) (--rules) (--fmt-check) (--fmt-diff) (--fix) (--all)
    (--rule (value CODE) repeated) (-I (value DIR) repeated)
    (inputs repeated)))
  catch %(bad-arg *):
    _usage()
    return 2
  if options["rules"]:
    Rule.print_table()
    return 0
  if options["help"]:
    _usage()
    return 0
  Map selected = {}
  foreach String code in options["rule"].list():
    if !Rule.find(code):
      fprintf(stderr, "x2c-lint: unknown rule '%s'\n", code)
      return 2
    selected[code] = 1
  Array inputs = options["inputs"].list()
  if !inputs.len():
    _usage()
    return 2
  if options["fmt-check"] || options["fmt-diff"]:
    return _format_check(inputs, options["fmt-diff"].int())
  if options["all"]:
    Rule.select_family(selected, <language>)
    Rule.select_family(selected, <style>)
  if !selected.len(): Rule.select_family(selected, <language>)
  int fix = options["fix"].int()
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest))
  request.command = <translate>
  request.include_dirs = options["I"]
  Frontend frontend = Frontend.new(request)
  frontend.preprocessor_errors = _preprocessor_errors
  if !frontend.preload_macro_libraries(): return 1
  try frontend.prepare_meta(inputs)
  catch %((!or not-found io-fail) *detail):
    _input_error(detail)
    return 1
  Path x2c = Path.dirname(Path.dirname(x2c_get_executable())).join("x2c")
  Array translate = [x2c, "translate", "--no-deps", "-q", "--plain"]
  foreach String dir in request.include_dirs:
    translate.push("-I")
    translate.push(dir)
  Path work = fix ? Path.temp_dir() : NULL
  int status = 0, count = 0
  Lint *lints = Scope.calloc(inputs.len() + 1, sizeof(Lint))
  foreach Path file in inputs:
    String source
    if !_read(file, source):
      status = 1
      continue
    Lint l = lints[count++] = Lint.new(file, source, selected)
    l.token_rules()
    l.idiom_rules()
    l.comment_rules()
    if !_parse(l, frontend, file): status = 1
    l.structure_rules()
  lint_corpus_rules(lints, count)
  for (int at = 0; at < count; at++):
    Lint l = lints[at]
    l.suppression_rules()
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
