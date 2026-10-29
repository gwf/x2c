/*  native-check.x -- persistent native playground behavior

    Copyright (c) 2026 Gary William Flake.
*/
#include "repl-session.x"
#include "repl-inspect.x"
#include "utils.x"
#include <stdio.h>

static int failures, cleanup_log[32], cleanup_count;

static void _check(int condition, String message) {
  if (condition) return;
  fprintf(stderr, "%s\n", message);
  failures++;
}

static ReplResult _expect(
  ReplSession session, String source, Symbol status, String displayed) {
  ReplResult result = session.submit(source);
  int correct = result.status == status &&
    (!displayed || result.formatted == displayed);
  if (correct) return result;
  fprintf(stderr, "submission: %s\nexpected: %s %s\nactual: %s %s\n",
    source, status.str(), displayed ? displayed : "", result.status.str(),
    result.formatted ? result.formatted : "");
  if (result.message) fprintf(stderr, "reason: %s\n", result.message);
  if (result.cause) fprintf(stderr, "cause: %s\n", result.cause.repr());
  foreach (Var entry, result.diagnostics)
    session.compiler.print_diagnostic(entry);
  failures++;
  return result;
}

static void _value(ReplSession session, String source, String displayed) =>
  _expect(session, source, <value>, displayed);

static void _shared(ReplSession session) {
  _expect(session, "int shared=10;", <executed>, NULL);
  _expect(session, "int plus(int n) { return shared+n; }", <defined>, NULL);
  _value(session, "plus(3);", "int 13");
  _expect(session, "shared=20;", <executed>, NULL);
  _value(session, "plus(3);", "int 23");
  _expect(session, "int *shared_pointer=&shared;", <executed>, NULL);
  _expect(session, "*shared_pointer=30;", <executed>, NULL);
  _value(session, "plus(3);", "int 33");
  _expect(session, "int other=40;", <executed>, NULL);
  _expect(session, "int read_shared(void) { return shared; }", <defined>, NULL);
  _expect(session, "int read_other(void) { return other; }", <defined>, NULL);
  _expect(session, "int (*saved_read)(void)=read_shared;", <executed>, NULL);
  _value(session, "read_other();", "int 40");
  _value(session, "saved_read();", "int 30");
  _expect(session, "other=50;", <executed>, NULL);
  _value(session, "read_other();", "int 50");
  _value(session, "saved_read();", "int 30");
  _expect(session, "int recurse(int n) { return n ? n+recurse(n-1) : 0; }",
          <defined>, NULL);
  _value(session, "recurse(4);", "int 10");
  _value(session, "shared;", "int 30");
  _value(session, "shared;", "int 30");
}

static void _objects(ReplSession session) {
  _expect(session, "typedef struct Point { int x; int y; } Point;",
          <defined>, NULL);
  _expect(session, "Point point={1,2};", <executed>, NULL);
  _value(session, "point;", "Point { x: 1, y: 2 }");
  _expect(session, "int *field=&point.x;", <executed>, NULL);
  _expect(session, "Point replacement={8,9};", <executed>, NULL);
  _expect(session, "point=replacement;", <executed>, NULL);
  _value(session, "*field;", "int 8");
  _expect(session, "Point make_point(int n) { Point p={n,n+1}; return p; }",
          <defined>, NULL);
  _expect(session, "Point returned=make_point(20);", <executed>, NULL);
  _value(session, "returned;", "Point { x: 20, y: 21 }");
  _value(session, "make_point(3);", "Point { x: 3, y: 4 }");
  _expect(session, "void shift(Point *p,int dx) { p->x+=dx; }", <defined>, NULL);
  _expect(session, "shift(&returned,2);", <executed>, NULL);
  _value(session, "returned.x;", "int 22");
  _expect(session, "const int fixed[3]={4,5,6};", <executed>, NULL);
  _value(session, "fixed[1];", "const int 5");
  _expect(session, "fixed[0]=9;", <rejected>, NULL);
  _value(session, "fixed[0];", "const int 4");
  _expect(session, "int inspections=0;", <executed>, NULL);
  _expect(session, "Point counted(void) { inspections++; return make_point(5); }",
          <defined>, NULL);
  _value(session, "counted();", "Point { x: 5, y: 6 }");
  _value(session, "inspections;", "int 1");
  _check(session.info("inspections++") != NULL, "expression type was unavailable");
  _value(session, "inspections;", "int 1");
  ReplResult inspected = session.inspect_expression("inspections++", 3, 100);
  _check(inspected.status == <value> && inspected.formatted == "int 1",
         "explicit inspection did not capture one postfix result");
  _value(session, "inspections;", "int 2");
  _expect(session, "int selectors=0;", <executed>, NULL);
  _expect(session, "int matrix[2][2]={{1,2},{3,4}};", <executed>, NULL);
  ReplResult row = _expect(session, "matrix[selectors++];", <value>, NULL);
  _check("[ 1, 2 ]" in row.formatted,
         "native array selection did not retain one selected row");
  _value(session, "selectors;", "int 1");
  _expect(session, "enum Choice { RED=3, BLUE=4 };", <defined>, NULL);
  _value(session, "RED==3 && BLUE==4;", "int 1");
}

