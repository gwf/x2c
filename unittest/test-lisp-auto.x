/*  test-lisp-auto.x -- production second-call AUTO at the _apply hook

    The complete L1-L12 matrix against the real private boundary:
    ordinary public evaluation, no fixture dispatcher.  The recursive
    evaluator remains the semantic oracle; every row checks results,
    exact raised errors, hook telemetry, and machine counters where the
    frozen matrix pinned them.  The scoping rows pin the lexical rule: a
    free name reads what the body was written next to, so a caller's
    binding of the same name changes nothing. */

#include "test-support.x"

static long auto_add_calls;
static long auto_mult_calls;
static char auto_order_log[64];

static Var _auto_native_add(Var a, Var b) {
  auto_add_calls++;
  return a.binary(<+>, b);
}

static Var _auto_native_add100(Var a, Var b) {
  return Var.binary(a.binary(<+>, b), <+>, Var.new(<i32>, 100));
}

static Var _auto_native_mult(Var a, Var b) {
  auto_mult_calls++;
  return a.binary(<"*">, b);
}

static Var _auto_native_log(Var v) {
  strcat(auto_order_log, v.str());
  return v;
}

static Var _binary_signature(void) {
  return %((func (("Var") ("Var"))) "Var");
}

static Func _make_func(FuncAdapter fn, Var signature) {
  Func func = Func.new(fn, Var.list(signature));
  EXPECT_NOT_NULL(func);
  return func;
}

static Var _ev(Lisp lisp, const char *text) {
  return lisp.eval_string(String.new(text));
}

static Symbol _raised(Lisp lisp, const char *text) {
  Symbol code = 0;
  try _ev(lisp, text);
  catch %(bad-arity *): code = <bad-arity>;
  catch %(bad-types *): code = <bad-types>;
  catch %(bad-sig *): code = <bad-sig>;
  catch %(not-call *): code = <not-call>;
  catch %(unbound *): code = <unbound>;
  return code;
}

static Lisp _auto_session(int with_add) {
  Lisp lisp = Lisp.kernel();
  if (with_add)
    lisp.set_global("add",
                    Func.var(_make_func(
                                        _auto_native_add,
                                        _binary_signature())));
  lisp.set_global("log!",
                  Func.var(_make_func(
                    _auto_native_log,
                    %((func (("Var"))) "Var"))));
  _ev(lisp, "(def helper (lambda (x bias) (add x bias)))");
  _ev(lisp,
      "(def make-brancher (lambda (bias) (lambda (x) (cond (x (helper x bias)) (1 bias)))))");
  _ev(lisp, "(def brancher (make-brancher 5))");
  return lisp;
}

static void lisp_auto_second_call_transition(void) {
  Lisp lisp = _auto_session(1);
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  lisp.auto_instrument(&mstats);
  LispAutoStats before = lisp.auto_stats();

  // L1: EVAL -> AUTO -> PREPARED, all 12.
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats first = lisp.auto_stats();
  EXPECT_INT_EQ((int) (first.machine_entries - before.machine_entries), 0);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats second = lisp.auto_stats();
  EXPECT_INT_EQ((int) (second.machine_entries - before.machine_entries), 2);
  EXPECT_INT_EQ((int) (second.published - before.published), 2);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats third = lisp.auto_stats();
  EXPECT_INT_EQ((int) (third.machine_entries - before.machine_entries), 3);
  EXPECT_INT_EQ((int) (third.analyses - before.analyses), 2);

  // Exact per-entry machine work, matching the frozen L1 counters.
  EXPECT_INT_EQ((int) mstats.nil_edges, 2);
  EXPECT_INT_EQ((int) mstats.nil_taken, 0);
  EXPECT_INT_EQ((int) mstats.local_loads, 7);
  EXPECT_INT_EQ((int) mstats.capture_loads, 1);
  EXPECT_INT_EQ((int) mstats.global_loads, 4);
  EXPECT_INT_EQ((int) mstats.prepared_calls, 1);
  EXPECT_INT_EQ((int) mstats.native_calls, 2);
  // Three returns: the helper's call is in tail position and reuses the
  // frame it stands in rather than returning from one of its own.
  EXPECT_INT_EQ((int) mstats.lisp_returns, 3);
  lisp.destroy();
}

static void lisp_auto_nil_path(void) {
  // L2: the nil arm publishes the same programs but calls nothing.
  Lisp lisp = _auto_session(1);
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  lisp.auto_instrument(&mstats);
  EXPECT_TRUE(_ev(lisp, "(brancher ())").is_nil() == 0);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher ())")), 5);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher ())")), 5);
  EXPECT_INT_EQ((int) mstats.local_loads, 2);
  EXPECT_INT_EQ((int) mstats.nil_taken, 2);
  EXPECT_INT_EQ((int) mstats.capture_loads, 2);
  EXPECT_INT_EQ((int) mstats.global_loads, 0);
  EXPECT_INT_EQ((int) mstats.prepared_calls, 0);
  EXPECT_INT_EQ((int) mstats.native_calls, 0);
  EXPECT_INT_EQ((int) mstats.lisp_returns, 2);
  EXPECT_INT_EQ((int) lisp.auto_stats().published, 1);

  // L3: captures outlive the maker frame by construction; numeric
  // zero is not nil and takes the hit arm.
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 0)")), 5);
  lisp.destroy();
}

