/*  test-lisp-auto.x -- production second-call AUTO at the _apply hook

    The complete L1-L12 matrix against the real private boundary:
    ordinary public evaluation, no fixture dispatcher.  The recursive
    evaluator remains the semantic oracle; every row checks results,
    exact raised errors, hook telemetry, and machine counters where the
    frozen matrix pinned them.  The added shadowing rows pin the
    production-only guard: a name that the evaluator would resolve
    dynamically through the caller chain declines to the evaluator
    before any effect. */

#include "test-support.x"

static long auto_add_calls;
static long auto_mult_calls;
static char auto_order_log[64];

static Var _auto_native_add(Var a, Var b) {
  auto_add_calls++;
  return Var.binary(a, <+>, b);
}

static Var _auto_native_add100(Var a, Var b) {
  return Var.binary(Var.binary(a, <+>, b), <+>, Var.new(<i32>, 100));
}

static Var _auto_native_mult(Var a, Var b) {
  auto_mult_calls++;
  return Var.binary(a, <"*">, b);
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
  return Lisp.eval_string(lisp, String.new(text));
}

static Symbol _raised(Lisp lisp, const char *text) {
  Symbol code = 0;
  try _ev(lisp, text);
  catch %(bad-arity *): code = <bad-arity>;
  catch %(bad-types *): code = <bad-types>;
  catch %(not-call *): code = <not-call>;
  catch %(unbound *): code = <unbound>;
  return code;
}

static Lisp _auto_session(int with_add) {
  Lisp lisp = Lisp.new_bare();
  if (with_add)
    Lisp.set_global(lisp, "add",
                    Func.var(_make_func(
                                        _auto_native_add,
                                        _binary_signature())));
  Lisp.set_global(lisp, "log!",
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
  Lisp.auto_instrument(lisp, &mstats);
  LispAutoStats before = Lisp.auto_stats(lisp);

  // L1: EVAL -> AUTO -> PREPARED, all 12.
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats first = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (first.machine_entries - before.machine_entries), 0);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats second = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (second.machine_entries - before.machine_entries), 2);
  EXPECT_INT_EQ((int) (second.published - before.published), 2);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats third = Lisp.auto_stats(lisp);
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
  EXPECT_INT_EQ((int) mstats.lisp_returns, 4);
  Lisp.destroy(lisp);
}

static void lisp_auto_nil_path(void) {
  // L2: the nil arm publishes the same programs but calls nothing.
  Lisp lisp = _auto_session(1);
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  Lisp.auto_instrument(lisp, &mstats);
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
  EXPECT_INT_EQ((int) Lisp.auto_stats(lisp).published, 1);

  // L3: captures outlive the maker frame by construction; numeric
  // zero is not nil and takes the hit arm.
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 0)")), 5);
  Lisp.destroy(lisp);
}

static void lisp_auto_replacement_guards(void) {
  Lisp lisp = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats warmed = Lisp.auto_stats(lisp);

  // L4: replacing the native add is visible immediately through the
  // late lookup, with no reanalysis and no republication.
  Var original = void;
  EXPECT_TRUE(Lisp.try_get(lisp, "add", &original));
  Lisp.set_global(lisp, "add",
                  Func.var(_make_func(
                                      _auto_native_add100,
                                      _binary_signature())));
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 112);
  Lisp.set_global(lisp, "add", original);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats after = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (after.published - warmed.published), 0);
  EXPECT_INT_EQ((int) (after.analyses - warmed.analyses), 0);

  // L5: a helper replacement starts a fresh threshold, as does a
  // brancher replacement.
  _ev(lisp, "(def helper (lambda (x bias) (add (add x bias) 1)))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 13);
  after = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (after.published - warmed.published), 0);
  LispAutoStats base = after;
  _ev(lisp, "(def brancher (lambda (x) (add x 20)))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 27);
  EXPECT_INT_EQ((int) (Lisp.auto_stats(lisp).machine_entries -
                       base.machine_entries), 0);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 27);
  EXPECT_INT_EQ((int) (Lisp.auto_stats(lisp).machine_entries -
                       base.machine_entries), 1);

  // L6: a native helper replacement crosses the one callable service
  // directly: no add call, no prepared child call.
  Lisp fresh = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(fresh, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(fresh, "(brancher 7)")), 12);
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  Lisp.auto_instrument(fresh, &mstats);
  Lisp.set_global(fresh, "helper",
                  Func.var(_make_func(
                                      _auto_native_mult,
                                      _binary_signature())));
  long adds = auto_add_calls;
  EXPECT_INT_EQ(Var.integer(_ev(fresh, "(brancher 7)")), 35);
  EXPECT_INT_EQ((int) (auto_add_calls - adds), 0);
  EXPECT_INT_EQ((int) mstats.prepared_calls, 0);
  EXPECT_INT_EQ((int) mstats.native_calls, 1);
  Lisp.destroy(fresh);
  Lisp.destroy(lisp);
}

