/*  api-check.x -- direct checks of the submission contract

    Copyright (c) 2026 Gary William Flake.
*/
#include "repl-session.x"
#include "lisp.x"
#include "scope.x"
#include "macros.x"
#include <stdio.h>

static int failures;

static int _has_completion(List candidates, String spelling) {
  foreach (Var row, candidates)
    match (row) case %(? $spelling): return 1;
  return 0;
}

static int _has_completion_kind(
  List candidates, Symbol kind, String spelling) {
  foreach (Var row, candidates)
    match (row) case %($kind $spelling): return 1;
  return 0;
}

static void _symbols(ReplSession session, List expected) {
  List actual = session.symbols();
  if (actual.repr() != expected.repr()) {
    fprintf(stderr, "expected symbols %s, got %s\n",
            expected.repr(), actual.repr());
    failures++;
  }
}

static void _expect(
  ReplSession session, String source, Symbol status, Var value) {
  ReplResult result = session.submit(source);
  if (result.status != status ||
      (status == <value> && result.value != value)) {
    fprintf(stderr, "%s: expected %s, got %s (%s)\n",
            source, status.str(), result.status.str(), result.value.repr());
    if (result.message) fprintf(stderr, "%s\n", result.message);
    if (result.diagnostics) fprintf(stderr, "%s\n", result.diagnostics.repr());
    failures++;
  }
}

static void _completion(
  ReplSession session, String source, String present, String absent) {
  ReplCompletion result = session.complete(source, source.len());
  if ((present && !_has_completion(result.candidates, present)) ||
      (absent && _has_completion(result.candidates, absent))) {
    fprintf(stderr, "completion for %s: %s\n",
            source, result.candidates.repr());
    failures++;
  }
}

static void _completion_kind(
  ReplSession session, String source, Symbol kind, String spelling) {
  ReplCompletion result = session.complete(source, source.len());
  if (!_has_completion_kind(result.candidates, kind, spelling)) {
    fprintf(stderr, "completion kind for %s: %s\n",
            source, result.candidates.repr());
    failures++;
  }
}

static void _completion_range(ReplSession session) {
  ReplCompletion result = session.complete("pri trailing", 3);
  if (result.start != 0 || result.end != 3 ||
      !_has_completion(result.candidates, "print")) {
    fprintf(stderr, "completion range: %zu:%zu %s\n",
            result.start, result.end, result.candidates.repr());
    failures++;
  }
}

static void _transaction_deletion(Compiler c) {
  SymTxn inactive = {0};
  inactive.commit();
  inactive.rollback();
  SymTxn.commit(NULL);
  SymTxn.rollback(NULL);
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
  if (transaction.active || original.contains(key) ||
      (void *) original != (void *) c.sym.file_statics()) {
    fputs("transient commit lost deletion or original map identity\n", stderr);
    failures++;
  }
}

/* A macro value application that placed support code and whose carrier's
   effects ran, and whose skeleton then fails to bind, leaves no early
   declaration, adapter, generated name, or exception flag behind. */
static void _carrier_rollback(Compiler c) {
  List key = %(repl-rollback-probe);
  Atom token = Atom.intern("?__rollback_probe");
  Atom placed = Atom.intern("?__rollback_cleanup");
  List carrier = %(code-value "source"
    (seq (stmnt (expr () (ident $token))) $placed)
    ((new-name $token "rollback") (cleanup $placed (seq))));
  List support = %(declare (int) (bindings (bind ("rollback_probe") ())));
  int early = c.pending.area(<support>).len(), exception = c.needs_exception;
  String counters = c.names.counters.repr();
  int failed = 0;
  DiagnosticsHold hold = c.diagnostics.hold();
  $let(c.recovery_depth, c.recovery_depth + 1)
  $let(c.macro_application, c.macro_application + 1) {
    SymTxn transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    try {
      Var value;
      int retained;
      c.place(%(unit-support $key), support);
      c.take_code_value(carrier, value, retained);
      c.bind_syntax(value, <statement>, NULL);
      transaction.commit();
    }
    catch %(malformed *): failed = 1;
  }
  c.diagnostics.release(hold, 0);
  if (!failed || c.pending.area(<support>).len() != early ||
      c.names.adapters.contains(key) || c.needs_exception != exception ||
      c.names.counters.repr() != counters) {
    fputs("carrier effects leaked past a failed application\n", stderr);
    failures++;
  }
}