static void lisp_auto_replacement_guards(void) {
  Lisp lisp = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats warmed = lisp.auto_stats();

  // L4: replacing the native add is visible immediately through the
  // late lookup, with no reanalysis and no republication.
  Var original = void;
  EXPECT_TRUE(lisp.try_get("add", &original));
  lisp.set_global("add",
                  Func.var(_make_func(
                                      _auto_native_add100,
                                      _binary_signature())));
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 112);
  lisp.set_global("add", original);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats after = lisp.auto_stats();
  EXPECT_INT_EQ((int) (after.published - warmed.published), 0);
  EXPECT_INT_EQ((int) (after.analyses - warmed.analyses), 0);

  // L5: a helper replacement starts a fresh threshold, as does a
  // brancher replacement.
  _ev(lisp, "(def helper (lambda (x bias) (add (add x bias) 1)))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 13);
  after = lisp.auto_stats();
  EXPECT_INT_EQ((int) (after.published - warmed.published), 0);
  LispAutoStats base = after;
  _ev(lisp, "(def brancher (lambda (x) (add x 20)))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 27);
  EXPECT_INT_EQ((int) (lisp.auto_stats().machine_entries -
                       base.machine_entries), 0);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 27);
  EXPECT_INT_EQ((int) (lisp.auto_stats().machine_entries -
                       base.machine_entries), 1);

  // L6: a native helper replacement crosses the one callable service
  // directly: no add call, no prepared child call.
  Lisp fresh = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(fresh, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(fresh, "(brancher 7)")), 12);
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  fresh.auto_instrument(&mstats);
  fresh.set_global("helper",
                   Func.var(_make_func(
                                       _auto_native_mult,
                                       _binary_signature())));
  long adds = auto_add_calls;
  EXPECT_INT_EQ(Var.integer(_ev(fresh, "(brancher 7)")), 35);
  EXPECT_INT_EQ((int) (auto_add_calls - adds), 0);
  EXPECT_INT_EQ((int) mstats.prepared_calls, 0);
  EXPECT_INT_EQ((int) mstats.native_calls, 1);
  fresh.destroy();
  lisp.destroy();
}

static void lisp_auto_cond_identity_guard(void) {
  // A rebound cond reaches its site guard on the machine. It raises before
  // evaluating arguments; restoring the identity resumes the lowered form.
  Lisp lisp = _auto_session(1);
  Var reserved = _ev(lisp, "cond");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats warmed = lisp.auto_stats();
  long adds = auto_add_calls;
  _ev(lisp, "(def cond 99)");
  EXPECT_INT_EQ(_raised(lisp, "(brancher 7)"), <not-call>);
  LispAutoStats blocked = lisp.auto_stats();
  EXPECT_INT_EQ((int) (blocked.machine_entries - warmed.machine_entries), 1);
  EXPECT_TRUE(blocked.guard_failures > warmed.guard_failures);
  EXPECT_INT_EQ((int) (auto_add_calls - adds), 0);
  lisp.set_global("cond", reserved);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ((int) (lisp.auto_stats().machine_entries -
                       warmed.machine_entries), 2);
  lisp.destroy();
}

static void lisp_auto_error_paths(void) {
  // L9a: an unbound native reports the same error from interpreted and
  // prepared execution.
  Lisp missing = _auto_session(0);
  EXPECT_INT_EQ(_raised(missing, "(brancher 7)"), <unbound>);
  EXPECT_INT_EQ(_raised(missing, "(brancher 7)"), <unbound>);
  EXPECT_INT_EQ(_raised(missing, "(brancher 7)"), <unbound>);
  missing.destroy();

  // L9b: a non-callable helper replacement fails inside the prepared
  // caller without replaying it.
  Lisp lisp = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats warmed = lisp.auto_stats();
  _ev(lisp, "(def helper 42)");
  EXPECT_INT_EQ(_raised(lisp, "(brancher 7)"), <not-call>);
  EXPECT_INT_EQ((int) (lisp.auto_stats().machine_entries -
                       warmed.machine_entries), 1);

  // Argument-count mismatches decline so the evaluator owns the
  // exact apply-args error.
  EXPECT_INT_EQ(_raised(lisp, "(brancher 1 2)"), <bad-arity>);
  lisp.destroy();
}

static void lisp_auto_recursion_and_effects(void) {
  // L10: recursive prepared frames restore caller state exactly.
  Lisp lisp = _auto_session(1);
  _ev(lisp,
      "(def helper (lambda (x bias) (cond (x (helper () (add x bias))) (1 bias))))");
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  lisp.auto_instrument(&mstats);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ((int) mstats.prepared_calls, 2);
  EXPECT_INT_EQ((int) mstats.native_calls, 1);
  // Two returns: helper's recursive call and its tail call back out both
  // reuse the frame they stand in, so only the entries return.
  EXPECT_INT_EQ((int) mstats.lisp_returns, 2);

  // Left-to-right effects: top-level arguments through the shared
  // owner, nested arguments through the machine.
  auto_order_log[0] = 0;
  _ev(lisp, "(def observer (lambda (a b) b))");
  _ev(lisp, "(observer (log! 1) (log! 2))");
  _ev(lisp, "(observer (log! 3) (log! 4))");
  EXPECT_STR_EQ(String.new(auto_order_log), "1234");
  auto_order_log[0] = 0;
  _ev(lisp, "(def nested (lambda (x) (observer (log! 5) (log! 6))))");
  _ev(lisp, "(nested 1)");
  _ev(lisp, "(nested 1)");
  EXPECT_STR_EQ(String.new(auto_order_log), "5656");
  lisp.destroy();
}

