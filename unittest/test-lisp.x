/*  test-lisp.x -- unit tests for the Lisp runtime */

#include "test-support.x"

// reader - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

static Var _read1(Lisp lisp, const char *text, Symbol *status) {
  unsigned cursor = 0;
  Var out = void;
  Symbol result = Lisp.read(lisp, String.new(text), &cursor, &out);
  if (status) *status = result;
  return out;
}

/* A reader failure transfers, so the cursor, the untouched destination, and
   the reported position are all observed from the catch. */
static void _expect_read_failure(
  Lisp lisp, String source, Symbol expected, unsigned start, int line,
  int column) {
  unsigned cursor = 0;
  Var out = Var.new(<i32>, 777), untouched_out = out;
  Symbol code = 0;
  List detail = NULL;
  try Lisp.read(lisp, source, &cursor, &out);
  catch %(incomplete *cause): { code = <incomplete>; detail = cause; }
  catch %(malformed *cause): { code = <malformed>; detail = cause; }
  EXPECT_INT_EQ(code, expected);
  EXPECT_INT_EQ(cursor, start);
  EXPECT_VAR_EQ(out, untouched_out);
  if (!EXPECT_NOT_NULL(detail)) return;
  EXPECT_INT_EQ(Var.integer(detail.assoc(<line>)), line);
  EXPECT_INT_EQ(Var.integer(detail.assoc(<column>)), column);
}

static void lisp_read_integer_value(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  Var value = _read1(lisp, "42", &status);
  EXPECT_INT_EQ(status, <value>);
  EXPECT_TRUE(value is <i32>);
  EXPECT_INT_EQ(Var.integer(value), 42);
  value = _read1(lisp, "-7", &status);
  EXPECT_INT_EQ(status, <value>);
  EXPECT_INT_EQ(Var.integer(value), -7);
  value = _read1(lisp, "+9", &status);
  EXPECT_INT_EQ(Var.integer(value), 9);
  Lisp.destroy(lisp);
}

static void lisp_read_float_value(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  Var value = _read1(lisp, "3.5", &status);
  EXPECT_INT_EQ(status, <value>);
  EXPECT_TRUE(value is <f64>);
  EXPECT_TRUE(value == 3.5);
  Lisp.destroy(lisp);
}

static void lisp_read_string_value(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  Var value = _read1(lisp, "\"hi\\nthere\"", &status);
  EXPECT_INT_EQ(status, <value>);
  EXPECT_TRUE(value is <string>);
  EXPECT_STR_EQ(Var.string(value), "hi\nthere");
  Lisp.destroy(lisp);
}

static void lisp_read_identifier_representations(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  Var first = _read1(lisp, "foo-bar!", &status);
  EXPECT_INT_EQ(status, <value>);
  EXPECT_TRUE(first is <symbol>);
  EXPECT_STR_EQ(first.str(), "foo-bar!");
  Var second = _read1(lisp, "foo-bar!", &status);
  EXPECT_TRUE(first == second);
  Var long_name = _read1(lisp, "foo-bar-long", &status);
  EXPECT_TRUE(long_name.is_atom());
  EXPECT_TRUE(long_name is <lsym>);
  Var mixed_case = _read1(lisp, "Foo", &status);
  EXPECT_TRUE(mixed_case.is_atom());
  EXPECT_TRUE(mixed_case is <symbol>);
  Var escaped = _read1(lisp, "foo\\ bar", &status);
  EXPECT_STR_EQ(escaped.str(), "foo bar");
  Var comparison = _read1(lisp, "<=", &status);
  EXPECT_INT_EQ(status, <value>);
  EXPECT_STR_EQ(comparison.str(), "<=");
  Lisp.destroy(lisp);
}

static void lisp_read_case_sensitive_long_identifiers(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  Var alpha = _read1(lisp, "VeryLongIdentifierNameAlpha", &status);
  Var beta = _read1(lisp, "VeryLongIdentifierNameBeta", &status);
  Var lower = _read1(lisp, "verylongidentifiernamealpha", &status);
  EXPECT_TRUE(alpha != beta);
  EXPECT_TRUE(alpha != lower);
  EXPECT_STR_EQ(alpha.str(), "VeryLongIdentifierNameAlpha");
  Lisp.destroy(lisp);
}

static void lisp_read_compact_symbol_literal(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  Var value = _read1(lisp, "<sym>", &status);
  EXPECT_INT_EQ(status, <value>);
  EXPECT_TRUE(value is <symbol>);
  EXPECT_VAR_EQ(value, Var.new(<symbol>, <sym>));
  Lisp.destroy(lisp);
}

static void lisp_read_list_form(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  Var value = _read1(lisp, "(add 1 (sub 2 3))", &status);
  EXPECT_INT_EQ(status, <value>);
  if (!EXPECT_TRUE(value is <list>)) return;
  List form = value;
  (Symbol operation, int argument, List inner) = form;
  EXPECT_STR_EQ(operation.str(), "add");
  EXPECT_INT_EQ(argument, 1);
  EXPECT_STR_EQ(inner.car().str(), "sub");
  EXPECT_INT_EQ(form.len(), 3);
  Lisp.destroy(lisp);
}

static void lisp_read_matches_x2c_list_literal(void) {
  Lisp lisp = Lisp.new_bare();
  Var actual = Lisp.eval_string(lisp,
    "'((enum \"FileReadStatus\") (struct (* int)) (op &&) (dim (8)))");
  List expected = %((enum "FileReadStatus")
                    (struct (* int)) (op &&) (dim (8)));
  EXPECT_VAR_EQ(actual, expected.var());
  Lisp.destroy(lisp);
}

static void lisp_read_quote_sugar(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  List form = Var.list(_read1(lisp, "'x", &status));
  if (!EXPECT_NOT_NULL(form)) return;
  (Symbol quote, Symbol quoted_name) = form;
  EXPECT_STR_EQ(quote.str(), "quote");
  EXPECT_STR_EQ(quoted_name.str(), "x");
  form = Var.list(_read1(lisp, "`(a ,b ,@c)", &status));
  if (!EXPECT_NOT_NULL(form)) return;
  (Symbol quasiquote, List body) = form;
  List (unquote, splice) = body.cdr();
  EXPECT_STR_EQ(quasiquote.str(), "quasiquote");
  EXPECT_STR_EQ(unquote.car().str(), "unquote");
  EXPECT_STR_EQ(splice.car().str(), "unquote-splicing");
  Lisp.destroy(lisp);
}

