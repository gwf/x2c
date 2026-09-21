/*  api-check.x -- direct checks of the submission contract

    Copyright (c) 2026 Gary William Flake.
*/
#include "session.x"
#include "lisp.x"
#include "scope.x"
#include <stdio.h>

static int failures;

static void _expect(
  ReplSession session, String source, Symbol status, Var value) {
  ReplResult result = session.submit(source);
  if (result.status != status ||
      (status == <value> && result.value != value)) {
    fprintf(stderr, "%s: expected %s, got %s (%s)\n",
            source, status.str(), result.status.str(), result.value.repr());
    failures++;
  }
}

static void _transaction_deletion(Compiler c) {
  List key = %("__repl_probe");
  Map original = c.sym.file_statics();
  original[key] = 1;
  Scope scratch = Scope.new();
  SymTxn transaction;
  {
    Scope.push(&scratch);
    defer Scope.pop();
    transaction = c.begin_semantic_transaction();
  }
  c.sym.file_statics().del(key);
  transaction.commit_transient();
  transaction.rollback();
  scratch.destroy();
  if (original.contains(key) ||
      (void *) original != (void *) c.sym.file_statics()) {
    fputs("transient commit lost deletion or original map identity\n", stderr);
    failures++;
  }
}

static void _exercise(ReplSession s) {
  _expect(s, "int", <incomplete>, void);
  _expect(s, "int f(int", <incomplete>, void);
  _expect(s, "int f(int x) {", <incomplete>, void);
  _expect(s, "int f(int x) { { int a = ; } }", <rejected>, void);
  _expect(s, "x;", <rejected>, void);
  _expect(s, "a;", <rejected>, void);
  _expect(s, "1 +", <incomplete>, void);
  _expect(s, "1 + ;", <rejected>, void);
  _expect(s, "unknown[0];", <rejected>, void);
  _expect(s, "int n=0;", <executed>, void);
  _expect(s, "int next(void) { n+=1; return n; }", <defined>, void);
  _expect(s, "int bad=next(), second=1/0;", <failed>, void);
  _expect(s, "n;", <value>, 1);
  _expect(s, "bad;", <rejected>, void);
  _expect(s, "second;", <rejected>, void);
  _expect(s, "int bad=9, second=10;", <executed>, void);
  _expect(s, "bad+second;", <value>, 19);
  _expect(s, "int twice(int x) { return next()+x; }", <defined>, void);
  _expect(s, "twice(3);", <value>, 5);
  _expect(s, "n;", <value>, 2);
  _expect(s, "n+=3;", <executed>, void);
  _expect(s, "n;", <value>, 5);
}

static void _retained_results(ReplSession s) {
  _expect(s, "long wide(void) { return 5000000000; }", <defined>, void);
  _expect(s, "Func capture(int x) { return %!(int y) => x+y; }",
          <defined>, void);
  _expect(s, "Func captured = capture(7);", <executed>, void);
  ReplResult closure = s.submit("captured;");
  ReplResult wide = s.submit("wide();");
  ReplResult array = s.submit("Array kept = [];");
  _expect(s, "kept.push(17);", <value>, 17);
  array = s.submit("kept;");
  ReplResult bad = s.submit("int broken = ;");
  String syntax = wide.syntax.repr(), lowered = wide.lowered.repr();
  String diagnostic = bad.diagnostics.repr();
  for (int i = 0; i < 200; i++) {
    _expect(s, "n+=1;", <executed>, void);
    _expect(s, "int incomplete(int x,", <incomplete>, void);
    _expect(s, "int invalid = ;", <rejected>, void);
  }
  _expect(s, "wide();", <value>, 5000000000L);
  if (wide.value != 5000000000L || wide.syntax.repr() != syntax ||
      wide.lowered.repr() != lowered || bad.diagnostics.repr() != diagnostic ||
      bad.source != "int broken = ;" || array.value.array()[0] != 17 ||
      s.compiler.macro_lisp.apply(closure.value, %(5)) != 12) {
    fputs("retained result changed after later submissions\n", stderr);
    failures++;
  }
}

int main(int argc, char **argv) {
  (void) argc;
  x2c_initialize_environment(argv[0]);
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <translate>;
  Frontend frontend = Frontend.new(request);
  if (!frontend.preload_macro_libraries()) return 1;
  size_t baseline = 0, growth = 0;
  size_t scopes = Scope.stats().live_scopes;
  for (int phase = 0; phase < 2; phase++) {
    for (int run = 0; run < 3; run++) {
      ParsedUnit unit;
      if (!frontend.open(String.new(argv[1]), &unit)) return 1;
      if (phase) {
        _transaction_deletion(unit.compiler);
        ReplSession session = ReplSession.new(unit.compiler);
        _exercise(session);
        _retained_results(session);
      }
      unit.close();
      ScopeStats stats = Scope.stats();
      size_t live = stats.live_allocations;
      if (stats.live_scopes != scopes) {
        fprintf(stderr, "session left allocation scopes open\n");
        failures++;
      }
      if (run) {
        if (!phase && run == 1) growth = live - baseline;
        else if (live - baseline != growth) {
          fprintf(stderr, "session teardown exceeds frontend baseline\n");
          failures++;
        }
      }
      baseline = live;
    }
  }
  if (!failures)
    printf("direct submission checks passed; teardown matches empty "
           "frontend baseline (+%zu allocations/round)\n", growth);
  return failures != 0;
}