static void lisp_auto_rest_and_macro_preparation(void) {
  // L11: rest parameters remain interpreted; macros prepare normally.
  Lisp lisp = _auto_session(1);
  _ev(lisp, "(def resty (lambda (x . r) x))");
  _ev(lisp, "(def identity-m (macro (x) x))");
  LispAutoStats before = lisp.auto_stats();
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(resty 3 4)")), 3);
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(identity-m 9)")), 9);
  LispAutoStats after = lisp.auto_stats();
  EXPECT_INT_EQ((int) (after.analyses - before.analyses), 2);
  EXPECT_INT_EQ((int) (after.ineligible - before.ineligible), 1);
  EXPECT_INT_EQ((int) (after.published - before.published), 1);
  EXPECT_INT_EQ((int) (after.remembered_fallbacks -
                       before.remembered_fallbacks), 1);
  EXPECT_INT_EQ((int) (after.machine_entries - before.machine_entries), 2);
  lisp.destroy();
}

static void lisp_auto_quasiquote(void) {
  Lisp lisp = _auto_session(1);
  _ev(lisp, "(def qq (lambda (x xs) `(1 ,(add x 1) ,@xs)))");
  LispAutoStats before = lisp.auto_stats();
  Var interpreted = _ev(lisp, "(qq 2 '(4 5))");
  EXPECT_VAR_EQ(interpreted, _ev(lisp, "'(1 3 4 5)"));
  EXPECT_VAR_EQ(_ev(lisp, "(qq 2 '(4 5))"), interpreted);
  EXPECT_INT_EQ((int) (lisp.auto_stats().machine_entries -
                       before.machine_entries), 1);

  _ev(lisp, "(def nested-qq (lambda (x) ``(a ,(b ,x))))");
  interpreted = _ev(lisp, "(nested-qq 3)");
  EXPECT_VAR_EQ(_ev(lisp, "(nested-qq 3)"), interpreted);

  auto_order_log[0] = 0;
  _ev(lisp, "(def qq-log (lambda (x) `(,(log! x) ,@'(2 3) ,(log! x))))");
  EXPECT_VAR_EQ(_ev(lisp, "(qq-log 7)"), _ev(lisp, "'(7 2 3 7)"));
  EXPECT_VAR_EQ(_ev(lisp, "(qq-log 8)"), _ev(lisp, "'(8 2 3 8)"));
  EXPECT_STR_EQ(String.new(auto_order_log), "7788");

  _ev(lisp, "(def bad-splice (lambda (x) `(1 ,@x)))");
  EXPECT_INT_EQ(_raised(lisp, "(bad-splice 7)"), <bad-types>);
  EXPECT_INT_EQ(_raised(lisp, "(bad-splice 7)"), <bad-types>);
  _ev(lisp, "(def bad-top (lambda (x) `,@x))");
  EXPECT_INT_EQ(_raised(lisp, "(bad-top '(1))"), <bad-types>);
  EXPECT_INT_EQ(_raised(lisp, "(bad-top '(1))"), <bad-types>);
  _ev(lisp, "(def bad-qq-arity (lambda (x) (quasiquote ((unquote x x)))))");
  EXPECT_INT_EQ(_raised(lisp, "(bad-qq-arity 1)"), <bad-arity>);
  EXPECT_INT_EQ(_raised(lisp, "(bad-qq-arity 1)"), <bad-arity>);
  lisp.destroy();
}

static void lisp_auto_macro_calls(void) {
  Lisp lisp = _auto_session(1);
  _ev(lisp, "(def twice (macro (e) `(add ,e ,e)))");
  _ev(lisp, "(def call-twice (lambda (x) (twice (log! x))))");
  auto_order_log[0] = 0;
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(call-twice 7)")), 14);
  LispAutoStats warmed = lisp.auto_stats();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(call-twice 8)")), 16);
  LispAutoStats prepared = lisp.auto_stats();
  // One entry, not two: analysis expanded `twice` into the caller, so
  // the macro itself no longer runs at call time.
  EXPECT_INT_EQ((int) (prepared.machine_entries - warmed.machine_entries), 1);
  EXPECT_STR_EQ(String.new(auto_order_log), "7788");

  _ev(lisp, "(def caller-name (macro () 'x))");
  _ev(lisp, "(def read-caller (lambda (x) (caller-name)))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-caller 9)")), 9);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-caller 10)")), 10);

  _ev(lisp, "(def plus-n (macro (e) `(add ,e 1)))");
  _ev(lisp, "(def use-plus-n (lambda (x) (plus-n x)))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(use-plus-n 2)")), 3);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(use-plus-n 2)")), 3);
  // Redefinition invalidates this expansion at its use inside the program.
  _ev(lisp, "(def plus-n (macro (e) `(add ,e 10)))");
  LispAutoStats stale = lisp.auto_stats();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(use-plus-n 2)")), 12);
  LispAutoStats after = lisp.auto_stats();
  EXPECT_TRUE(after.guard_failures > stale.guard_failures);
  lisp.destroy();
}