static void _exercise(ReplSession s) {
  _symbols(s, %());
  _completion(s, "Str", "String", NULL);
  _completion(s, "pri", "print", NULL);
  _completion(s, "\"x\".le", "len", NULL);
  _completion(s, "\"x\".for", "format", NULL);
  _completion_kind(s, "", <keyword>, "int");
  _completion_kind(s, "int f(void) { ret", <keyword>, "return");
  _completion_kind(s, "if (1) {} el", <keyword>, "else");
  _completion_kind(s, "try {} ca", <keyword>, "catch");
  _completion_kind(s, "try {} fi", <keyword>, "finally");
  _completion_kind(s, "try {} catch: {} fi", <keyword>, "finally");
  _completion(s, "return Str", NULL, "String");
  _completion(s, "int f(pri", NULL, "print");
  _completion(s, "int f(Str", "String", NULL);
  _completion(s, "int f(const pri", NULL, "print");
  _completion(s, "int f(const Str", "String", NULL);
  _completion(s, "if (1) { Str", "String", NULL);
  _completion(s, "int f(void) { int local=0; loc", "local", NULL);
  _completion_range(s);
  _expect(s, "int", <incomplete>, void);
  _expect(s, "int f(int", <incomplete>, void);
  _expect(s, "int f(int x) {", <incomplete>, void);
  _expect(s, "int f(int x) { { int a = ; } }", <rejected>, void);
  _expect(s, "x;", <rejected>, void);
  _expect(s, "a;", <rejected>, void);
  _expect(s, "1 +", <incomplete>, void);
  _expect(s, "1 + ;", <rejected>, void);
  _expect(s, "unknown[0];", <rejected>, void);
  _symbols(s, %());
  _expect(s, "int n=0;", <executed>, void);
  _expect(s, "int next(void) { n+=1; return n; }", <defined>, void);
  _completion(s, "ne", "next", NULL);
  _expect(s, "int bad=next(), second=1/0;", <failed>, void);
  _completion(s, "ba", NULL, "bad");
  _symbols(s, %((value "n") (function "next")));
  if (s.inspect("bad") || s.inspect("second") || s.inspect("f") ||
      s.inspect("a") || s.inspect("__repl_eval") || s.inspect("String") ||
      s.inspect("n").repr() != %(value).repr()) {
    fputs("inspection published a failed binding or wrong kind\n", stderr);
    failures++;
  }
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
  _expect(s, "int rejected(void) { return sizeof(struct Incomplete); }",
          <rejected>, void);
  _expect(s, "int twice(int x) { return 99; }", <rejected>, void);
  _symbols(s, %((value "bad") (value "n") (function "next")
               (value "second") (function "twice")));
  if (s.inspect("rejected")) {
    fputs("inspection published a function that failed compilation\n", stderr);
    failures++;
  }
}

static int _inspection_native(int n) => n;