static void lisp_read_comments_and_whitespace(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  Var value = _read1(lisp, "  // note\n  41", &status);
  EXPECT_INT_EQ(status, <value>);
  EXPECT_INT_EQ(Var.integer(value), 41);
  value = _read1(lisp, "/* block\n comment */ 43", &status);
  EXPECT_INT_EQ(Var.integer(value), 43);
  Lisp.destroy(lisp);
}

static void lisp_read_eof_cases(void) {
  Lisp lisp = Lisp.new_bare();
  Symbol status;
  _read1(lisp, "", &status);
  EXPECT_INT_EQ(status, <eof>);
  _read1(lisp, "   // only a comment", &status);
  EXPECT_INT_EQ(status, <eof>);
  Lisp.destroy(lisp);
}

static void lisp_read_incomplete_resets_cursor(void) {
  Lisp lisp = Lisp.new_bare();
  _expect_read_failure(lisp, "  (add 1", <incomplete>, 2, 1, 3);
  _expect_read_failure(lisp, "\"open", <incomplete>, 0, 1, 1);
  _expect_read_failure(lisp, "'", <incomplete>, 0, 1, 1);
  Lisp.destroy(lisp);
}

static void lisp_read_malformed_reports_error(void) {
  Lisp lisp = Lisp.new_bare();
  _expect_read_failure(lisp, ")", <malformed>, 0, 1, 1);
  Lisp.destroy(lisp);
}


static void lisp_read_classifies_lexical_failures(void) {
  Lisp lisp = Lisp.new_bare();
  _expect_read_failure(lisp, "  \"open", <incomplete>, 2, 1, 3);
  _expect_read_failure(lisp, "  /* open", <incomplete>, 2, 1, 3);
  _expect_read_failure(lisp, "  <open", <incomplete>, 2, 1, 3);
  _expect_read_failure(lisp, "  <\"\\x", <incomplete>, 2, 1, 3);
  _expect_read_failure(lisp, "  <\"\\u12", <incomplete>, 2, 1, 3);
  _expect_read_failure(lisp, "  '", <incomplete>, 2, 1, 3);
  _expect_read_failure(lisp, "  (a", <incomplete>, 2, 1, 3);
  _expect_read_failure(lisp, "  name\\", <incomplete>, 2, 1, 3);

  _expect_read_failure(lisp, "\n  \"\\z\"", <malformed>, 3, 2, 3);
  char raw[] = {' ', ' ', '"', 'a', '\n', 'b', '"', 0};
  _expect_read_failure(lisp, String.new(raw), <malformed>, 2, 1, 3);
  _expect_read_failure(lisp, "  1e+", <malformed>, 2, 1, 3);
  _expect_read_failure(lisp, "  <>", <malformed>, 2, 1, 3);
  _expect_read_failure(lisp, "  <a b>", <malformed>, 2, 1, 3);
  _expect_read_failure(lisp, "  ) trailing", <malformed>, 2, 1, 3);
  Lisp.destroy(lisp);
}


static void lisp_read_advances_cursor_across_forms(void) {
  Lisp lisp = Lisp.new_bare();
  unsigned cursor = 0;
  Var out = void;
  String source = "1 (a b)\n\"s\"";
  EXPECT_INT_EQ(Lisp.read(lisp, source, &cursor, &out), <value>);
  EXPECT_INT_EQ(Var.integer(out), 1);
  EXPECT_INT_EQ(Lisp.read(lisp, source, &cursor, &out), <value>);
  EXPECT_TRUE(out is <list>);
  EXPECT_INT_EQ(Lisp.read(lisp, source, &cursor, &out), <value>);
  EXPECT_TRUE(out is <string>);
  EXPECT_INT_EQ(Lisp.read(lisp, source, &cursor, &out), <eof>);
  Lisp.destroy(lisp);
}

// evaluator - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

static Var _ev(Lisp lisp, const char *text) {
  return Lisp.eval_string(lisp, String.new(text));
}

static Var _ev2(Lisp lisp, const char *left, const char *right) {
  return Lisp.eval_string(lisp, String.new(left) + String.new(right));
}

static void lisp_canonical_names_outlive_initial_context(void) {
  Context initial_context =
    Context.open_isolated_named("Lisp canonical-name initialization");
  Lisp initial = Lisp.new_bare();
  EXPECT_TRUE(_ev(initial, "'(initialized)") is <list>);
  Lisp.destroy(initial);
  initial_context.close();

  Lisp lisp = Lisp.new_bare();
  Var result = _ev(lisp, "`(1 ,@(quote (2 3)))");
  EXPECT_TRUE(result == %(1 2 3));
  Lisp.destroy(lisp);
}

static Symbol _raised_code(Lisp lisp, const char *text) {
  Symbol code = 0;
  try _ev(lisp, text);
  catch %(bad-arity *): code = <bad-arity>;
  catch %(bad-sig *): code = <bad-sig>;
  catch %(bad-types *): code = <bad-types>;
  catch %(malformed *): code = <malformed>;
  catch %(no-symbol *): code = <no-symbol>;
  catch %(not-call *): code = <not-call>;
  catch %(not-found *): code = <not-found>;
  catch %(unbound *): code = <unbound>;
  return code;
}

static Symbol _raised_code2(Lisp lisp, const char *left, const char *right) {
  String text = String.new(left) + String.new(right);
  return _raised_code(lisp, text);
}

static Var _native_add2(Var a, Var b) {
  return Var.binary(a, <+>, b);
}

static char order_log[64];

static Var _native_log(Var v) {
  strcat(order_log, v.str());
  return v;
}

$lisp.binding(test_policy, "native-sum")
static int _lisp_bound_sum(int left, int right) {
  return left + right;
}

$lisp.binding(test_policy, "native-pair")
static List _lisp_bound_pair(String label, int value) {
  return %($label $value);
}

static String _lisp_bound_greet(String name) {
  return %"hello $name";
}

static Var _lisp_bound_raise(Var value) {
  raise %(format (value $value));
  return void;
}

static void _install(Lisp lisp, const char *name, FuncAdapter fn, List sig) {
  Func func = Func.new(fn, sig);
  Lisp.set_global(lisp, String.new(name), Func.var(func));
  Var installed = void;
  EXPECT_TRUE(Lisp.try_get(lisp, String.new(name), &installed));
}

static Lisp _session(void) {
  Lisp lisp = Lisp.new_bare();
  _install(lisp, "add", _native_add2,
           %((func (("Var") ("Var"))) "Var"));
  _install(lisp, "log!", _native_log,
           %((func (("Var"))) "Var"));
  return lisp;
}