static void lisp_auto_quasiquote_capacity(void) {
  Lisp lisp = _auto_session(1);
  Buffer source = Buffer.new(0);
  source.write("(def deep-qq (lambda (x) `(");
  for (int i = 0; i < 250; i++) source.write("0 ");
  source.write(",x)))");
  _ev(lisp, source.str_free());
  LispAutoStats before = lisp.auto_stats();
  EXPECT_INT_EQ(Var.list(_ev(lisp, "(deep-qq 7)")).len(), 251);
  EXPECT_INT_EQ(Var.list(_ev(lisp, "(deep-qq 7)")).len(), 251);
  LispAutoStats after = lisp.auto_stats();
  // The quasiquote exceeds the operand stack, so it is interpreted in place;
  // the lambda around it still prepares and runs on the machine.
  EXPECT_INT_EQ((int) (after.machine_entries - before.machine_entries), 1);
  EXPECT_INT_EQ((int) (after.ineligible - before.ineligible), 0);
  lisp.destroy();
}

static void lisp_auto_session_isolation(void) {
  // L12: generations of state are per-Lambda, so sessions cannot
  // observe each other even across allocator reuse.
  Lisp a = _auto_session(1), b = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(a, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(a, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(b, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(b, "(brancher 7)")), 12);
  a.set_global("add",
               Func.var(_make_func(
                                   _auto_native_add100,
                                   _binary_signature())));
  EXPECT_INT_EQ(Var.integer(_ev(a, "(brancher 7)")), 112);
  EXPECT_INT_EQ(Var.integer(_ev(b, "(brancher 7)")), 12);
  a.destroy();
  Lisp c = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(c, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(c, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(b, "(brancher 7)")), 12);
  c.destroy();
  b.destroy();
}

static void lisp_auto_caller_binding_is_invisible(void) {
  // A caller binding a name the callee reads freely changes nothing: the
  // callee's `add` is still the global one. The call stays on the machine,
  // so there is no guard to fail and no effect to hold back.
  Lisp lisp = _auto_session(1);
  _ev(lisp, "(def wrapper (lambda (add) (brancher 7)))");
  LispAutoStats before = lisp.auto_stats();
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(wrapper 99)")), 12);
  EXPECT_INT_EQ((int) (lisp.auto_stats().guard_failures -
                       before.guard_failures), 0);

  // The same call through a non-shadowing wrapper answers the same.
  _ev(lisp, "(def clean (lambda (unused) (brancher 7)))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(clean 1)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(clean 1)")), 12);
  EXPECT_TRUE(lisp.auto_stats().machine_entries > 0);
  lisp.destroy();
}

static void lisp_auto_expands_macro_heads(void) {
  // `if` is a macro, so until analysis expanded macro heads every
  // recursive call left the machine for the evaluator: the standard
  // library made the compiled path almost unreachable.
  Lisp lisp = Lisp.new();
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  lisp.auto_instrument(&mstats);
  LispAutoStats before = lisp.auto_stats();
  _ev(lisp, "(defun cd (n a) (if (= n 0) a (cd (- n 1) (+ a 1))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(cd 40 0)")), 40);
  EXPECT_TRUE(mstats.prepared_calls > 0);
  EXPECT_INT_EQ((int) (lisp.auto_stats().guard_failures -
                       before.guard_failures), 0);
  lisp.destroy();
}

static void lisp_auto_macro_rebinding_guard(void) {
  // A program built from an expansion is valid only while the macro it
  // expanded still means the same thing.
  Lisp lisp = Lisp.new();
  _ev(lisp, "(defun pick (a b) (if a a b))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick 1 2)")), 1);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick 1 2)")), 1);
  EXPECT_TRUE(lisp.auto_stats().machine_entries > 0);

  // Swapping the arms of `if` must reach a program compiled before the
  // swap: the stale program would still answer 1. Checking at the macro
  // call preserves effects from earlier instructions in the same call.
  _ev(lisp, "(defmacro if (c x y) `(cond (,c ,y) (true ,x)))");
  LispAutoStats warmed = lisp.auto_stats();
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick 1 2)")), 2);
  LispAutoStats blocked = lisp.auto_stats();
  EXPECT_TRUE(blocked.guard_failures > warmed.guard_failures);
  lisp.destroy();
}

static void lisp_auto_tail_calls_stay_flat(void) {
  // A lambda calling itself in tail position reuses the frame it is
  // standing in, so depth far past MACHINE_FRAME_MAX costs one frame.
  Lisp lisp = Lisp.new();
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  lisp.auto_instrument(&mstats);
  _ev(lisp, "(defun cd (n a) (if (= n 0) a (cd (- n 1) (+ a 1))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(cd 4000 0)")), 4000);
  EXPECT_INT_EQ(mstats.max_frames, 1);
  EXPECT_TRUE(mstats.prepared_calls > 3000);

  // The call resolves the current binding; rebinding its name cannot
  // tail-call the old program.
  _ev(lisp, "(def old cd)");
  _ev(lisp, "(def cd 5)");
  EXPECT_INT_EQ(_raised(lisp, "(old 3 0)"), <not-call>);
  lisp.destroy();
}