static void _callbacks(ReplSession session) {
  _expect(session, "int callback_bias=2;", <executed>, NULL);
  _expect(session,
    "int compare_ints(const void *left,const void *right) { "
    "return *(const int *)left-*(const int *)right; }", <defined>, NULL);
  _expect(session, "int numbers[4]={4,1,3,2};", <executed>, NULL);
  _expect(session, "qsort(numbers,4,sizeof(numbers[0]),compare_ints);",
          <executed>, NULL);
  _value(session, "numbers[0]*1000+numbers[1]*100+numbers[2]*10+numbers[3];",
         "int 1234");
  _expect(session,
    "int callback(int n,void *data) { return n+*(int *)data+callback_bias; }",
    <defined>, NULL);
  _expect(session,
    "int invoke(int (*call)(int,void *),void *data) { return call(4,data); }",
    <defined>, NULL);
  _expect(session, "int userdata=7;", <executed>, NULL);
  _value(session, "invoke(callback,&userdata);", "int 13");
  _expect(session, "callback_bias=3;", <executed>, NULL);
  _value(session, "invoke(callback,&userdata);", "int 14");
  _expect(session, "int (*saved_callback)(int,void *)=callback;", <executed>, NULL);
  _value(session, "saved_callback(5,&userdata);", "int 15");
}

static void _collections(ReplSession session) {
  _expect(session, "Array values=[1,2];", <executed>, NULL);
  _expect(session,
    "int append(int n) { values.push(n); return values.len(); }",
    <defined>, NULL);
  _value(session, "append(3);", "int 3");
  _value(session, "values;", "Array [ 1, 2, 3 ]");
  _expect(session, "values[0]+=4;", <executed>, NULL);
  _value(session, "values[0].int();", "int 5");
  _expect(session, "Map record={\"value\": 2};", <executed>, NULL);
  _expect(session, "record[\"value\"]+=3;", <executed>, NULL);
  _value(session, "record[\"value\"].int();", "int 5");
  _expect(session, "Func add=%!(int x) => x+5;", <executed>, NULL);
  _value(session, "add(3).int();", "int 8");
  _expect(session,
    "Func factory(int n) { return %!(int x) using &n => (n+=x); }",
    <defined>, NULL);
  _expect(session, "Func counter=factory(10);", <executed>, NULL);
  _value(session, "counter(2).int();", "int 12");
  _value(session, "counter(3).int();", "int 15");
  _expect(session, "String text=\"hello\";", <executed>, NULL);
  _value(session, "text;", "String \"hello\"");
  _expect(session, "List syntax=%(one 2);", <executed>, NULL);
  _value(session, "syntax;", "List (one 2)");
}

