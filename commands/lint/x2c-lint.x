#pragma indent
/*  x2c-lint.x -- report x2c source that is not this repository's idiom

    Usage: x2c-lint [--all | --rule CODE]... [--fix] [-I DIR]... FILE...
           x2c-lint --fmt-check [--fmt-diff] FILE...
           x2c-lint --rules

    Prints each finding as `FILE:LINE: KIND CODE RULE-ID: MESSAGE`, in line
    order. The language rules run unless `--all` or `--rule` selects rules;
    `--rules` prints the table of codes, families, kinds, and standard rule
    IDs. `function-reading-order` requires explicit `--rule` selection;
    `--all` does not select it. Each file is scanned for token rules and
    parsed by the compiler for declaration and member-arrow rules. The
    member files a module entry splices are linted with it, each under its
    own path and lines; a member that several entries splice is linted once.
    The compiler's diagnostics go to standard error; a unit that does not
    parse gets the token rules only and makes the exit status 1. Findings
    alone leave the exit status 0. An unreadable input reports its path on
    standard error, makes the exit status 1, and leaves other readable
    inputs available.
    `-` names an ordinary file in both lint and formatting modes.

    `--fix` rewrites each file with the proposed fixes of the selected
    rules that leave its generated C and header byte-identical, and prints
    `FILE: fixed N of M` after its findings.

    `--fmt-check` reports, for each file whose spacing formatting would
    change, `FILE: N lines to format`, and exits 1 when any would change;
    `--fmt-diff` also prints the unified difference. Neither writes; see
    `formatting.x` for what formatting changes.

    The command links the compiler's objects through `make commands`.
    `make commands-check` checks its findings on `tests/`.
*/
#include "system-macros.x"
#include "frontend.x"
#include "meta-project.x"
#include "lint.x"
#include "tokens.x"
#include "declarations.x"
#include "order.x"
#include "lifetime.x"
#include "idioms.x"
#include "comments.x"
#include "validation.x"
#include "structure.x"
#include "policy.x"
#include "fix.x"
#include "formatting.x"
#include "diff.x"
#include "args.x"
#include <stdio.h>
#include <string.h>

static void _usage(File out):
  fputs($dedent(%"
    usage: x2c-lint [--all | --rule CODE]... [--fix] [-I DIR]... FILE...
           x2c-lint --fmt-check [--fmt-diff] FILE...
           x2c-lint --rules
    function-reading-order requires --rule (excluded from --all).
    "), out)

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

/* The member files that the module block of `path` splices, spelled as the
   compiler spells them, each once. A malformed block yields none; the
   unit's parse reports it. */
static List _members(String path, String text):
  Context scan = auto Context.open_isolated_named("lint module members")
  Compiler c = Compiler.new()
  c.recovery_depth = 1
  ModuleSource module = NULL
  try module = c.module_source(path, text)
  catch %(malformed *): return NULL
  if !module: return NULL
  Array members = []
  Map seen = {(Path.resolved_absolute(path)): 1}
  foreach List marker in module.markers:
    String file = marker.caddr(), resolved = Path.resolved_absolute(file)
    if resolved in seen: continue
    seen[resolved] = 1
    members.push(file)
  return scan.export(members.list_free())

/* Lints the `files` files of one unit, its entry `unit[0]` and members.
   Returns 0 when the unit does not parse. */
static int _lint_unit(Lint *unit, int files, Frontend frontend,
                      Map order_seen):
  for (int at = 0; at < files; at++):
    unit[at].token_rules()
    unit[at].idiom_rules()
  int parsed = _parse(unit, files, frontend, order_seen)
  for (int at = 0; at < files; at++):
    if !parsed: unit[at].comment_rules(NULL, NULL, NULL)
    unit[at].structure_rules()
    unit[at].policy_rules()
  return parsed

/* Parses the unit of `unit[0]` and runs the rules that read its parse over
   each of its `files` files. Returns 0 and prints the compiler's
   diagnostics when the unit does not parse. */
static int _parse(Lint *unit, int files, Frontend frontend, Map order_seen):
  ParsedUnit parsed
  if !frontend.open_reporting(unit[0].path, parsed): return 0
  Compiler c = parsed.compiler
  List ast = parsed.ast, rows = c.definition_rows(ast)
  for (int at = 0; at < files; at++):
    Lint l = unit[at]
    l.comment_rules(c, ast, rows)
    l.declaration_rules(c, ast, rows)
    l.lifetime_rules(c, ast)
    l.member_arrows(c, ast)
    l.validation_rules(c, ast)
  lint_order_rules(unit, files, c, ast, rows, order_seen)
  for (int at = 0; at < files; at++):
    Lint l = unit[at]
    foreach List finding in l.findings: finding.promote()
    foreach List edit in l.edits: edit.promote()
    foreach List function in l.functions: function.promote()
    foreach List function in l.unused: function.promote()
  parsed.close()
  return 1

/* The translate command that proves fixes, without its output directory and
   input, or NULL when the matching compiler is unavailable. */
static Array _translate(CliRequest request):
  String x2c = Compiler.driver_executable()
  if !x2c: return NULL
  Array translate = [x2c, "translate", "--no-deps", "-q", "--plain"]
  foreach String dir in request.include_dirs:
    translate.push("-I")
    translate.push(dir)
  return translate

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
    _usage(Stderr)
    return 2
  if options["rules"]:
    Rule.print_table()
    return 0
  if options["help"]:
    _usage(Stdout)
    return 0
  Map selected = {}
  foreach String code in options["rule"].list():
    if !Rule.find(code):
      fprintf(stderr, "x2c-lint: unknown rule '%s'\n", code)
      return 2
    selected[code] = 1
  Array inputs = options["inputs"].list()
  if !inputs.len():
    _usage(Stderr)
    return 2
  if options["fmt-check"] || options["fmt-diff"]:
    return _format_check(inputs, options["fmt-diff"].int())
  if options["all"]:
    Rule.select_family(selected, <language>)
    Rule.select_family(selected, <style>)
  if !selected.len(): Rule.select_family(selected, <language>)
  int fix = options["fix"].int()
  CliRequest request = xcalloc(1, sizeof(struct CliRequest))
  request.command = <translate>
  request.include_dirs = options["I"]
  Frontend frontend = Frontend.new(request)
  frontend.preprocessor_errors = _preprocessor_errors
  try frontend.prepare_meta(inputs)
  catch %((!or not-found io-fail) *detail):
    _input_error(detail)
    return 1
  Array translate = fix ? _translate(request) : NULL
  if fix && !translate:
    fputs("x2c-lint: the matching x2c compiler is unavailable\n", stderr)
    return 1
  Path work = fix ? Path.temp_dir() : NULL
  int status = 0, count = 0
  Map order_seen = "function-reading-order" in selected ? {} : NULL
  Map owned = {}
  Lint *lints = NULL
  foreach Path file in inputs:
    String source
    if !_read(file, source):
      status = 1
      continue
    List members = _members(file, source)
    lints = xrealloc(lints, (count + members.len() + 1) * sizeof(Lint))
    Lint *unit = lints + count
    int files = 0
    unit[files++] = Lint.new(file, source, selected)
    // A member that several entries splice belongs to the first.
    foreach String member in members:
      String text, resolved = Path.resolved_absolute(member)
      if resolved in owned: continue
      owned[resolved] = 1
      if !_read(member, text):
        status = 1
        continue
      unit[files] = Lint.new(member, text, selected)
      unit[files++].entry = file
    if !_lint_unit(unit, files, frontend, order_seen): status = 1
    count += files
  lint_corpus_rules(lints, count)
  lint_unused_rules(lints, count)
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