static void lisp_auto_tail_call_to_another(void) {
  // A tail call reuses the frame it stands in whatever lambda it names. The
  // callee writes its own slots over the caller's dead ones, and a free name
  // is lexical, so `leaf` reads the global `x` rather than the `x` its
  // caller was passed. One frame serves the whole chain.
  Lisp lisp = Lisp.new();
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  lisp.auto_instrument(&mstats);
  _ev(lisp, "(def x 1)");
  _ev(lisp, "(defun leaf () x)");
  _ev(lisp, "(defun mid (x) (leaf))");
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(mid 99)")), 1);
  EXPECT_INT_EQ(mstats.max_frames, 1);
  lisp.destroy();
}

static void lisp_auto_forced_evaluator_arm(void) {
  // The benchmark's forced-evaluator control: identical results with
  // zero machine entries, then re-enabled AUTO resumes.
  Lisp lisp = _auto_session(1);
  lisp.auto_disable(1);
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ((int) lisp.auto_stats().machine_entries, 0);
  lisp.auto_disable(0);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_TRUE(lisp.auto_stats().machine_entries > 0);
  lisp.destroy();
}

static void lisp_auto_local_bindings(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(defun parallel (x) (let ((x 2) (y x)) y))");
    _ev(lisp, "(defun sequential (x) (let* ((x 2) (y x)) y))");
    _ev(lisp, "(defun shadow (x) (let ((x 2)) (let ((x 3)) x)))");
    _ev(lisp, "(defun duplicate () ((lambda (x x) x) 2 3))");
    for (int i = 0; i < 3; i++) {
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(parallel 7)")), 7);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(sequential 7)")), 2);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(shadow 7)")), 3);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(duplicate)")), 3);
    }
    MachineView view;
    int nparam;
    Var body;
    EXPECT_INT_EQ(Lisp.program(_ev(lisp, "parallel"),
                              &view, &nparam, &body), !disabled);
    lisp.destroy();
  }
}

static void lisp_auto_local_bindings_inline(void) {
  // A `let` expands to an immediately applied lambda literal. Lowering
  // binds its values in slots of the frame it stands in, so the body costs
  // no call and no frame of its own.
  Lisp lisp = Lisp.new();
  _ev(lisp, "(defun sum3 (a) (let ((b (+ a 1)) (c (+ a 2))) (+ b c)))");
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(sum3 10)")), 23);
  EXPECT_TRUE(lisp.auto_stats().machine_entries > 0);
  EXPECT_INT_EQ((int) lisp.auto_stats().inlined_scopes, 1);
  EXPECT_INT_EQ((int) lisp.auto_stats().inline_declines, 0);
  lisp.destroy();
}

static void lisp_auto_local_binding_is_lexical(void) {
  // `read-x` reads the global `x` wherever it is called from: a `let` in the
  // caller binds a name in the caller, not in the callee. A lambda written
  // inside the `let` does read that binding, and keeps the value it was
  // made with.
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(def x 1)");
    _ev(lisp, "(defun read-x () x)");
    _ev(lisp, "(defun local-read (v) (let ((x v)) (read-x)))");
    _ev(lisp, "(defun local-closure (v) (let ((x v)) (lambda () (+ x 0))))");
    for (int i = 0; i < 3; i++) {
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(local-read 9)")), 1);
      _ev(lisp, "(def saved (local-closure 11))");
      _ev(lisp, "(local-closure 22)");
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(saved)")), 11);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-x)")), 1);
    }
    lisp.destroy();
  }
}

static void lisp_auto_local_match_and_redefinition(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(defun pick (e) (match-case e ((tag ?v) ?v) (else 0)))");
    _ev(lisp, "(defun local (v) (let ((x v)) x))");
    for (int i = 0; i < 3; i++) {
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick '(tag 7))")), 7);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick '(other 7))")), 0);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(local 8)")), 8);
    }
    MachineView view;
    int nparam;
    Var body;
    EXPECT_INT_EQ(Lisp.program(_ev(lisp, "pick"),
                              &view, &nparam, &body), !disabled);
    _ev(lisp, "(defmacro match-case (e . cases) 31)");
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick '(tag 7))")), 31);
    _ev(lisp, "(defmacro let (bindings body) 41)");
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(local 8)")), 41);
    lisp.destroy();
  }
}

static void lisp_auto_immediate_constructor_rebinding(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = _auto_session(1);
    lisp.auto_disable(disabled);
    _ev(lisp, "(def replacement (lambda (x) (add x 100)))");
    _ev(lisp, "(def constructor (macro (params body) 'replacement))");
    _ev(lisp, "(def change (lambda (flag)"
              " (cond (flag (def lambda constructor)) (1 ()))))");
    _ev(lisp, "(def run (lambda (flag)"
              " ((lambda (ignored) ((lambda (x) x) (log! 7)))"
              " (change flag))))");
    auto_order_log[0] = 0;
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(run ())")), 7);
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(run ())")), 7);
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(run 1)")), 107);
    EXPECT_STR_EQ(String.new(auto_order_log), "777");
    lisp.destroy();
  }
}