static Lisp _boot_session(void) {
  Lisp lisp = Lisp.new_bare();
  File bootstrap = File.open("../etc/init.xlisp", "r");
  if (!EXPECT_NOT_NULL(bootstrap)) return lisp;
  Lisp.eval_file(lisp, bootstrap);
  bootstrap.close();
  return lisp;
}

static int _load_lisp_layer(Lisp lisp, String path) {
  File source = File.open(path, "r");
  if (!EXPECT_NOT_NULL(source)) return 0;
  Lisp.eval_file(lisp, source);
  source.close();
  return 1;
}

static void lisp_eval_self_and_quote(void) {
  Lisp lisp = Lisp.new_bare();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "42")), 42);
  EXPECT_TRUE(_ev(lisp, "\"s\"") is <string>);
  EXPECT_TRUE(_ev(lisp, "()").is_nil());
  EXPECT_TRUE(_ev(lisp, "").is_nil());
  Var quoted = _ev(lisp, "(quote foo)");
  EXPECT_TRUE(quoted is <symbol>);
  EXPECT_STR_EQ(quoted.str(), "foo");
  EXPECT_VAR_EQ(_ev(lisp, "'foo"), quoted);
  Lisp.destroy(lisp);
}

static void lisp_eval_def_and_globals(void) {
  Lisp lisp = _session();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(def x 41)")), 41);
  Var native = void;
  EXPECT_TRUE(Lisp.try_get(lisp, "add", &native));
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(add x 1)")), 42);
  Var stored = void;
  EXPECT_TRUE(Lisp.try_get(lisp, "x", &stored));
  EXPECT_INT_EQ(Var.integer(stored), 41);
  EXPECT_FALSE(Lisp.try_get(lisp, "missing", &stored));
  Lisp.set_global(lisp, "y", Var.new(<i32>, 5));
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "y")), 5);
  EXPECT_INT_EQ(_raised_code(lisp, "unbound-name"), <unbound>);
  Lisp.destroy(lisp);
}

static void lisp_eval_cond_nil_only_false(void) {
  Lisp lisp = Lisp.new_bare();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(cond (() 1) (0 2) (3 4))")), 2);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(cond (\"\" 7))")), 7);
  EXPECT_TRUE(_ev(lisp, "(cond (() 1))").is_nil());
  EXPECT_INT_EQ(_raised_code(lisp, "(cond)"), <bad-arity>);
  EXPECT_INT_EQ(_raised_code(lisp, "(cond 5)"), <bad-types>);
  EXPECT_INT_EQ(_raised_code(lisp, "(cond (1))"), <bad-arity>);
  Lisp.destroy(lisp);
}

static void lisp_eval_lambda_application(void) {
  Lisp lisp = _session();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "((lambda (x) (add x 1)) 4)")), 5);
  EXPECT_INT_EQ(_raised_code(lisp, "((lambda (x) x))"), <bad-arity>);
  EXPECT_INT_EQ(_raised_code(lisp, "((lambda (x) x) 1 2)"), <bad-arity>);
  EXPECT_INT_EQ(_raised_code(lisp, "(lambda (x))"), <bad-sig>);
  EXPECT_INT_EQ(_raised_code(lisp, "(1 2)"), <not-call>);
  Lisp.destroy(lisp);
}

static void lisp_apply_uses_evaluated_values(void) {
  Lisp lisp = _boot_session();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(apply + '(10 20 12))")), 42);
  EXPECT_INT_EQ(Var.integer(_ev(lisp,
    "(apply (lambda (a b) (+ a b)) '(19 23))")), 42);
  EXPECT_INT_EQ(_raised_code(lisp, "(apply + 7)"), <bad-types>);
  EXPECT_INT_EQ(_raised_code(lisp, "(apply quote '(x))"), <not-call>);

  Var plus = void;
  EXPECT_TRUE(Lisp.try_get(lisp, "+", &plus));
  EXPECT_INT_EQ(Var.integer(Lisp.apply(lisp, plus, %(20 22))), 42);
  Lisp.destroy(lisp);
}

static void lisp_eval_rest_parameters(void) {
  Lisp lisp = Lisp.new_bare();
  EXPECT_VAR_EQ(_ev(lisp, "((lambda (a . r) r) 1 2 3)"),
                _ev(lisp, "(quote (2 3))"));
  EXPECT_TRUE(_ev(lisp, "((lambda (a . r) r) 1)").is_nil());
  EXPECT_INT_EQ(_raised_code(lisp, "((lambda (a .) a) 1)"), <bad-sig>);
  Lisp.destroy(lisp);
}

static void lisp_eval_capture_semantics(void) {
  Lisp lisp = _session();
  _ev(lisp, "(def mk (lambda (n) (lambda (x) (add x n))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "((mk 5) 3)")), 8);
  _ev(lisp, "(def gv 1)");
  _ev(lisp, "(def gf (lambda () gv))");
  _ev(lisp, "(def gv 2)");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(gf)")), 2);
  Lisp.destroy(lisp);
}

static void lisp_eval_globals_shadow_reserved(void) {
  Lisp lisp = Lisp.new_bare();
  EXPECT_STR_EQ(_ev(lisp, "(quote a)").str(), "a");
  _ev(lisp, "(def cond 99)");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "cond")), 99);
  Lisp.destroy(lisp);
}

static void lisp_eval_alias_chains(void) {
  Lisp lisp = _session();
  _ev(lisp, "(def plus add)");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(plus 1 2)")), 3);
  _ev(lisp, "(def plus2 plus)");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(plus2 1 2)")), 3);
  Lisp.destroy(lisp);
}

static void lisp_eval_left_to_right_arguments(void) {
  Lisp lisp = _session();
  order_log[0] = 0;
  _ev(lisp, "((lambda (a b) a) (log! 1) (log! 2))");
  EXPECT_STR_EQ(String.new(order_log), "12");

  order_log[0] = 0;
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(add (log! 1) (log! 2))")), 3);
  EXPECT_STR_EQ(String.new(order_log), "12");

  order_log[0] = 0;
  EXPECT_INT_EQ(_raised_code(lisp, "(log! (log! 1) (log! 2))"), <bad-arity>);
  EXPECT_STR_EQ(String.new(order_log), "12");

  order_log[0] = 0;
  EXPECT_INT_EQ(_raised_code2(lisp,
    "(add (log! 1) (log! 2) (log! 3) (log! 4) (log! 5) ",
    "(log! 6) (log! 7) (log! 8) (log! 9))"), <bad-arity>);
  EXPECT_STR_EQ(String.new(order_log), "123456789");
  Lisp.destroy(lisp);
}


