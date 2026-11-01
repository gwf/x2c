/*  inspect-check.x -- native playground display and discovery

    Copyright (c) 2026 Gary William Flake.
*/
#include "repl-inspect.x"
#include "repl-native.x"
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

/* Displays a Probe value through the native submission path. */
static String _render(ReplSession session, int depth, int limit) {
  List probe = session.resolve("(Probe){7, {1, 2, 3}, 0, 9, 5, {.first=11}}");
  with (session.inspect_depth = depth, session.inspect_limit = limit) {
    Map published = repl_native_execute(
      session, %(block (stmnt $probe)), 0, 1);
    return published["formatted"];
  }
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
    "volatile int watch; unsigned bits:3; "
    "union { int first; long second; } choice; } Probe;");
  ReplSession session = xcalloc(1, sizeof(struct ReplSession));
  session.compiler = c;
  session.names = {};
  session.descriptions = {};
  session.declarations = [record];
  session.names["Probe"] = %(type);
  session.describe("Probe", record, "typedef struct Probe { ... } Probe;");
  String full = _render(session, 3, 100);
  _check("Probe" in full && "x: 7" in full && "values: [ 1, 2, 3 ]" in full,
         %"record values missing: $full");
  _check("pointer: 0x0" in full && "watch: <volatile>" in full,
         %"pointer or volatile field was followed: $full");
  _check("bits: 5" in full, %"bitfield missing: $full");
  _check("members: first, second" in full,
         %"union member choices missing: $full");
  String union_limited = _render(session, 3, 10);
  _check("members: first, ..." in union_limited &&
         !("first, second" in union_limited),
         %"union choices exceeded the shared entry budget: $union_limited");
  String shallow = _render(session, 1, 100);
  _check("values: ..." in shallow, %"depth was not bounded: $shallow");
  String bounded = _render(session, 3, 2);
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
  Map metric = session.descriptions["metric"];
  metric["dependency"] = 1;
  _check(!("metric" in session.symbol_text("me", 0, NULL, 0)) &&
         "metric" in session.symbol_text("me", 0, NULL, 1),
         "dependency browsing did not follow the all filter");
  _check("distance" in session.info("metric"),
         "dependency filtering hid explicit information lookup");
  metric.del("dependency");
  metric["unavailable"] = 1;
  _check("no native provider" in session.info("metric") &&
         !("execution: native" in session.info("metric")),
         "unavailable declaration information claimed native execution");
  metric.del("unavailable");
  session.descriptions["SCALE"] = {
    "name": "SCALE", "kind": <macro>, "type": (List) NULL,
    "declaration": "#define SCALE 3"
  };
  _check("preprocessor macro" in session.info("SCALE") &&
         !("execution: native" in session.info("SCALE")),
         "macro information claimed native execution");
  _check(session.source("missing_name") == NULL,
         "unknown source returned a definition");
  String method_source = "int Probe.read(Probe value) { return value.x; }";
  List method = _definition(c, method_source);
  session.names["Probe_read"] = %(function);
  session.describe("Probe_read", method, method_source);
  _check("Probe.read" in session.info("Probe.read"),
         "authored method spelling did not resolve");
  _check(method_source in session.source("Probe.read"),
         "method source did not resolve");
  _definition(c, "typedef struct Owner { delegate Probe part; } Owner;");
  _check("via part" in session.members("Owner"),
         "delegated method was not described");
  _check("read" in repl_member_candidates(c, %("Owner")).repr(),
         "delegated method was not a completion candidate");
  _definition(c, "Probe create_probe(int x);");
  _check("create_probe" in session.members("Probe"),
         "related C constructor was not described");
  Buffer displayed = auto Buffer.new(0);
  int remaining = 3;
  repl_inspect_value(displayed, [1, [2, 3], 4], 3, &remaining);
  String limited = displayed;
  _check("..." in limited && !("4" in limited),
         "nested value entries were not bounded");
  displayed.unwrite(displayed.content.length);
  Array cycle = [];
  cycle.push(cycle);
  remaining = 100;
  repl_inspect_value(displayed, cycle, 3, &remaining);
  String cyclic = displayed;
  _check("..." in cyclic, "cyclic collection did not reach depth limit");
  if (!failures) puts("native inspection checks passed");
  return failures != 0;
}