static void lisp_auto_immediate_effects_and_fallback(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = _auto_session(1);
    lisp.auto_disable(disabled);
    _ev(lisp, "(def ordered (lambda ()"
              " ((lambda (a b) b) (log! 1) (log! 2))))");
    _ev(lisp, "(def dotted (lambda ()"
              " ((lambda (x . rest) x) (log! 3) (log! 4))))");
    _ev(lisp, "(def wrong-arity (lambda ()"
              " ((lambda (x) x) (log! 5) (log! 6))))");
    _ev(lisp, "(def malformed (lambda () ((lambda 1 2) (log! 7))))");
    for (int i = 0; i < 3; i++) {
      auto_order_log[0] = 0;
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(ordered)")), 2);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(dotted)")), 3);
      EXPECT_INT_EQ(_raised(lisp, "(wrong-arity)"), <bad-arity>);
      EXPECT_INT_EQ(_raised(lisp, "(malformed)"), <bad-sig>);
      EXPECT_STR_EQ(String.new(auto_order_log), "123456");
    }
    lisp.destroy();
  }
}

static void lisp_auto_macro_is_lexical(void) {
  // A macro body is a lambda body: its free names read the globals it was
  // written next to, whatever the caller happens to bind. A macro that needs
  // the caller's value takes it as an argument.
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(def y 1)");
    _ev(lisp, "(defmacro get-y () (list 'quote y))");
    _ev(lisp, "(defun quoted-y () (list 'quote y))");
    _ev(lisp, "(defmacro helper-y () (quoted-y))");
    _ev(lisp, "(defmacro captured-y ()"
              " ((lambda () (list 'quote y))))");
    _ev(lisp, "(defmacro quote-it (v) (list 'quote v))");
    _ev(lisp, "(defun direct (v) (let ((y v)) (get-y)))");
    _ev(lisp, "(defun indirect (v) (let ((y v)) (helper-y)))");
    _ev(lisp, "(defun captured (v) (let ((y v)) (captured-y)))");
    _ev(lisp, "(defun passed () (quote-it 7))");
    for (int i = 0; i < 3; i++) {
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(direct 7)")), 1);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(indirect 9)")), 1);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(captured 8)")), 1);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(passed)")), 7);
    }
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(get-y)")), 1);
    lisp.destroy();
  }
}

static void lisp_auto_local_macro_effects_once(void) {
  // A macro body with an effect runs once per call, whether the call runs
  // on the machine or through the evaluator. Its free `y` is the global.
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(def count 0)");
    _ev(lisp, "(def y 1)");
    _ev(lisp, "(defmacro get-y ()"
              " (cond ((def count (+ count 1)) (list 'quote y))))");
    _ev(lisp, "(defun local-effect () (let ((y 42)) (get-y)))");
    for (int i = 0; i < 4; i++) {
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(local-effect)")), 1);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "count")), i + 1);
    }
    lisp.destroy();
  }
}

static void lisp_auto_macro_native_effects(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = _auto_session(1);
    lisp.auto_disable(disabled);
    _ev(lisp, "(def direct (macro () (cond ((log! 1) 42))))");
    _ev(lisp, "(def indirect (macro ()"
              " (cond ((apply log! '(2)) 42))))");
    _ev(lisp, "(def run (lambda ()"
              " ((lambda (a b) b) (direct) (indirect))))");
    for (int i = 0; i < 4; i++) {
      auto_order_log[0] = 0;
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(run)")), 42);
      EXPECT_STR_EQ(String.new(auto_order_log), "12");
    }
    lisp.destroy();
  }
}

static void lisp_auto_macro_unchosen_effects(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = _auto_session(1);
    lisp.auto_disable(disabled);
    _ev(lisp, "(def effect (macro () (cond ((log! 1) 42))))");
    _ev(lisp, "(def choose (lambda (flag)"
              " ((lambda (x) (cond (flag (effect)) (1 x))) 7)))");
    _ev(lisp, "(def forever (macro () (forever)))");
    _ev(lisp, "(def skip (lambda (flag)"
              " (cond (flag (forever)) (1 9))))");
    auto_order_log[0] = 0;
    for (int i = 0; i < 4; i++) {
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(choose ())")), 7);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(skip ())")), 9);
    }
    EXPECT_INT_EQ(auto_order_log[0], 0);
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(choose 1)")), 42);
    EXPECT_STR_EQ(String.new(auto_order_log), "1");
    lisp.destroy();
  }
}