static void _retained_results(ReplSession s) {
  ReplResult definition = s.submit("long wide(void) { return 5000000000; }");
  List entry = s.inspect("wide"), symbols = s.symbols();
  String inspected = entry.repr(), published = symbols.repr();
  int matched = 0;
  match (entry) {
    case %(function (typed ?syntax) (execution native)):
      matched = definition.status == <defined> &&
                syntax.repr() == definition.syntax.repr() &&
                !definition.lowered;
  }
  if (!matched) {
    fputs("named inspection lost typed AST or native execution\n", stderr);
    failures++;
  }
  $lisp.bind(s.compiler.macro_lisp, "inspection_native", _inspection_native);
  _expect(s, "meta int inspection_native(int n);", <defined>, void);
  if (s.function_info("wide") !=
      "long wide(void);\nsource: prompt\nexecution: native" ||
      s.function_info("n") || s.function_info("missing") ||
      !_has_completion(s.complete_functions("wi", 0), "wide") ||
      !_has_completion(s.complete_functions("inspection", 1),
                       "inspection_native") ||
      _has_completion(s.complete_functions("inspection", 0),
                      "inspection_native")) {
    fputs("function inspection or completion changed its contract\n", stderr);
    failures++;
  }
  _expect(s, "Func capture(int x) { return %!(int y) => x+y; }",
          <defined>, void);
  _expect(s, "Func captured = capture(7);", <executed>, void);
  ReplResult closure = s.submit("captured;");
  _expect(s, "captured(5);", <value>, 12);
  _expect(s, "capture(19)(4);", <value>, 23);
  _expect(s, "int apply_capture(Func fn, int x) { return fn(x); }",
          <defined>, void);
  _expect(s, "apply_capture(captured, 9);", <value>, 16);
  _expect(s, "captured();", <failed>, void);
  _expect(s, "captured(6);", <value>, 13);
  _expect(s, "Func no_args = %!(void) => 37;", <executed>, void);
  _expect(s, "no_args();", <value>, 37);
  ReplResult wide = s.submit("wide();");
  ReplResult array = s.submit("Array kept = [];");
  _completion(s, "kept.pu", "push", "free");
  _completion(s, "if (1) { String local = \"x\"; local.le", "len", NULL);
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
  _expect(s, "captured(8);", <value>, 15);
  _expect(s, "no_args();", <value>, 37);
  _expect(s, "wide();", <value>, 5000000000L);
  if (wide.value != 5000000000L || wide.syntax.repr() != syntax ||
      wide.lowered.repr() != lowered || bad.diagnostics.repr() != diagnostic ||
      bad.source != "int broken = ;" || array.value.array()[0] != 17 ||
      s.evaluator.apply(closure.value, %(5)) != 12 ||
      s.inspect("wide").repr() != inspected || entry.repr() != inspected ||
      symbols.repr() != published || s.inspect("incomplete") ||
      s.inspect("invalid") || s.inspect("broken")) {
    fputs("retained result changed after later submissions\n", stderr);
    failures++;
  }
}

static void _meta_records(ReplSession session) {
  _expect(session, "struct ReplPoint { int x; };", <defined>, void);
  _expect(session,
    "int record_alias(void) { struct ReplPoint a={1}, b={2}; "
    "int *p=&a.x; a=b; return *p*10+a.x; }", <defined>, void);
  _expect(session, "record_alias();", <value>, 22);
  _expect(session, "struct ReplPoint kept_point={3};", <executed>, void);
  _expect(session, "kept_point.x;", <value>, 3);
  _expect(session, "kept_point.x=8;", <executed>, void);
  _expect(session, "record_alias();", <value>, 22);
  _expect(session, "kept_point.x;", <value>, 8);
  _expect(session, "int *kept_field = &kept_point.x;", <executed>, void);
  _expect(session, "struct ReplPoint replacement = {12};", <executed>, void);
  _expect(session, "kept_point = replacement;", <executed>, void);
  _expect(session, "*kept_field;", <value>, 12);
  _expect(session, "kept_point.x;", <value>, 12);
  _expect(session,
    "int inline_record(void) { struct { int x; } a={6}; return a.x; }",
    <defined>, void);
  _expect(session, "inline_record();", <value>, 6);
  _expect(session, "typedef int ReplCount;", <defined>, void);
  _expect(session, "ReplCount count=7;", <executed>, void);
  _expect(session, "count;", <value>, 7);
  _expect(session, "struct Unfinished { int x;", <incomplete>, void);
  if (session.inspect("Unfinished")) {
    fputs("incomplete meta type was published\n", stderr);
    failures++;
  }
  _expect(session, "struct Unfinished { int y; };", <defined>, void);
  _expect(session,
    "int recovered_type(void) { struct Unfinished p={9}; return p.y; }",
    <defined>, void);
  _expect(session, "recovered_type();", <value>, 9);
}

