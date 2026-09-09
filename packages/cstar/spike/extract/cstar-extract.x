/*  cstar-extract.x -- read C* annotations out of a parsed x2c unit.

    The tool parses one annotated source file with the real compiler
    frontend, reads the compile-time Lisp global `cstar.records` that
    `cstar.xmacro` accumulated during expansion, prints the annotations in
    lexical order, and checks binding correspondence: the body each
    `$cstar.verify` recorded after erasing its markers must be the body the
    compiler actually kept, compared modulo `(at ID NODE)` wrappers.
*/

#include "frontend.x"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#pragma private

static void _preprocessor_errors(String text) {
  Stderr.printf("%s", text);
}

static int _open_input(Frontend frontend, String filename, ParsedUnit *unit) {
  int ok = frontend.start(filename, unit);
  if (ok) {
    unit->compiler.own_diagnostics();
    ok = unit.collect(frontend) && unit.parse();
  }
  if (ok) return 1;
  if (!unit->compiler.diagnostics.has_emitter())
    foreach (Var entry, unit->compiler.diagnostics())
      unit->compiler.print_diagnostic(entry);
  unit.close();
  return 0;
}

/** Removes every `(at ID NODE)` wrapper so two spellings of one body compare
    by structure alone. */
static Var _strip(Var value) {
  if (value is not <list>) return value;
  List node = value;
  match (node)
    case %(at ? ?inner): return _strip(inner);
  List result = %();
  foreach (Var child, node) result = cons(_strip(child), result);
  return result.reverse();
}

static List _strip_items(List items) {
  List result = %();
  foreach (Var item, items) result = cons(_strip(item), result);
  return result.reverse();
}

/** Returns the `(block ...)` of the function definition named `name`. */
static List _function_body(List ast, String name) {
  foreach (List node, ast)
    match (node)
      case %(function ? (bind (binding ? (!is ?spelling type string)) ?)
             (!set ?body (block *))):
        if (((String) spelling) == name) return body;
  return NULL;
}

static String _joined(List texts) {
  Array parts = %[];
  foreach (Var text, texts) parts.push(%"\"${text.str()}\"");
  return parts.join(", ");
}

static List _rows(Compiler compiler, List ast) {
  Var stored;
  if (!Lisp.try_get(compiler.macro_lisp, %"cstar.records", &stored))
    return NULL;
  Array rows = %[];
  foreach (Var entry, stored.list()) {
    List record = entry.list();
    Var line = %(), column = %();
    String text = NULL;
    match (record) {
      case %(assert ?id ?what ?file ?at ?col): {
        line = at, column = col;
        text = %"${file.str()}:${at.repr()}:${col.repr()}  assert " +
               %"[marker ${id.repr()}]  ${what.str()}";
      }
      case %(invariant ?id ?what ?file ?at ?col): {
        line = at, column = col;
        text = %"${file.str()}:${at.repr()}:${col.repr()}  invariant " +
               %"[marker ${id.repr()}]  ${what.str()}";
      }
      case %(proof ?id ?helper ?args ?file ?at ?col): {
        line = at, column = col;
        text = %"${file.str()}:${at.repr()}:${col.repr()}  proof " +
               %"[marker ${id.repr()}]  ${helper.str()}" +
               %"(${_joined(args.list())})";
      }
      case %(function ?name ?pre ?post ?file ?at ?col ?erased): {
        line = at, column = col;
        List actual = _function_body(ast, name.str());
        List recorded = _strip_items(((Var) erased).list());
        List kept = actual ? _strip_items(actual.cdr()) : NULL;
        String verdict = !actual ? %"MISSING"
                       : List.equal(recorded, kept) ? %"MATCH"
                       : %"MISMATCH";
        text = %"${file.str()}:${at.repr()}:${col.repr()}  function " +
               %"${name.str()}\n    requires  ${pre.str()}\n" +
               %"    ensures   ${post.str()}\n" +
               %"    body      ${verdict} " +
               %"(${recorded.len()} recorded, " +
               %"${kept ? kept.len() : 0} compiled)";
        if (verdict == "MISMATCH")
          text = text + %"\n    recorded  ${recorded.repr()}" +
                        %"\n    compiled  ${kept.repr()}";
      }
      default: text = %"unrecognized record ${record.repr()}";
    }
    rows.push(%($line $column $text));
  }
  rows.sort();
  return rows.list_free();
}

static void _usage(const char *program) {
  Stderr.printf("usage: %s [--root DIR] [-I DIR] FILE\n", program);
}

int main(int argc, char **argv) {
  String input = NULL, root = NULL;
  Array include_dirs = %[];
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--root") && i + 1 < argc)
      root = String.new(argv[++i]);
    else if (!strcmp(argv[i], "-I") && i + 1 < argc)
      include_dirs.push(String.new(argv[++i]));
    else if (argv[i][0] == '-' || input) {
      _usage(argv[0]);
      return 2;
    }
    else input = String.new(argv[i]);
  }
  if (!input) {
    _usage(argv[0]);
    return 2;
  }
  x2c_initialize_environment(argv[0]);
  if (!root) {
    const char *from_environment = getenv("X2C_ROOT");
    if (from_environment) root = String.new(from_environment);
  }
  if (root) x2c_set_root(root);
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <translate>;
  request.include_dirs = include_dirs.list_free();
  Frontend frontend = Frontend.new(request);
  frontend.preprocessor_errors = _preprocessor_errors;
  Context command = Context.open_isolated_named("cstar extract");
  int status = 0;
  ParsedUnit parsed;
  if (!_open_input(frontend, input, &parsed)) status = 1;
  else {
    List rows = _rows(parsed.compiler, parsed.ast);
    rows = rows ? parsed.context.export(rows).list() : NULL;
    parsed.close();
    if (!rows) Stdout.printf("no cstar.records in %s\n", input);
    foreach (List row, rows) {
      String text = row.last().str();
      Stdout.printf("%s\n", text);
      if (text.find("MISMATCH") >= 0) status = 1;
    }
  }
  command.close();
  return status;
}