static void lisp_auto_macro_global_data(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(def version 10)");
    _ev(lisp, "(defmacro versioned () (list 'quote version))");
    _ev(lisp, "(defun read-version (ignored)"
              " (let ((x 42)) (versioned)))");
    _ev(lisp, "(defun read-after-change () (versioned))");
    _ev(lisp, "(defun change-version (flag)"
              " (cond (flag (def version 30)) (1 1)))");
    _ev(lisp, "(defun change-then-read (flag)"
              " (cond ((change-version flag) (versioned))))");
    for (int i = 0; i < 3; i++) {
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-version ())")), 10);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-after-change)")), 10);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(change-then-read ())")), 10);
    }
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(change-then-read 1)")), 30);
    _ev(lisp, "(def version 10)");
    EXPECT_INT_EQ(Var.integer(_ev(lisp,
                  "(read-version (def version 40))")), 40);
    _ev(lisp, "(def version 20)");
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-after-change)")), 20);
    lisp.destroy();
  }
}

static void lisp_auto_macro_helper_rebinding(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(defun expansion-value () 10)");
    _ev(lisp, "(def original-helper expansion-value)");
    _ev(lisp, "(defmacro from-helper ()"
              " (list 'quote (expansion-value)))");
    _ev(lisp, "(defun read-helper (ignored)"
              " (let ((x 42)) (from-helper)))");
    _ev(lisp, "(defun read-rebound-helper () (from-helper))");
    _ev(lisp, "(defun change-helper (flag)"
              " (cond (flag (def expansion-value (lambda () 30)))"
              " (1 1)))");
    _ev(lisp, "(defun change-then-expand (flag)"
              " (cond ((change-helper flag) (from-helper))))");
    for (int i = 0; i < 3; i++) {
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-helper ())")), 10);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-rebound-helper)")), 10);
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(change-then-expand ())")), 10);
    }
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(change-then-expand 1)")), 30);
    _ev(lisp, "(def expansion-value original-helper)");
    EXPECT_INT_EQ(Var.integer(_ev(lisp,
                  "(read-helper (def expansion-value (lambda () 40)))")),
                  40);
    _ev(lisp, "(defun expansion-value () 20)");
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(read-rebound-helper)")), 20);
    lisp.destroy();
  }
}

static void lisp_auto_macro_fresh_closure(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(defmacro fresh () (list 'quote (lambda () 7)))");
    _ev(lisp, "(defun make-fresh () (let ((x 42)) (fresh)))");
    Var previous = _ev(lisp, "(make-fresh)");
    for (int i = 0; i < 4; i++) {
      Var current = _ev(lisp, "(make-fresh)");
      EXPECT_TRUE(current != previous);
      EXPECT_INT_EQ(Var.integer(lisp.apply(current, %())), 7);
      previous = current;
    }
    lisp.destroy();
  }
}

static void lisp_auto_declined_form_releases_programs(void) {
  // Both unchosen arms decline on call width and rewind to one interpreted
  // word, so both lambdas publish the same program shape. Only the second
  // emitted an immediate lambda first; its child program must not survive the
  // rewind, or the second lambda would cost more.
  Lisp lisp = Lisp.kernel();
  _ev(lisp, "(def control (lambda (flag) (cond (flag 1)"
            " (1 (nine 1 2 3 4 5 6 7 8 9)))))");
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(control 7)")), 1);
  long one = lisp.auto_stats().program_bytes;
  EXPECT_TRUE(one > 0);

  _ev(lisp, "(def wide (lambda (flag) (cond (flag 1)"
            " (1 ((lambda (a b c d e f g h) a) 1 2 3 4 5 6 7 8 9)))))");
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(wide 7)")), 1);
  LispAutoStats after = lisp.auto_stats();
  EXPECT_TRUE(after.machine_entries > 0);
  EXPECT_INT_EQ((int) after.ineligible, 0);
  EXPECT_INT_EQ(after.program_bytes, 2 * one);
  lisp.destroy();
}

static void lisp_auto_mutating_specials(void) {
  const char *names[] = { "quote", "cond", "quasiquote" };
  const char *forms[] = { "(quote 7)", "(cond (1 7))",
                          "(quasiquote (7))" };
  for (int special = 0; special < 3; special++)
    for (int lane = 0; lane < 3; lane++)
      for (int disabled = 0; disabled < 2; disabled++) {
        Lisp lisp = _auto_session(1);
        lisp.auto_disable(disabled);
        String name = String.new(names[special]);
        String form = String.new(forms[special]);
        _ev(lisp, "(def replacement (macro (x) 99))");
        if (!lane) {
          _ev(lisp, "(def f (lambda (flag) (cond (flag " +
                    %"(cond ((log! 1) (cond ((def ${name} replacement) " +
                    %"${form}))))) (1 0))))");
          _ev(lisp, "(f ())");
          auto_order_log[0] = 0;
          EXPECT_INT_EQ(Var.integer(_ev(lisp, "(f 1)")), 99);
        }
        else {
          _ev(lisp, %"(def f (lambda (x) ${form}))");
          _ev(lisp, "(f 0)");
          String call = "(f (cond ((log! 1) " +
                         %"(def ${name} replacement))))";
          if (lane == 2) {
            _ev(lisp, "(def caller (lambda (flag) " +
                      %"(cond (flag ${call}) (1 0))))");
            _ev(lisp, "(caller ())");
            call = "(caller 1)";
          }
          auto_order_log[0] = 0;
          EXPECT_INT_EQ(Var.integer(_ev(lisp, call)), 99);
        }
        EXPECT_STR_EQ(String.new(auto_order_log), "1");
        lisp.destroy();
      }
}

static void lisp_auto_quasiquote_effect_order(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.kernel();
    lisp.auto_disable(disabled);
    _ev(lisp, "(def replacement (macro (x) 99))");
    _ev(lisp, "(def f (lambda (flag) (cond (flag (quasiquote "
              "((unquote (cond ((def quasiquote replacement) 5))) 7)))"
              " (1 0))))");
    _ev(lisp, "(f ())");
    EXPECT_TRUE(_ev(lisp, "(f 1)") == %(5 7));
    lisp.destroy();

    lisp = Lisp.kernel();
    lisp.auto_disable(disabled);
    _ev(lisp, "(def replacement (macro (x) 99))");
    _ev(lisp, "(def f (lambda (flag) (cond (flag (quasiquote "
              "((unquote (cond ((def quote replacement) 5))) "
              "(unquote (quote 7))))) (1 0))))");
    _ev(lisp, "(f ())");
    EXPECT_TRUE(_ev(lisp, "(f 1)") == %(5 99));
    lisp.destroy();

    lisp = Lisp.kernel();
    lisp.auto_disable(disabled);
    _ev(lisp, "(def f (lambda (x) "
              "(quasiquote ((unquote-splicing x)))))");
    _ev(lisp, "(f ())");
    Var original = _ev(lisp, "(def xs (quote (1 2 3)))");
    EXPECT_TRUE(_ev(lisp, "(f xs)").u64 == original.u64);
    EXPECT_TRUE(_ev(lisp, "(f ())").is_nil());
    lisp.destroy();

    lisp = Lisp.kernel();
    lisp.auto_disable(disabled);
    _ev(lisp, "(def side 0) (def f (lambda (flag) (cond (flag "
              "(quasiquote ((unquote-splicing 7) "
              "(unquote (def side 1))))) (1 0))))");
    _ev(lisp, "(f ())");
    EXPECT_INT_EQ(_raised(lisp, "(f 1)"), <bad-types>);
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "side")), 0);
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(f ())")), 0);
    lisp.destroy();
  }
}