static void lisp_auto_cond_identity_guard(void) {
  // L7/L8: shadowing the reserved cond fails the guard before any
  // effect; restoring the exact identity resumes prepared execution.
  Lisp lisp = _auto_session(1);
  Var reserved = _ev(lisp, "cond");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats warmed = Lisp.auto_stats(lisp);
  long adds = auto_add_calls;
  _ev(lisp, "(def cond 99)");
  EXPECT_INT_EQ(_raised(lisp, "(brancher 7)"), <not-call>);
  LispAutoStats blocked = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (blocked.machine_entries - warmed.machine_entries), 0);
  EXPECT_TRUE(blocked.guard_failures > warmed.guard_failures);
  EXPECT_INT_EQ((int) (auto_add_calls - adds), 0);
  Lisp.set_global(lisp, "cond", reserved);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ((int) (Lisp.auto_stats(lisp).machine_entries -
                       warmed.machine_entries), 1);
  Lisp.destroy(lisp);
}

static void lisp_auto_error_paths(void) {
  // L9a: an unbound native reports the same error from interpreted and
  // prepared execution.
  Lisp missing = _auto_session(0);
  EXPECT_INT_EQ(_raised(missing, "(brancher 7)"), <unbound>);
  EXPECT_INT_EQ(_raised(missing, "(brancher 7)"), <unbound>);
  EXPECT_INT_EQ(_raised(missing, "(brancher 7)"), <unbound>);
  Lisp.destroy(missing);

  // L9b: a non-callable helper replacement fails inside the prepared
  // caller without replaying it.
  Lisp lisp = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  LispAutoStats warmed = Lisp.auto_stats(lisp);
  _ev(lisp, "(def helper 42)");
  EXPECT_INT_EQ(_raised(lisp, "(brancher 7)"), <not-call>);
  EXPECT_INT_EQ((int) (Lisp.auto_stats(lisp).machine_entries -
                       warmed.machine_entries), 1);

  // Argument-count mismatches decline so the evaluator owns the
  // exact apply-args error.
  EXPECT_INT_EQ(_raised(lisp, "(brancher 1 2)"), <bad-arity>);
  Lisp.destroy(lisp);
}

static void lisp_auto_recursion_and_effects(void) {
  // L10: recursive prepared frames restore caller state exactly.
  Lisp lisp = _auto_session(1);
  _ev(lisp,
      "(def helper (lambda (x bias) (cond (x (helper () (add x bias))) (1 bias))))");
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  Lisp.auto_instrument(lisp, &mstats);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ((int) mstats.prepared_calls, 2);
  EXPECT_INT_EQ((int) mstats.native_calls, 1);
  // Three returns, not four: helper's recursive call is in tail position
  // and reuses its own frame.
  EXPECT_INT_EQ((int) mstats.lisp_returns, 3);

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
  Lisp.destroy(lisp);
}

static void lisp_auto_rest_and_macro_preparation(void) {
  // L11: rest parameters remain interpreted; macros prepare normally.
  Lisp lisp = _auto_session(1);
  _ev(lisp, "(def resty (lambda (x . r) x))");
  _ev(lisp, "(def identity-m (macro (x) x))");
  LispAutoStats before = Lisp.auto_stats(lisp);
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(resty 3 4)")), 3);
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(identity-m 9)")), 9);
  LispAutoStats after = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (after.analyses - before.analyses), 2);
  EXPECT_INT_EQ((int) (after.ineligible - before.ineligible), 1);
  EXPECT_INT_EQ((int) (after.published - before.published), 1);
  EXPECT_INT_EQ((int) (after.remembered_fallbacks -
                       before.remembered_fallbacks), 1);
  EXPECT_INT_EQ((int) (after.machine_entries - before.machine_entries), 2);
  Lisp.destroy(lisp);
}