static void _interpreter_ownership(ReplSession s) {
  _expect(s,
    "int trouble(void) { struct { int x; } p={1}; "
    "return sizeof(struct Missing); }", <rejected>, void);
  _expect(s,
    "int trouble(void) { struct { int x; int y; } p={2,3}; return p.y; }",
    <defined>, void);
  _expect(s, "trouble();", <value>, 3);
  Var value;
  if (s.compiler.macro_lisp.try_get("C.globals", value) ||
      s.compiler.macro_lisp.try_get("wide", value)) {
    fputs("interpreter definitions leaked into compiler Lisp\n", stderr);
    failures++;
  }
  s.compiler.macro_lisp.set_global("__isolation", 41);
  s.evaluator.set_global("__isolation", 7);
  if (s.compiler.macro_lisp.eval_string("__isolation") != 41 ||
      s.evaluator.eval_string("__isolation") != 7) {
    fputs("interpreter and compiler globals are shared\n", stderr);
    failures++;
  }
  _expect(s,
    "struct ReplPoint make_point(int n) { "
    "struct ReplPoint p={n}; return p; }", <defined>, void);
  _expect(s, "struct ReplPoint returned=make_point(23);", <executed>, void);
  _expect(s,
    "int storage_failure(void) { struct ReplPoint p={9}; "
    "int *q=&p.x; raise %(probe (value ${*q})); }", <defined>, void);
  for (int i = 0; i < 20; i++) {
    _expect(s, "storage_failure();", <failed>, void);
    _expect(s, "make_point(99).x;", <value>, 99);
    if (s.evaluator.automatic_storage() != s.evaluator.storage() ||
        s.evaluator.result_storage() != s.evaluator.storage()) {
      fputs("failed source activation left storage owners active\n", stderr);
      failures++;
    }
  }
  _expect(s, "returned.x;", <value>, 23);
  _expect(s,
    "Func record_capture(void) { struct ReplPoint p={42}; "
    "Func fn=%!(int y) => p.x+y; p.x=99; return fn; }", <defined>, void);
  _expect(s, "Func captured_point=record_capture();", <executed>, void);
  for (int i = 0; i < 20; i++) {
    _expect(s, "make_point(99).x;", <value>, 99);
    _expect(s, "%(1).map(captured_point);", <value>, %(43));
  }
  _expect(s, "int cleaned=0;", <executed>, void);
  _expect(s, "int normal_cleanup(void) { defer cleaned+=1; raise %(probe); }",
          <defined>, void);
  _expect(s, "normal_cleanup();", <failed>, void);
  _expect(s, "cleaned;", <value>, 1);
  s.evaluator.call_budget(100);
  _expect(s, "{ defer cleaned+=1; while(1) {} }", <failed>, void);
  s.evaluator.call_budget(1000000);
  _expect(s, "cleaned;", <value>, 1);
  _expect(s, "normal_cleanup();", <failed>, void);
  _expect(s, "cleaned;", <value>, 2);
  s.evaluator.eval_string(
    "(defun budget_loop (n) (if (= n 0) 7 "
    "(C.unwind (lambda () (budget_loop (- n 1))) (lambda () 0) nil)))");
  s.evaluator.call_budget(20);
  int exhausted = 0;
  try s.evaluator.eval_string("(budget_loop 40)");
  catch %(call-stack (operation "apply") (reason "steps")): exhausted = 1;
  s.evaluator.call_budget(1000000);
  if (!exhausted) {
    fputs("nested callback renewed the evaluation budget\n", stderr);
    failures++;
  }
  _expect(s, "returned.x;", <value>, 23);
}