static void lisp_auto_mutating_tail_recursion(void) {
  Lisp lisp = Lisp.new();
  MachineStats stats = {};
  lisp.auto_instrument(&stats);
  _ev(lisp, "(defun cd (n) "
            "(cond ((= n 0) 7) ((def seen n) (cd (- n 1)))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(cd 100000)")), 7);
  EXPECT_INT_EQ(stats.max_frames, 1);
  lisp.destroy();
}

static void lisp_auto_local_recursion_capacity(void) {
  for (int disabled = 0; disabled < 2; disabled++) {
    Lisp lisp = Lisp.new();
    lisp.auto_disable(disabled);
    _ev(lisp, "(defun count-local (n)"
              " (let ((saved n))"
              " (if (= saved 0) 0 (+ 1 (count-local (- saved 1))))))");
    for (int i = 0; i < 3; i++)
      EXPECT_INT_EQ(Var.integer(_ev(lisp, "(count-local 140)")), 140);
    lisp.destroy();
  }
}

$(import "test-macros.xmacro")

void lisp_auto_suite(void) {
  $test.run(lisp_auto_second_call_transition);
  $test.run(lisp_auto_nil_path);
  $test.run(lisp_auto_replacement_guards);
  $test.run(lisp_auto_cond_identity_guard);
  $test.run(lisp_auto_error_paths);
  $test.run(lisp_auto_recursion_and_effects);
  $test.run(lisp_auto_rest_and_macro_preparation);
  $test.run(lisp_auto_quasiquote);
  $test.run(lisp_auto_macro_calls);
  $test.run(lisp_auto_quasiquote_capacity);
  $test.run(lisp_auto_session_isolation);
  $test.run(lisp_auto_caller_binding_is_invisible);
  $test.run(lisp_auto_expands_macro_heads);
  $test.run(lisp_auto_macro_rebinding_guard);
  $test.run(lisp_auto_tail_calls_stay_flat);
  $test.run(lisp_auto_tail_call_to_another);
  $test.run(lisp_auto_forced_evaluator_arm);
  $test.run(lisp_auto_local_bindings);
  $test.run(lisp_auto_local_bindings_inline);
  $test.run(lisp_auto_local_binding_is_lexical);
  $test.run(lisp_auto_local_match_and_redefinition);
  $test.run(lisp_auto_immediate_constructor_rebinding);
  $test.run(lisp_auto_immediate_effects_and_fallback);
  $test.run(lisp_auto_macro_is_lexical);
  $test.run(lisp_auto_local_macro_effects_once);
  $test.run(lisp_auto_macro_native_effects);
  $test.run(lisp_auto_macro_unchosen_effects);
  $test.run(lisp_auto_macro_global_data);
  $test.run(lisp_auto_macro_helper_rebinding);
  $test.run(lisp_auto_macro_fresh_closure);
  $test.run(lisp_auto_declined_form_releases_programs);
  $test.run(lisp_auto_local_recursion_capacity);
  $test.run(lisp_auto_mutating_specials);
  $test.run(lisp_auto_quasiquote_effect_order);
  $test.run(lisp_auto_mutating_tail_recursion);
}