static void lisp_auto_quasiquote(void) {
  Lisp lisp = _auto_session(1);
  _ev(lisp, "(def qq (lambda (x xs) `(1 ,(add x 1) ,@xs)))");
  LispAutoStats before = Lisp.auto_stats(lisp);
  Var interpreted = _ev(lisp, "(qq 2 '(4 5))");
  EXPECT_VAR_EQ(interpreted, _ev(lisp, "'(1 3 4 5)"));
  EXPECT_VAR_EQ(_ev(lisp, "(qq 2 '(4 5))"), interpreted);
  EXPECT_INT_EQ((int) (Lisp.auto_stats(lisp).machine_entries -
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
  Lisp.destroy(lisp);
}

static void lisp_auto_macro_calls(void) {
  Lisp lisp = _auto_session(1);
  _ev(lisp, "(def twice (macro (e) `(add ,e ,e)))");
  _ev(lisp, "(def call-twice (lambda (x) (twice (log! x))))");
  auto_order_log[0] = 0;
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(call-twice 7)")), 14);
  LispAutoStats warmed = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(call-twice 8)")), 16);
  LispAutoStats prepared = Lisp.auto_stats(lisp);
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
  // Redefining the macro invalidates the expansion it was compiled from,
  // so the caller answers from the evaluator instead.
  _ev(lisp, "(def plus-n (macro (e) `(add ,e 10)))");
  LispAutoStats stale = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(use-plus-n 2)")), 12);
  LispAutoStats after = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (after.machine_entries - stale.machine_entries), 0);
  EXPECT_TRUE(after.guard_failures > stale.guard_failures);
  Lisp.destroy(lisp);
}

static void lisp_auto_quasiquote_capacity(void) {
  Lisp lisp = _auto_session(1);
  Buffer source = Buffer.new(0);
  source.write("(def deep-qq (lambda (x) `(");
  for (int i = 0; i < 250; i++) source.write("0 ");
  source.write(",x)))");
  _ev(lisp, source.str_free());
  LispAutoStats before = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) Var.list(_ev(lisp, "(deep-qq 7)")).len(), 251);
  EXPECT_INT_EQ((int) Var.list(_ev(lisp, "(deep-qq 7)")).len(), 251);
  LispAutoStats after = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (after.machine_entries - before.machine_entries), 0);
  EXPECT_INT_EQ((int) (after.ineligible - before.ineligible), 1);
  Lisp.destroy(lisp);
}

static void lisp_auto_session_isolation(void) {
  // L12: generations of state are per-Lambda, so sessions cannot
  // observe each other even across allocator reuse.
  Lisp a = _auto_session(1), b = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(a, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(a, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(b, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(b, "(brancher 7)")), 12);
  Lisp.set_global(a, "add",
                  Func.var(_make_func(
                                      _auto_native_add100,
                                      _binary_signature())));
  EXPECT_INT_EQ(Var.integer(_ev(a, "(brancher 7)")), 112);
  EXPECT_INT_EQ(Var.integer(_ev(b, "(brancher 7)")), 12);
  Lisp.destroy(a);
  Lisp c = _auto_session(1);
  EXPECT_INT_EQ(Var.integer(_ev(c, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(c, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(b, "(brancher 7)")), 12);
  Lisp.destroy(c);
  Lisp.destroy(b);
}

static void lisp_auto_caller_shadowing_declines(void) {
  // Production-only guard: the evaluator resolves free names through
  // the caller chain, so a caller parameter shadowing a guarded name
  // must decline before effects — on every call, not just the first.
  Lisp lisp = _auto_session(1);
  _ev(lisp, "(def wrapper (lambda (add) (brancher 7)))");
  EXPECT_INT_EQ(_raised(lisp, "(wrapper 99)"), <not-call>);
  EXPECT_INT_EQ(_raised(lisp, "(wrapper 99)"), <not-call>);
  EXPECT_INT_EQ(_raised(lisp, "(wrapper 99)"), <not-call>);

  // The same call through a non-shadowing wrapper stays prepared.
  _ev(lisp, "(def clean (lambda (unused) (brancher 7)))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(clean 1)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(clean 1)")), 12);
  EXPECT_TRUE(Lisp.auto_stats(lisp).machine_entries > 0);
  Lisp.destroy(lisp);
}

static void lisp_auto_expands_macro_heads(void) {
  // `if` is a macro, so until analysis expanded macro heads every
  // recursive call left the machine for the evaluator: the standard
  // library made the compiled path almost unreachable.
  Lisp lisp = Lisp.new();
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  Lisp.auto_instrument(lisp, &mstats);
  LispAutoStats before = Lisp.auto_stats(lisp);
  _ev(lisp, "(defun cd (n a) (if (= n 0) a (cd (- n 1) (+ a 1))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(cd 40 0)")), 40);
  EXPECT_TRUE(mstats.prepared_calls > 0);
  EXPECT_INT_EQ((int) (Lisp.auto_stats(lisp).guard_failures -
                       before.guard_failures), 0);
  Lisp.destroy(lisp);
}