static void _delegate_completion(ReplSession session) {
  _expect(session, "typedef struct ReplPart { int value; } ReplPart;",
          <defined>, void);
  _expect(session, "int ReplPart.read(ReplPart part) { return part.value; }",
          <defined>, void);
  _expect(session, "struct ReplOwner { delegate ReplPart part; };",
          <defined>, void);
  _expect(session, "struct ReplOwner owner={{7}};", <executed>, void);
  _completion(session, "owner.", "part", "read");
  _completion(session, "owner.part.", "read", NULL);
  _expect(session, "owner.read();", <value>, 7);
}

static void _completion_does_not_publish_meta(ReplSession session) {
  Compiler compiler = session.compiler;
  size_t values = compiler.meta_group.len();
  (void) session.complete("meta static int completion_value = 41;", 38);
  if (compiler.meta_group.len() != values) {
    fputs("completion published a meta declaration effect\n", stderr);
    failures++;
  }
}

static void _reference_arguments(ReplSession s) {
  _expect(s, "typedef struct RefValue { int n; } RefValue;",
          <defined>, void);
  _expect(s, "int RefValue.bump(RefValue &v) { v.n++; return v.n; }",
          <defined>, void);
  _expect(s, "int bad_ref(void) { RefValue v={4}; RefValue *p=&v; "
             "return p.bump(); }", <defined>, void);
  _expect(s, "bad_ref();", <failed>, void);
  _expect(s, "int good_ref(void) { RefValue v={4}; RefValue *p=&v; "
             "int n=(*p).bump(); return n*10+v.n; }", <defined>, void);
  _expect(s, "good_ref();", <value>, 55);
  _expect(s, "int direct_ref(void) { RefValue v={4}; "
             "int n=v.bump(); return n*10+v.n; }", <defined>, void);
  _expect(s, "direct_ref();", <value>, 55);
  _expect(s, "int ref_bump(int &v) { v++; return v; }", <defined>, void);
  _expect(s, "ref_bump(0);", <rejected>, void);
  _expect(s, "ref_bump(4);", <rejected>, void);
  _expect(s, "int ref_forward(int &v) { return ref_bump(v); }",
          <defined>, void);
  _expect(s, "int ref_value(void) { int v=4; "
             "int n=ref_forward(v); return n*10+v; }", <defined>, void);
  _expect(s, "ref_value();", <value>, 55);
  _expect(s, "int ref_maybe(int &?v) { if (!v) return 7; "
             "return ref_bump(v); }", <defined>, void);
  _expect(s, "ref_maybe(0);", <value>, 7);
  _expect(s, "int ref_present(void) { int v=4; "
             "int n=ref_maybe(v); return n*10+v; }", <defined>, void);
  _expect(s, "ref_present();", <value>, 55);
  _expect(s, "({ int local=3; local+4; });", <value>, 7);
  ReplResult statement = s.submit("({ int local=3; local++; local; });");
  if (statement.status != <rejected> ||
      statement.message != "unsupported: a statement expression") {
    fputs("statement expression refusal described a different form\n", stderr);
    failures++;
  }
  _expect(s, "1+2;", <value>, 3);
}