static void lisp_eval_multiple_forms_share_one_stream(void) {
  Lisp lisp = _session();
  order_log[0] = 0;
  ScopeStats before = Scope.stats();
  Var result = _ev(lisp, "(log! 1) (log! 2) 9");
  ScopeStats after = Scope.stats();
  EXPECT_STR_EQ(String.new(order_log), "12");
  EXPECT_INT_EQ(Var.integer(result), 9);
  EXPECT_INT_EQ((int) after.live_scopes, (int) before.live_scopes);

  order_log[0] = 0;
  before = Scope.stats();
  EXPECT_INT_EQ(_raised_code(lisp, "(log! 3) missing (log! 4)"), <unbound>);
  after = Scope.stats();
  EXPECT_STR_EQ(String.new(order_log), "3");
  EXPECT_INT_EQ((int) after.live_scopes, (int) before.live_scopes);

  order_log[0] = 0;
  before = Scope.stats();
  EXPECT_INT_EQ(_raised_code(lisp, "(log! 5) \"\\z\""), <malformed>);
  after = Scope.stats();
  EXPECT_STR_EQ(String.new(order_log), "5");
  EXPECT_INT_EQ((int) after.live_scopes, (int) before.live_scopes);
  Lisp.destroy(lisp);
}


static void lisp_eval_macro_semantics(void) {
  Lisp lisp = _session();
  _ev2(lisp, "(def twice (macro (e) ",
       "(quasiquote (add (unquote e) (unquote e)))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(twice 21)")), 42);
  order_log[0] = 0;
  _ev(lisp, "(def m (macro (e) (quasiquote (log! (unquote e)))))");
  _ev(lisp, "(m 7)");
  _ev(lisp, "(m 8)");
  EXPECT_STR_EQ(String.new(order_log), "78");
  _ev(lisp, "(def m (macro (e) (quasiquote (add (unquote e) 10))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(m 1)")), 11);
  Lisp.destroy(lisp);
}

static void lisp_eval_quasiquote(void) {
  Lisp lisp = _session();
  EXPECT_VAR_EQ(_ev(lisp, "`(1 ,(add 1 1) ,@(quote (3 4)))"),
                _ev(lisp, "(quote (1 2 3 4))"));
  EXPECT_VAR_EQ(_ev(lisp, "``(a ,(b ,(add 1 2)))"),
                _ev(lisp, "'(quasiquote (a (unquote (b 3))))"));
  EXPECT_INT_EQ(_raised_code(lisp, "`,@(quote (1))"), <bad-types>);
  Lisp.destroy(lisp);
}


