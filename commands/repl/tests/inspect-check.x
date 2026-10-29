/*  inspect-check.x -- native playground display and discovery

    Copyright (c) 2026 Gary William Flake.
*/
#include "repl-inspect.x"
#include "meta-group/meta-group.x"
#include "utils.x"
#include <stdio.h>

static int failures;

List ReplSession.resolve(ReplSession session, String text) {
  Compiler c = session.compiler;
  struct Compiler saved = *c;
  SymTxn transaction = c.begin_semantic_transaction();
  List value = NULL;
  try {
    c.tokenize(text);
    value = c.parse_expression();
  }
  catch %(malformed *): {}
  *c = saved;
  transaction.rollback();
  return value;
}

static void _check(int condition, String message) {
  if (condition) return;
  fprintf(stderr, "%s\n", message);
  failures++;
}

static List _definition(Compiler c, String text) {
  c.tokenize(text);
  return c.parse_submission(text.len());
}

static List _prepare(Compiler c, int depth, int limit) {
  Type type = %("Probe");
  List value = c.sym.introduce("__inspect_value");
  List output = c.sym.introduce("__inspect_output");
  List entry = c.sym.introduce("__inspect_probe");
  List expression = %(expr $type (ident $value));
  List buffer = %(expr ("Buffer") (ident $output));
  List render = repl_render(c, type, expression, buffer, depth, limit);
  List syntax = $!Unit{
    String $entry(void) {
      Buffer $output = Buffer.new(0);
      $type $value = {7, {1, 2, 3}, NULL, 9, 5};
      @($(render))
      String result = (String) $buffer;
      $buffer.free();
      return result;
    }
  };
  return c.bind_syntax(syntax, <unit>, NULL);
}

static String _render(Compiler c, List declarations, int depth, int limit) {
  String failure = NULL;
  Map targets = c.stage_session_function(declarations,
    %!(Compiler compiler) =>
      _prepare(compiler, depth, limit), failure);
  _check(targets != NULL, failure ? failure : "native renderer did not stage");
  if (!targets) return "";
  Func function = targets["__inspect_probe"];
  return function.apply(0, NULL);
}

int main(int argc, char **argv) {
  (void) argc;
  x2c_initialize_environment(argv[0]);
  CliRequest request = CliRequest.new(<translate>);
  Frontend frontend = Frontend.new(request);
  ParsedUnit unit;
  if (!frontend.open_session(unit)) return 1;
  defer unit.close();
  Compiler c = unit.compiler;
  List record = _definition(c,
    "typedef struct Probe { int x; int values[3]; int *pointer; "
    "volatile int watch; unsigned bits:3; } Probe;");
  ReplSession session = xcalloc(1, sizeof(struct ReplSession));
  session.compiler = c;
  session.names = {};
  session.descriptions = {};
  session.names["Probe"] = %(type);
  session.describe("Probe", record, "typedef struct Probe { ... } Probe;");
  String full = _render(c, $(record), 3, 100);
  _check("Probe" in full && "x: 7" in full && "values: [ 1, 2, 3 ]" in full,
         %"record values missing: $full");
  _check("pointer: 0x0" in full && "watch: <volatile>" in full,
         %"pointer or volatile field was followed: $full");
  _check("bits: 5" in full, %"bitfield missing: $full");
  String shallow = _render(c, $(record), 1, 100);
  _check("values: ..." in shallow, %"depth was not bounded: $shallow");
  String bounded = _render(c, $(record), 3, 2);
  _check("..." in bounded && !("bits: 5" in bounded),
         %"entry budget was not bounded: $bounded");

  String source = "int metric(int distance) { return distance + 1; }";
  List function = _definition(c, source);
  session.names["metric"] = %(function);
  session.describe("metric", function, source);
  String information = session.info("metric");
  _check("distance" in information && "source: prompt:1" in information,
         %"function description lost names: $information");
  _check(source in session.source("metric"), "prompt source was not retained");
  _check("int x" in session.members("Probe"), "type fields missing");
  _check("metric" in session.symbol_text("me", 0, NULL, 0),
         "symbol prefix did not find function");
  _check(!("metric" in session.symbol_text("Pr", 0, NULL, 0)),
         "symbol prefix did not filter function");
  _check(session.source("missing_name") == NULL,
         "unknown source returned a definition");
  if (!failures) puts("native inspection checks passed");
  return failures != 0;
}