static void _compiled_functions(ReplSession s) {
  _expect(s, "int bias=1;", <executed>, void);
  _expect(s, "int adjust(int n) { return n+bias; }", <defined>, void);
  _expect(s, "int twice_adjust(int n) { return adjust(adjust(n)); }",
          <defined>, void);
  _expect(s, "Func saved_adjust=twice_adjust;", <executed>, void);
  _expect(s, "bias=10;", <executed>, void);
  _expect(s, "saved_adjust(2);", <value>, 22);
  _expect(s, "Func address_adjust(void) { return &adjust; }", <defined>, void);
  _expect(s, "Func group_adjust(void) { return (adjust); }", <defined>, void);
  _expect(s, "Func deref_adjust(void) { return *adjust; }", <defined>, void);
  _expect(s, "address_adjust()(2);", <value>, 12);
  _expect(s, "group_adjust()(2);", <value>, 12);
  _expect(s, "deref_adjust()(2);", <value>, 12);
  _expect(s, "int grouped_adjust(int n) { return (adjust)(n) "
             "+ (&adjust)(n) + (*(&adjust))(n); }", <defined>, void);
  _expect(s, "grouped_adjust(2);", <value>, 36);
  _expect(s, "Func choose_adjust(int flag) { "
             "return flag ? adjust : twice_adjust; }", <defined>, void);
  _expect(s, "choose_adjust(1)(2);", <value>, 12);
  _expect(s, "choose_adjust(0)(2);", <value>, 22);
  _expect(s, "int call_choice(int flag) { "
             "return (flag ? adjust : twice_adjust)(2); }", <defined>, void);
  _expect(s, "call_choice(0);", <value>, 22);
  _expect(s, "int raw_adjust(int n) { int (*fn)(int)=adjust; return fn(n); }",
          <rejected>, void);
  _expect(s, "int cast_adjust(int n) { "
             "int (*fn)(int)=(int (*)(int))adjust; return fn(n); }",
          <rejected>, void);
  _expect(s, "int *bias_address=&bias;", <executed>, void);
  _expect(s, "int mutate_bias(int &n) { n+=bias; bias++; return n; }",
          <defined>, void);
  _expect(s, "int number=2;", <executed>, void);
  _expect(s, "mutate_bias(number);", <value>, 12);
  _expect(s, "number;", <value>, 12);
  _expect(s, "*bias_address;", <value>, 11);
  _expect(s, "int same_address(int *p) { return p==&bias; }", <defined>, void);
  _expect(s, "same_address(bias_address);", <value>, 1);
  _expect(s, "int *address(void) { return &bias; }", <defined>, void);
  _expect(s, "address()==bias_address;", <value>, 1);
  _expect(s, "Func later(void) { return %!(void) => bias; }", <defined>, void);
  _expect(s, "Func read_later=later();", <executed>, void);
  _expect(s, "bias+=1;", <executed>, void);
  _expect(s, "read_later();", <value>, 12);
  _expect(s, "bias-=1;", <executed>, void);
  _expect(s, "int recurse(int n) { return n ? n+recurse(n-1) : bias; }",
          <defined>, void);
  _expect(s, "recurse(4);", <value>, 21);
  _expect(s, "Func own_value(void) { return own_value; }", <defined>, void);
  _expect(s, "Func own_saved=own_value();", <executed>, void);
  _expect(s, "own_saved()==own_saved;", <value>, 1);
  _expect(s, "Array shared_items=[];", <executed>, void);
  _completion(s, "shared_items.pu", "push", NULL);
  _expect(s, "Array append_shared(int n) { shared_items.push(n); "
             "return shared_items; }", <defined>, void);
  _expect(s, "append_shared(7)==shared_items;", <value>, 1);
  _expect(s, "shared_items[0];", <value>, 7);
  _expect(s, "shared_items.push(9);", <value>, 9);
  _expect(s, "int shared_count(void) { return shared_items.len(); }",
          <defined>, void);
  _expect(s, "shared_count();", <value>, 2);
  _expect(s, "int change_point(int n) { int old=kept_point.x; "
             "kept_point.x=n; return old; }", <defined>, void);
  _expect(s, "change_point(21);", <value>, 12);
  _expect(s, "*kept_field;", <value>, 21);
  _expect(s, "kept_point=replacement;", <executed>, void);
  _expect(s, "change_point(27);", <value>, 12);
  _expect(s, "int jumped(void) { goto end; end: return bias; }",
          <defined>, void);
  _expect(s, "jumped();", <value>, 11);
}