static void _rollback(ReplSession session) {
  _expect(session, "int effects=0;", <executed>, NULL);
  _expect(session,
    "int fail(void) { effects++; raise %(probe); return 0; }",
    <defined>, NULL);
  _expect(session, "int unpublished=fail();", <failed>, NULL);
  _check(!session.inspect("unpublished"), "failed initializer published a name");
  _value(session, "effects;", "int 1");
  _expect(session, "int first=++effects, second=fail();", <failed>, NULL);
  _check(!session.inspect("first") && !session.inspect("second"),
         "failed compound declaration published partial names");
  _value(session, "effects;", "int 3");
  _expect(session, "int unfinished(int n) {", <incomplete>, NULL);
  _check(!session.inspect("unfinished"), "incomplete function was published");
  _expect(session, "int broken=;", <rejected>, NULL);
  _check(!session.inspect("broken"), "rejected declaration was published");
  _expect(session, "int broken=7;", <executed>, NULL);
  _value(session, "broken;", "int 7");
  _expect(session, "typedef int Stable;", <defined>, NULL);
  _expect(session, "typedef long Stable;", <rejected>, NULL);
  _expect(session, "Stable kept=8;", <executed>, NULL);
  _value(session, "(int)kept;", "int 8");
}

static void _record_cleanup(int value) {
  if (cleanup_count < 32) cleanup_log[cleanup_count++] = value;
}

static List _install(Compiler c, String source) {
  c.tokenize(source);
  return c.parse_submission(source.len());
}

static void _cleanup(ReplSession session) {
  _install(session.compiler, "void record_cleanup(int value);");
  session.addresses["record_cleanup"] = (void *) _record_cleanup;
  _expect(session, "int late=1;", <executed>, NULL);
  _expect(session, "defer record_cleanup(late);", <executed>, NULL);
  _expect(session, "late=2;", <executed>, NULL);
  _check(cleanup_count == 0, "top-level defer ran before session retirement");
  _expect(session, "{ defer record_cleanup(3); }", <executed>, NULL);
  _check(cleanup_count == 1 && cleanup_log[0] == 3,
         "explicit block did not clean at block exit");

  _expect(session, "typedef int Managed;", <defined>, NULL);
  _install(session.compiler, "void Managed.cleanup(Managed value);");
  session.addresses["Managed_cleanup"] = (void *) _record_cleanup;
  session.declarations.push(_install(session.compiler, "protocol Cleanup(Managed);"));
  _expect(session, "auto Managed current=4;", <executed>, NULL);
  _expect(session, "current=5;", <executed>, NULL);
  _expect(session, "Managed acquired=auto (Managed)6;", <executed>, NULL);
  _expect(session, "acquired=7;", <executed>, NULL);
  _check(cleanup_count == 1, "managed top-level cleanup ran at submission exit");
}

int main(int argc, char **argv) {
  x2c_initialize_environment(argv[0]);
  CliRequest request = CliRequest.new(<translate>);
  Frontend frontend = Frontend.new(request);
  ParsedUnit unit;
  if (!frontend.open_session(unit)) return 1;
  ReplSession session = ReplSession.new(unit.compiler);
  session.frontend = frontend;
  String selected = argc > 1 ? String.new(argv[1]) : NULL;
  if (!selected || selected == "shared") _shared(session);
  if (!selected || selected == "objects") _objects(session);
  if (!selected || selected == "callbacks") _callbacks(session);
  if (!selected || selected == "collections") _collections(session);
  if (!selected || selected == "rollback") _rollback(session);
  if (!selected || selected == "cleanup") _cleanup(session);
  session.close();
  if (!selected || selected == "cleanup")
    _check(cleanup_count == 4 && cleanup_log[1] == 6 &&
           cleanup_log[2] == 5 && cleanup_log[3] == 2,
           "session cleanup did not preserve reverse order and capture meaning");
  unit.close();
  if (!failures) puts("native submission checks passed");
  return failures != 0;
}