static void lisp_auto_macro_rebinding_guard(void) {
  // A program built from an expansion is valid only while the macro it
  // expanded still means the same thing.
  Lisp lisp = Lisp.new();
  _ev(lisp, "(defun pick (a b) (if a a b))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick 1 2)")), 1);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick 1 2)")), 1);
  EXPECT_TRUE(Lisp.auto_stats(lisp).machine_entries > 0);

  // Swapping the arms of `if` must reach a program compiled before the
  // swap: the stale program would still answer 1.
  _ev(lisp, "(defmacro if (c x y) `(cond (,c ,y) (true ,x)))");
  LispAutoStats warmed = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(pick 1 2)")), 2);
  LispAutoStats blocked = Lisp.auto_stats(lisp);
  EXPECT_INT_EQ((int) (blocked.machine_entries - warmed.machine_entries), 0);
  EXPECT_TRUE(blocked.guard_failures > warmed.guard_failures);
  Lisp.destroy(lisp);
}

static void lisp_auto_tail_calls_stay_flat(void) {
  // A lambda calling itself in tail position reuses the frame it is
  // standing in, so depth far past MACHINE_FRAME_MAX costs one frame.
  Lisp lisp = Lisp.new();
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  Lisp.auto_instrument(lisp, &mstats);
  _ev(lisp, "(defun cd (n a) (if (= n 0) a (cd (- n 1) (+ a 1))))");
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(cd 4000 0)")), 4000);
  EXPECT_INT_EQ(mstats.max_frames, 1);
  EXPECT_TRUE(mstats.prepared_calls > 3000);

  // The self-call is noted like any other identity the program was built
  // against, so rebinding the name that named it declines to the
  // evaluator instead of tail-calling a callee that is no longer there.
  _ev(lisp, "(def old cd)");
  _ev(lisp, "(def cd 5)");
  EXPECT_INT_EQ(_raised(lisp, "(old 3 0)"), <not-call>);
  Lisp.destroy(lisp);
}

static void lisp_auto_tail_call_only_to_self(void) {
  // A tail call to a different lambda still stacks a frame. Dropping the
  // caller's would drop its locals out of free-name lookup, which the
  // evaluator keeps: `leaf` reads the caller's `x`, not the global.
  Lisp lisp = Lisp.new();
  MachineStats mstats;
  memset(&mstats, 0, sizeof(mstats));
  Lisp.auto_instrument(lisp, &mstats);
  _ev(lisp, "(def x 1)");
  _ev(lisp, "(defun leaf () x)");
  _ev(lisp, "(defun mid (x) (leaf))");
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(mid 99)")), 99);
  EXPECT_TRUE(mstats.max_frames > 1);
  Lisp.destroy(lisp);
}

static void lisp_auto_forced_evaluator_arm(void) {
  // The benchmark's forced-evaluator control: identical results with
  // zero machine entries, then re-enabled AUTO resumes.
  Lisp lisp = _auto_session(1);
  Lisp.auto_disable(lisp, 1);
  for (int i = 0; i < 3; i++)
    EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ((int) Lisp.auto_stats(lisp).machine_entries, 0);
  Lisp.auto_disable(lisp, 0);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_INT_EQ(Var.integer(_ev(lisp, "(brancher 7)")), 12);
  EXPECT_TRUE(Lisp.auto_stats(lisp).machine_entries > 0);
  Lisp.destroy(lisp);
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
  $test.run(lisp_auto_caller_shadowing_declines);
  $test.run(lisp_auto_expands_macro_heads);
  $test.run(lisp_auto_macro_rebinding_guard);
  $test.run(lisp_auto_tail_calls_stay_flat);
  $test.run(lisp_auto_tail_call_only_to_self);
  $test.run(lisp_auto_forced_evaluator_arm);
}