static void _match_binders(ReplSession s) {
  _expect(s, "List match_pair = %(point 1 2);", <executed>, void);
  _expect(s, "int match_result = 0;", <executed>, void);
  _expect(
    s, "match (match_pair) case %(point ?x ?y): match_result = 7;",
    <executed>, void);
  _expect(s, "match_result;", <value>, 7);
  _expect(
    s, "match (match_pair) case %(point ?x ?y): "
       "match_result = x.int() + y.int();", <executed>, void);
  _expect(s, "match_result;", <value>, 3);

  _expect(s, "List match_tail = %();", <executed>, void);
  _expect(
    s, "match (match_pair) case %(point *tail): match_tail = tail;",
    <executed>, void);
  _expect(s, "match_tail;", <value>, %(1 2));
  _expect(
    s, "match (match_pair) case %(point ?(int x) ?(int y)): "
       "match_result = x * 10 + y;", <executed>, void);
  _expect(s, "match_result;", <value>, 12);

  _expect(
    s, "match (match_pair) case %(point ?x ?y): { "
       "match_result = x.int(); { int x = 40; match_result += x; } "
       "match_result += x.int() + y.int(); }", <executed>, void);
  _expect(s, "match_result;", <value>, 44);
  _expect(
    s, "match (match_pair) case %(point ?x ?y): { "
       "match (%(inner 5)) case %(inner ?x): match_result = x.int(); "
       "match_result += x.int() + y.int(); }", <executed>, void);
  _expect(s, "match_result;", <value>, 8);
  _expect(s, "x;", <rejected>, void);
  _expect(s, "tail;", <rejected>, void);

  _expect(
    s, "match (match_pair) case %(point ?x ?y): { "
       "x = 9; match_result = x.int() + y.int(); }", <executed>, void);
  _expect(s, "match_result;", <value>, 11);
  _expect(
    s, "int match_bump(int &value) { value += 5; return value; }",
    <defined>, void);
  _expect(
    s, "match (match_pair) case %(point ?(int x) ?(int y)): { "
       "match_bump(x); match_result = x + y; }", <executed>, void);
  _expect(s, "match_result;", <value>, 8);

  _expect(s, "Func match_kept = %!() => 0;", <executed>, void);
  _expect(
    s, "match (match_pair) case %(point ?x ?y): "
       "match_kept = %!() => x.int() + y.int();", <executed>, void);
  _expect(s, "match_kept();", <value>, 3);

  _expect(s, "match_result = 0;", <executed>, void);
  _expect(
    s, "for (int i = 0; i < 3; i++) "
       "match (match_pair) case %(point ?x ?y): "
       "match_result += x.int() + y.int();", <executed>, void);
  _expect(s, "match_result;", <value>, 9);

  _expect(s, "int match_calls = 0;", <executed>, void);
  _expect(
    s, "List match_subject(void) { match_calls++; return match_pair; }",
    <defined>, void);
  _expect(
    s, "match (match_subject()) { "
       "case %(missing ?x ?y): match_result = 99; "
       "case %(point ?x ?y): match_result = x.int() + x.int() + "
       "y.int(); }", <executed>, void);
  _expect(s, "match_result;", <value>, 4);
  _expect(s, "match_calls;", <value>, 1);
}

static void _truth_values(ReplSession s) {
  int i = 0;
  foreach (String declaration, %(
    "String value=\"\";" "String value=%\"\";"
    "Symbol value=0;" "List value=%();" "String value=\"yes\";")) {
    String name = %"truth_case_${i}";
    String body = "if (value) hits+=1; if (!value) hits+=2; "
      "int a=value && ++hits; int b=value || ++hits; "
      "return hits*100+a*10+b+(value ? 1000 : 0);";
    _expect(s, %"int $name(void) { $declaration int hits=0; $body }",
            <defined>, void);
    _expect(s, %"$name();", <value>, i == 4 ? 1211 : 301);
    i++;
  }
}

static void _pointer_updates(ReplSession s) {
  int i = 0;
  foreach (String operation, %(
    "p++;" "++p;" "p+=1;" "p=p+1;"
    "p--;" "--p;" "p-=1;")) {
    String name = %"pointer_case_${i}";
    String body = %"int *p=data+1; $operation return *p;";
    _expect(s, %"int $name(void) { int data[3]={10,20,30}; $body }",
            <defined>, void);
    _expect(s, %"$name();", <value>, i < 4 ? 30 : 10);
    i++;
  }
  _expect(s,
    "int pointer_nested(void) { int data[3]={10,20,30}; "
    "int *p=data; int *q=(p+=1); return *q+*++p; }", <defined>, void);
  _expect(s, "pointer_nested();", <value>, 50);
  _expect(s,
    "int pointer_addressed(void) { int data[3]={10,20,30}; "
    "int *p=data; int **slot=&p; p+=1; return **slot; }", <defined>, void);
  _expect(s, "pointer_addressed();", <value>, 20);
}