static void lisp_eval_list_literal_reader_prefixes(void) {
  Lisp lisp = Lisp.new();
  lisp.set_global("tail", %(3 4));
  EXPECT_VAR_EQ(
    lisp.eval(%(`(1 ,(+ 1 1) ,@tail))),
    %(1 2 3 4).var()
  );
  List quoted = %('x y);
  EXPECT_INT_EQ(quoted.len(), 2);
  List quoted_form = quoted.car();
  (Symbol quote, Symbol quoted_name) = quoted_form;
  EXPECT_STR_EQ(quote.str(), "quote");
  EXPECT_STR_EQ(quoted_name.str(), "x");
  List ordinary = %("a" 1, "b" 2);
  EXPECT_INT_EQ(ordinary.len(), 4);
  EXPECT_STR_EQ(Var.list(ordinary.get(2)).car().str(), "unquote");
  List leading = %(`x y);
  EXPECT_INT_EQ(leading.len(), 2);
  (List leading_form, Symbol trailing) = leading;
  (Symbol quasiquote, Symbol leading_name) = leading_form;
  EXPECT_STR_EQ(quasiquote.str(), "quasiquote");
  EXPECT_STR_EQ(leading_name.str(), "x");
  EXPECT_STR_EQ(trailing.str(), "y");
  List nested = %(`(a b) c);
  EXPECT_INT_EQ(nested.len(), 2);
  (List nested_form, Symbol nested_trailing) = nested;
  EXPECT_STR_EQ(nested_form.car().str(), "quasiquote");
  EXPECT_STR_EQ(nested_trailing.str(), "c");
  Lisp.destroy(lisp);
}

static void lisp_eval_strips_locals(void) {
  Lisp lisp = _session();
  _ev(lisp, "(def y 10)");
  EXPECT_INT_EQ(Var.integer(_ev(lisp,
    "((lambda (y) (eval (quote y))) 5)")), 10);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(eval (quote (add 1 2)))")), 3);
  Lisp.destroy(lisp);
}

static void lisp_eval_bind_native(void) {
  Lisp lisp = Lisp.new_bare();
  Var first = _ev(lisp,
    "(bind \"Var_car\" '((func ((\"Var\"))) \"Var\"))");
  Var second = _ev(lisp,
    "(bind \"Var_car\" '((func ((\"Var\"))) \"Var\"))");
  EXPECT_TRUE(first is <func>);
  EXPECT_TRUE(first.pointer() == second.pointer());
  EXPECT_STR_EQ(Var.string(_ev2(lisp,
    "((bind \"lisp_string_downcase\" (quote ((func ((\"String\"))) ",
    "\"Var\"))) \"ABC\")")), "abc");
  EXPECT_INT_EQ(_raised_code(lisp, "(bind \"Var_car\" 1)"), <bad-sig>);
  EXPECT_INT_EQ(_raised_code(lisp, "(bind 1 (quote ((func ((void))) void)))"),
                <bad-types>);
  /* Only the compiler-generated target table is reachable now, so a linked
     symbol outside it is refused like any unknown name. */
  EXPECT_INT_EQ(_raised_code(lisp,
                String.new("(bind \"nosuchsym\" ") +
                  "(quote ((func ((void))) void)))"),
                <no-symbol>);
  EXPECT_INT_EQ(_raised_code(lisp,
                String.new("(bind \"String_lower\" ") +
                  "(quote ((func ((\"String\"))) \"String\")))"),
                <no-symbol>);
  Lisp.destroy(lisp);
}

static void lisp_default_session_is_ready(void) {
  Lisp lisp = Lisp.new();
  if (!EXPECT_NOT_NULL(lisp)) return;
  EXPECT_INT_EQ(Var.integer(Lisp.eval(lisp, %(+ 20 22))), 42);
  EXPECT_STR_EQ(Var.string(Lisp.eval(lisp, %(lower "READY"))), "ready");
  Lisp.destroy(lisp);
}

static void lisp_pattern_matching_operations(void) {
  Lisp lisp = Lisp.new();
  if (!EXPECT_NOT_NULL(lisp)) return;
  EXPECT_VAR_EQ(_ev(lisp, "(match '(add 1 2) '(add ?x ?y))"),
                %((?y 2) (?x 1)).var());
  EXPECT_INT_EQ(Var.integer(
    _ev(lisp, "(bound (match '(add 1 2) '(add ?x ?y)) '?x)")), 1);
  EXPECT_VAR_EQ(_ev(lisp, "(match '(nil-case) '(other))"), nil.var());
  EXPECT_VAR_EQ(_ev(lisp, "(match-replace '(+ x 0) '(+ ?a 0) '(id ?a))"),
                %(id x).var());
  // A bare-binder template replaces with a scalar, which the List-typed
  // List.match_replace cannot return.
  EXPECT_VAR_EQ(_ev(lisp, "(match-replace '(+ x 0) '(+ ?a 0) '?a)"),
                Symbol.var(<x>));
  EXPECT_VAR_EQ(_ev(lisp, "(search '(f (+ x 0)) '(+ ?a 0))"),
                %(((* (+ x 0)) (?a x))).var());
  EXPECT_VAR_EQ(
    _ev(lisp, "(search-replace '(f (+ x 0) (g (+ y 0))) '(+ ?a 0) '?a)"),
    %(f x (g y)).var());
  // The whole subject is a subtree too.
  EXPECT_VAR_EQ(_ev(lisp, "(search-replace '(+ x 0) '(+ ?a 0) '?a)"),
                Symbol.var(<x>));
  Lisp.destroy(lisp);
}

static void lisp_match_case_dispatch(void) {
  Lisp lisp = Lisp.new();
  if (!EXPECT_NOT_NULL(lisp)) return;
  String rules = String.new("(defun simplify (e) (match-case e") +
    " ((+ ?x 0) ?x) ((* ?x 0) 0) ((!or (a) (b)) 'alt)" +
    " ((tag) 'no-binders) (else e)))";
  lisp.eval_string(rules);
  EXPECT_VAR_EQ(_ev(lisp, "(simplify '(+ q 0))"), Symbol.var(<q>));
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(simplify '(* z 0))")), 0);
  EXPECT_VAR_EQ(_ev(lisp, "(simplify '(b))"), Symbol.var(<alt>));
  // A pattern with no binders still matches; match returns (()), not nil.
  EXPECT_VAR_EQ(_ev(lisp, "(simplify '(tag))"), Symbol.var(<no-binders>));
  EXPECT_VAR_EQ(_ev(lisp, "(simplify '(- a b))"), %(- a b).var());
  // A binder repeated in one pattern must bind the same value twice.
  EXPECT_INT_EQ(Var.integer(
    _ev(lisp, "(match-case '(dup 5 5) ((dup ?v ?v) ?v) (else 0))")), 5);
  EXPECT_INT_EQ(Var.integer(
    _ev(lisp, "(match-case '(dup 5 6) ((dup ?v ?v) ?v) (else 0))")), 0);
  // Without an else clause an exhausted match-case is nil.
  EXPECT_VAR_EQ(_ev(lisp, "(match-case '(x) ((y) 1))"), nil.var());
  // A run binder reaches the body, and a bare wildcard binds nothing.
  EXPECT_VAR_EQ(
    _ev(lisp, "(match-case '(dim 4 (int)) ((dim ? *rest) *rest))"),
    %((int)).var());
  // A pattern describes a List shape, so an atom subject falls through.
  EXPECT_VAR_EQ(_ev(lisp, "(match 'atom '(?a ?b))"), nil.var());
  EXPECT_INT_EQ(Var.integer(
    _ev(lisp, "(match-case \"text\" ((?a ?b) 1) (else 0))")), 0);
  Lisp.destroy(lisp);
}

static void lisp_bare_session_has_only_primitives(void) {
  Lisp lisp = Lisp.new_bare();
  if (!EXPECT_NOT_NULL(lisp)) return;
  EXPECT_INT_EQ(_raised_code(lisp, "(defun answer () 42)"), <unbound>);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "((lambda (x) x) 42)")), 42);
  Lisp.destroy(lisp);
}

static void lisp_inferred_direct_binding(void) {
  Lisp lisp = Lisp.new();
  if (!EXPECT_NOT_NULL(lisp)) return;
  $lisp.bind(lisp, "greet", _lisp_bound_greet);
  EXPECT_STR_EQ(
    Var.string(Lisp.eval(lisp, %(greet "Ada"))), "hello Ada"
  );
  Lisp.destroy(lisp);
}

static void lisp_group_install_and_typed_result(void) {
  Lisp lisp = Lisp.new();
  if (!EXPECT_NOT_NULL(lisp)) return;
  $lisp.install(lisp, test_policy);
  EXPECT_INT_EQ(Var.integer(Lisp.eval(lisp, %(native-sum 19 23))), 42);
  List result = Lisp.eval(lisp, %(native-pair "limit" 7));
  (String label, int value) = result;
  EXPECT_STR_EQ(label, "limit");
  EXPECT_INT_EQ(value, 7);
  Lisp.destroy(lisp);
}

static void lisp_group_installs_into_separate_sessions(void) {
  Lisp first = Lisp.new(), second = Lisp.new();
  if (!EXPECT_NOT_NULL(first) || !EXPECT_NOT_NULL(second)) {
    Lisp.destroy(first);
    Lisp.destroy(second);
    return;
  }
  $lisp.install(first, test_policy);
  $lisp.install(second, test_policy);
  EXPECT_INT_EQ(Var.integer(Lisp.eval(first, %(native-sum 1 2))), 3);
  EXPECT_INT_EQ(Var.integer(Lisp.eval(second, %(native-sum 4 5))), 9);
  Lisp.destroy(first);
  Lisp.destroy(second);
}

static void lisp_inferred_binding_transfers_native_error(void) {
  Lisp lisp = Lisp.new();
  if (!EXPECT_NOT_NULL(lisp)) return;
  $lisp.bind(lisp, "raise-native", _lisp_bound_raise);
  int caught = 0;
  try Lisp.eval(lisp, %(raise-native 17));
  catch %(format (value 17)): caught = 1;
  EXPECT_TRUE(caught);
  Lisp.destroy(lisp);
}

static void lisp_binding_storage_belongs_to_session(void) {
  Lisp warm = Lisp.new();
  $lisp.bind(warm, "greet", _lisp_bound_greet);
  Lisp.destroy(warm);
  ScopeStats before = Scope.stats();
  Lisp lisp = Lisp.new();
  $lisp.bind(lisp, "greet", _lisp_bound_greet);
  Lisp.destroy(lisp);
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ((int) after.live_scopes, (int) before.live_scopes);
  EXPECT_INT_EQ((int) after.live_allocations, (int) before.live_allocations);
}

static void lisp_eval_file_runs_forms(void) {
  Lisp lisp = Lisp.new_bare();
  FILE *raw = fopen("/tmp/x2c-lisp-test.xlisp", "w");
  if (!EXPECT_NOT_NULL(raw)) return;
  fputs("(def z 7)\n// comment\nz\n", raw);
  fclose(raw);
  File source = File.open("/tmp/x2c-lisp-test.xlisp", "r");
  EXPECT_INT_EQ(Var.integer(Lisp.eval_file(lisp, source)), 7);
  File.close(source);
  raw = fopen("/tmp/x2c-lisp-test.xlisp", "w");
  fclose(raw);
  source = File.open("/tmp/x2c-lisp-test.xlisp", "r");
  EXPECT_TRUE(Lisp.eval_file(lisp, source).is_nil());
  File.close(source);
  Lisp.destroy(lisp);
}


static void lisp_eval_file_transfers_read_failure(void) {
  Lisp lisp = Lisp.new_bare();
  File source = File.open("/dev/null", "w");
  if (!EXPECT_NOT_NULL(source)) {
    Lisp.destroy(lisp);
    return;
  }
  int caught = 0;
  try Lisp.eval_file(lisp, source);
  catch %(io-fail *): caught = 1;
  EXPECT_TRUE(caught);
  source.close();
  Lisp.destroy(lisp);
}


static void lisp_eval_file_rejects_embedded_nul(void) {
  Lisp lisp = Lisp.new_bare();
  File source = tmpfile();
  if (!EXPECT_NOT_NULL(source)) {
    Lisp.destroy(lisp);
    return;
  }
  unsigned char bytes[] = {'1', '\0', '2'};
  EXPECT_INT_EQ(source.write(bytes, 1, sizeof(bytes)), sizeof(bytes));
  source.rewind();
  int caught = 0;
  try Lisp.eval_file(lisp, source);
  catch %(bad-arg *): caught = 1;
  EXPECT_TRUE(caught);
  source.close();
  Lisp.destroy(lisp);
}


static void lisp_bootstrap_arithmetic_and_strings(void) {
  Lisp lisp = _boot_session();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(let* ((x 6) (y (+ x 1))) (* x y))")),
                42);
  EXPECT_STR_EQ(Var.string(_ev(lisp, "(+ \"Value: \" 7)")), "Value: 7");
  EXPECT_STR_EQ(Var.string(_ev(lisp, "(lower \"ABC\")")), "abc");
  EXPECT_STR_EQ(Var.string(_ev(lisp,
                "(string-append \"minimal\" \"-\" \"lisp\")")),
                "minimal-lisp");
  EXPECT_FALSE(_ev(lisp, "(string? (string-append \"\" \"\"))").is_nil());
  EXPECT_STR_EQ(Var.string(_ev(lisp, "(substring \"scheme\" 1 4)")), "che");
  EXPECT_FALSE(_ev(lisp, "(string? (substring \"scheme\" 1 1))").is_nil());
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(string-length \"scheme\")")), 6);
  EXPECT_STR_EQ(Var.string(_ev(lisp, "(repr '(a 1))")), "(a 1)");
  EXPECT_FALSE(_ev(lisp, "(string? (str \"\"))").is_nil());
  EXPECT_FALSE(_ev(lisp, "(string? (string-downcase \"\"))").is_nil());
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(/ 8 2)")), 4);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(- 5)")), -5);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(/ 8)")), 0);
  EXPECT_FALSE(_ev(lisp, "(= 3 3 3)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(< 1 2 3)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(<= 1 1 2)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(> 3 2 1)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(>= 3 3 2)").is_nil());
  Lisp.destroy(lisp);
}

/* Machine and Lisp frame storage is allocated on the session scope rather than
   the C stack. While it was a stack local, every evaluator frame reserved
   about 44 KB and recursion died with SIGSEGV past 88 levels -- inside the
   reach of the stdlib list primitives, which recurse once per element. */
static void lisp_deep_recursion_survives_stack(void) {
  Lisp lisp = _boot_session();
  _ev(lisp, "(def down (lambda (k) (if (= k 0) 0 (down (- k 1)))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(down 1000)")), 0);
  // Rest parameters make a lambda AUTO-ineligible, so this arm runs on the
  // evaluator rather than the prepared machine.
  _ev(lisp, "(def slow (lambda (k . rest) (if (= k 0) 0 (slow (- k 1)))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(slow 1000)")), 0);
  _ev2(lisp, "(def build (lambda (k acc)",
             " (if (= k 0) acc (build (- k 1) (cons k acc)))))");
  _ev(lisp, "(def wide (build 1000 nil))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(length wide)")), 1000);
  EXPECT_INT_EQ(
    Var.integer(_ev(lisp, "(length (map (lambda (v) v) wide))")), 1000);
  EXPECT_INT_EQ(
    Var.integer(_ev(lisp, "(length (filter (lambda (v) true) wide))")), 1000);
  EXPECT_INT_EQ(
    Var.integer(_ev(lisp, "(length (append wide (list 0)))")), 1001);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(length (reverse wide))")), 1000);
  Lisp.destroy(lisp);
}

/* The nine variadic arithmetic operators are native so compiled calls
   avoid evaluator dispatch for variadic lambdas. These Lisp definitions
   provide a reference implementation; compare every result and raised code. */
static void _same(Lisp lisp, const char *fresh, const char *old) {
  Symbol left = _raised_code(lisp, fresh), right = _raised_code(lisp, old);
  EXPECT_INT_EQ((int) left, (int) right);
  if (!left) EXPECT_VAR_EQ(_ev(lisp, fresh), _ev(lisp, old));
}

static void lisp_native_operators_match_their_lisp_definitions(void) {
  Lisp lisp = _boot_session();
  _ev2(lisp, "(defun o+ (. v) (if (null? v) 0 (foldl _add ",
             "(if (string? (car v)) \"\" 0) v)))");
  _ev2(lisp, "(defun o- (. v) (cond ((null? v) (sub)) ((null? (cdr v)) ",
             "(sub 0 (car v))) (true (foldl sub (car v) (cdr v)))))");
  _ev(lisp, "(defun o* (. v) (foldl mul 1 v))");
  _ev2(lisp, "(defun o/ (. v) (cond ((null? v) (div)) ((null? (cdr v)) ",
             "(div 1 (car v))) (true (foldl div (car v) (cdr v)))))");
  _ev2(lisp, "(defun oe (a b . r) (if (eq? (_compare a b) 0) ",
             "(if (null? r) true (apply oe (cons b r))) false))");
  _ev2(lisp, "(defun ol (a b . r) (if (eq? (_compare a b) -1) ",
             "(if (null? r) true (apply ol (cons b r))) false))");
  _ev2(lisp, "(defun ole (a b . r) (if (eq? (_compare a b) 1) false ",
             "(if (null? r) true (apply ole (cons b r)))))");
  _ev2(lisp, "(defun og (a b . r) (if (eq? (_compare a b) 1) ",
             "(if (null? r) true (apply og (cons b r))) false))");
  _ev2(lisp, "(defun oge (a b . r) (if (eq? (_compare a b) -1) false ",
             "(if (null? r) true (apply oge (cons b r)))))");

  _same(lisp, "(+)", "(o+)");
  _same(lisp, "(+ 5)", "(o+ 5)");
  _same(lisp, "(+ 1 2 3)", "(o+ 1 2 3)");
  _same(lisp, "(+ \"a\" \"b\" \"c\")", "(o+ \"a\" \"b\" \"c\")");
  _same(lisp, "(+ \"x\" 1)", "(o+ \"x\" 1)");
  _same(lisp, "(+ 1 nil)", "(o+ 1 nil)");
  _same(lisp, "(apply + '(10 20 12))", "(apply o+ '(10 20 12))");
  _same(lisp, "(-)", "(o-)");
  _same(lisp, "(- 7)", "(o- 7)");
  _same(lisp, "(- 10 3 2)", "(o- 10 3 2)");
  _same(lisp, "(*)", "(o*)");
  _same(lisp, "(* 2 3 4)", "(o* 2 3 4)");
  _same(lisp, "(/)", "(o/)");
  _same(lisp, "(/ 4)", "(o/ 4)");
  _same(lisp, "(/ 100 5 2)", "(o/ 100 5 2)");
  _same(lisp, "(= 1)", "(oe 1)");
  _same(lisp, "(= 1 1 1)", "(oe 1 1 1)");
  _same(lisp, "(= 1 2)", "(oe 1 2)");
  _same(lisp, "(= \"a\" \"a\")", "(oe \"a\" \"a\")");
  _same(lisp, "(< 1 2 3)", "(ol 1 2 3)");
  _same(lisp, "(< 1 3 2)", "(ol 1 3 2)");
  _same(lisp, "(<= 1 1 2)", "(ole 1 1 2)");
  _same(lisp, "(<= 2 1)", "(ole 2 1)");
  _same(lisp, "(> 3 2 1)", "(og 3 2 1)");
  _same(lisp, "(> 1 2)", "(og 1 2)");
  _same(lisp, "(>= 2 2 1)", "(oge 2 2 1)");
  _same(lisp, "(>= 1 2)", "(oge 1 2)");
  Lisp.destroy(lisp);
}

static void lisp_bootstrap_collections_and_macros(void) {
  Lisp lisp = _boot_session();
  EXPECT_VAR_EQ(_ev(lisp, "(map (lambda (x) (* x x)) '(1 2 3))"),
                _ev(lisp, "'(1 4 9)"));
  EXPECT_VAR_EQ(_ev(lisp, "(filter (lambda (x) (> x 1)) '(1 2 3))"),
                _ev(lisp, "'(2 3)"));
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(foldl + 0 '(10 20 12))")), 42);
  EXPECT_VAR_EQ(_ev(lisp, "(append '(1 2) '(3 4))"), _ev(lisp, "'(1 2 3 4)"));
  EXPECT_VAR_EQ(_ev(lisp, "(reverse '(1 2 3))"), _ev(lisp, "'(3 2 1)"));
  EXPECT_VAR_EQ(_ev(lisp, "(member 2 '(1 2 3))"), _ev(lisp, "'(2 3)"));
  EXPECT_VAR_EQ(_ev(lisp, "(assoc 'b '((a 1) (b 2)))"), _ev(lisp, "'(b 2)"));
  EXPECT_INT_EQ(Var.integer(_ev(lisp,
    "(cadr (assoc '?x (match '(1 2) '(?x ?y))))")), 1);
  EXPECT_VAR_EQ(
    _ev(lisp, "(cadr (assoc '?value (match '(same same) '(?value ?value))))"),
    _ev(lisp, "'same")
  );
  EXPECT_TRUE(_ev(lisp, "(match '(same other) '(?value ?value))").is_nil());
  EXPECT_VAR_EQ(
    _ev(lisp,
      "(cadr (assoc '*same (match '(a pivot a) '(*same pivot *same))))"),
    _ev(lisp, "'(a)")
  );
  EXPECT_TRUE(_ev(lisp, "(match '(a pivot b) '(*same pivot *same))").is_nil());
  EXPECT_FALSE(_ev(lisp, "(match '(literal) '(literal))").is_nil());
  EXPECT_INT_EQ(Var.integer(_ev(lisp,
                "(length (match '(literal) '(literal)))")), 1);
  _ev(lisp, "(def match 17)");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "match")), 17);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(length '(1 2 3))")), 3);

  _ev(lisp, "(def touched 0)");
  EXPECT_TRUE(_ev(lisp, "(and false (def touched 1))").is_nil());
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "touched")), 0);
  EXPECT_VAR_EQ(_ev(lisp, "(or true (def touched 2))"), _ev(lisp, "true"));
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "touched")), 0);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(and 1 2 3)")), 3);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(or nil 0 3)")), 0);
  Lisp.destroy(lisp);
}

static void lisp_bootstrap_predicates_are_exact(void) {
  Lisp lisp = _boot_session();
  Array array = %[];
  Map map = %{};
  Lisp.set_global(lisp, "array-value", array);
  Lisp.set_global(lisp, "map-value", map);

  EXPECT_FALSE(_ev(lisp, "(list? nil)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(list? '(1))").is_nil());
  EXPECT_FALSE(_ev(lisp, "(pair? '(1))").is_nil());
  EXPECT_TRUE(_ev(lisp, "(pair? nil)").is_nil());
  EXPECT_TRUE(_ev(lisp, "(list? array-value)").is_nil());
  EXPECT_TRUE(_ev(lisp, "(list? map-value)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(atom? array-value)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(number? 1.5)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(string? \"x\")").is_nil());
  EXPECT_FALSE(_ev(lisp, "(symbol? 'x)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(procedure? +)").is_nil());
  EXPECT_FALSE(_ev(lisp, "(procedure? (lambda (x) x))").is_nil());
  Lisp.destroy(lisp);
}

static void lisp_optional_layers_are_explicit(void) {
  Lisp lisp = _boot_session();
  Var value = void;
  EXPECT_FALSE(Lisp.try_get(lisp, "fib", &value));
  EXPECT_FALSE(Lisp.try_get(lisp, "read-file", &value));

  if (_load_lisp_layer(lisp, "../etc/lisp-extras.xlisp")) {
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(fib 8)")), 21);
    EXPECT_VAR_EQ(_ev(lisp, "(range 4)"), _ev(lisp, "'(0 1 2 3)"));
    EXPECT_VAR_EQ(_ev(lisp, "(sort '(3 1 2))"), _ev(lisp, "'(1 2 3)"));
    EXPECT_VAR_EQ(_ev(lisp, "(subst 'x 'a '(a (b a)))"),
                  _ev(lisp, "'(x (b x))"));
  }

  if (_load_lisp_layer(lisp, "../etc/lisp-io.xlisp")) {
    EXPECT_FALSE(_ev(lisp,
      "(write-file \"/tmp/x2c-lisp-io.txt\" \"minimal sdk\")").is_nil());
    EXPECT_STR_EQ(Var.string(_ev(lisp,
                  "(read-file \"/tmp/x2c-lisp-io.txt\")")),
                  "minimal sdk");
    EXPECT_FALSE(_ev(lisp,
      "(write-file \"/tmp/x2c-lisp-io.txt\" \"\")").is_nil());
    Var empty = _ev(lisp, "(read-file \"/tmp/x2c-lisp-io.txt\")");
    EXPECT_TRUE(empty is <string>);
    EXPECT_NULL(Var.string(empty));
  }
  Lisp.destroy(lisp);
}

static void lisp_bootstrap_import_uses_current_session(void) {
  FILE *raw = fopen("/tmp/x2c-lisp-import.xlisp", "w");
  if (!EXPECT_NOT_NULL(raw)) return;
  fputs("(def imported 73)\nimported\n", raw);
  fclose(raw);
  Lisp lisp = _boot_session();
  EXPECT_INT_EQ(Var.integer(_ev(lisp,
                "(import \"/tmp/x2c-lisp-import.xlisp\")")), 73);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "imported")), 73);
  EXPECT_INT_EQ(
    _raised_code(lisp, "(import \"/tmp/missing-x2c-lisp\")"),
    <not-found>);
  Lisp.destroy(lisp);
}

static void lisp_sessions_release_scopes(void) {
  Lisp warm = Lisp.new_bare();
  Lisp.eval_string(warm, "(def w (lambda (a) a)) (w 4)");
  Lisp.destroy(warm);
  ScopeStats before = Scope.stats();
  for (int i = 0; i < 3; i++) {
    Lisp lisp = Lisp.new_bare();
    Lisp.eval_string(lisp, "(def w (lambda (a) a)) (w 4)");
    Lisp.destroy(lisp);
  }
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ((int) after.live_scopes, (int) before.live_scopes);
}

$(import "test-macros.xmacro")

void lisp_suite(void) {
  $test.run(lisp_canonical_names_outlive_initial_context);
  $test.run(lisp_read_integer_value);
  $test.run(lisp_read_float_value);
  $test.run(lisp_read_string_value);
  $test.run(lisp_read_identifier_representations);
  $test.run(lisp_read_case_sensitive_long_identifiers);
  $test.run(lisp_read_compact_symbol_literal);
  $test.run(lisp_read_list_form);
  $test.run(lisp_read_matches_x2c_list_literal);
  $test.run(lisp_read_quote_sugar);
  $test.run(lisp_read_comments_and_whitespace);
  $test.run(lisp_read_eof_cases);
  $test.run(lisp_read_incomplete_resets_cursor);
  $test.run(lisp_read_malformed_reports_error);
  $test.run(lisp_read_classifies_lexical_failures);
  $test.run(lisp_read_advances_cursor_across_forms);
  $test.run(lisp_eval_self_and_quote);
  $test.run(lisp_eval_def_and_globals);
  $test.run(lisp_eval_cond_nil_only_false);
  $test.run(lisp_eval_lambda_application);
  $test.run(lisp_apply_uses_evaluated_values);
  $test.run(lisp_eval_rest_parameters);
  $test.run(lisp_eval_capture_semantics);
  $test.run(lisp_eval_globals_shadow_reserved);
  $test.run(lisp_eval_alias_chains);
  $test.run(lisp_eval_left_to_right_arguments);
  $test.run(lisp_eval_multiple_forms_share_one_stream);
  $test.run(lisp_eval_macro_semantics);
  $test.run(lisp_eval_quasiquote);
  $test.run(lisp_eval_list_literal_reader_prefixes);
  $test.run(lisp_eval_strips_locals);
  $test.run(lisp_eval_bind_native);
  $test.run(lisp_default_session_is_ready);
  $test.run(lisp_pattern_matching_operations);
  $test.run(lisp_match_case_dispatch);
  $test.run(lisp_bare_session_has_only_primitives);
  $test.run(lisp_inferred_direct_binding);
  $test.run(lisp_group_install_and_typed_result);
  $test.run(lisp_group_installs_into_separate_sessions);
  $test.run(lisp_inferred_binding_transfers_native_error);
  $test.run(lisp_binding_storage_belongs_to_session);
  $test.run(lisp_eval_file_runs_forms);
  $test.run(lisp_eval_file_transfers_read_failure);
  $test.run(lisp_eval_file_rejects_embedded_nul);
  $test.run(lisp_bootstrap_arithmetic_and_strings);
  $test.run(lisp_deep_recursion_survives_stack);
  $test.run(lisp_native_operators_match_their_lisp_definitions);
  $test.run(lisp_bootstrap_collections_and_macros);
  $test.run(lisp_bootstrap_predicates_are_exact);
  $test.run(lisp_optional_layers_are_explicit);
  $test.run(lisp_bootstrap_import_uses_current_session);
  $test.run(lisp_sessions_release_scopes);
}