static void _independent_sessions(Frontend frontend) {
  ParsedUnit first;
  if (!frontend.open_session(first)) { failures++; first.close(); return; }
  defer first.close();
  ReplSession a = ReplSession.new(first.compiler);
  defer a.close();
  String definition = "int session_add(int n) { shared+=n; return shared; }";
  _expect(a, "int shared=1;", <executed>, void);
  _expect(a, definition, <defined>, void);
  Var saved;
  a.evaluator.try_get("session_add", saved);
  Func callable = saved;
  {
    ParsedUnit second;
    if (!frontend.open_session(second)) { failures++; second.close(); return; }
    defer second.close();
    ReplSession b = ReplSession.new(second.compiler);
    defer b.close();
    _expect(b, "int shared=20;", <executed>, void);
    _expect(b, definition, <defined>, void);
    _expect(b, "session_add(2);", <value>, 22);
    FuncArg argument = FuncArg.value(2);
    if (callable.apply(1, &argument) != 3) {
      fputs("compiled sessions share captured variables\n", stderr);
      failures++;
    }
    _expect(b, "shared;", <value>, 22);
    _expect(b, "String text(void) { return \"module text\"; }",
            <defined>, void);
    _expect(b, "List syntax(void) { return %(module (cached 7)); }",
            <defined>, void);
    _expect(b, "text();", <value>, "module text");
    _expect(b, "syntax();", <value>, %(module (cached 7)));
  }
  _expect(a, "session_add(4);", <value>, 7);
  _expect(a, "String text(void) { return \"module text\"; }", <defined>, void);
  _expect(a, "List syntax(void) { return %(module (cached 7)); }",
          <defined>, void);
  _expect(a, "text();", <value>, "module text");
  _expect(a, "syntax();", <value>, %(module (cached 7)));
}

int main(int argc, char **argv) {
  (void) argc;
  x2c_initialize_environment(argv[0]);
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <translate>;
  Frontend frontend = Frontend.new(request);
  if (!frontend.preload_macro_libraries()) return 1;
  Compiler compiler = Compiler.new();
  Map definitions = compiler.shared_definitions();
  if (!frontend.preload_macro_libraries() || definitions == NULL ||
      (void *) definitions != (void *) compiler.shared_definitions()) {
    fputs("second preload discarded shared definitions\n", stderr);
    return 1;
  }
  size_t baseline = 0, growth = 0;
  size_t scopes = Scope.stats().live_scopes;
  for (int phase = 0; phase < 2; phase++) {
    for (int run = 0; run < 3; run++) {
      ParsedUnit unit;
      if (!frontend.open_session(unit)) return 1;
      if (phase) {
        _transaction_deletion(unit.compiler);
        _carrier_rollback(unit.compiler);
        ReplSession session = ReplSession.new(unit.compiler);
        _exercise(session);
        _retained_results(session);
        _meta_records(session);
        _interpreter_ownership(session);
        _reference_arguments(session);
        _compiled_functions(session);
        _match_binders(session);
        _truth_values(session);
        _pointer_updates(session);
        _delegate_completion(session);
        _completion_does_not_publish_meta(session);
        session.close();
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
          fprintf(stderr,
            "session teardown exceeds frontend baseline: %zu vs %zu\n",
            live - baseline, growth);
          failures++;
        }
      }
      baseline = live;
    }
  }
  _independent_sessions(frontend);
  if (!failures)
    printf("direct submission checks passed; teardown matches empty "
           "frontend baseline (+%zu allocations/round)\n", growth);
  return failures != 0;
}
