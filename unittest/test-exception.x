/*  test-exception.x -- unit tests for Error transfer and cleanup frames */

#include "test-support.x"

static int _exception_try_return_helper(int value) {
  try {
    if (value == 42) return value;
  }
  catch %(invariant): return -1;
  return 0;
}

static int _exception_nested_finally_helper(int *inner, int *outer) {
  try {
    try {
      return 7;
    }
    finally {
      (*inner)++;
    }
  }
  finally {
    (*outer)++;
  }
  return -1;
}

static int _exception_bubble_callee(volatile int *final_hits) {
  try {
    raise %(invariant (value 99));
  }
  finally {
    if (final_hits) (*final_hits)++;
  }
  return 0;
}

static void exception_try_cleanup_on_return(void) {
  ExceptionFrame base;
  x2c_exception_push(&base);
  ExceptionFrame *baseline = base.prev;
  x2c_exception_leave(&base);

  int result = _exception_try_return_helper(42);
  EXPECT_INT_EQ(result, 42);

  ExceptionFrame probe;
  x2c_exception_push(&probe);
  int leaked = probe.prev != baseline;
  x2c_exception_leave(&probe);
  EXPECT_FALSE(leaked);
}

static void exception_try_cleanup_on_loop_control(void) {
  ExceptionFrame base;
  x2c_exception_push(&base);
  ExceptionFrame *baseline = base.prev;
  x2c_exception_leave(&base);

  int iterations = 0, final_hits = 0;
  while (iterations < 3) {
    try {
      iterations++;
      if (iterations == 1) continue;
      break;
    }
    finally {
      final_hits++;
    }
  }

  EXPECT_INT_EQ(iterations, 2);
  EXPECT_INT_EQ(final_hits, 2);

  ExceptionFrame probe;
  x2c_exception_push(&probe);
  int leaked = probe.prev != baseline;
  x2c_exception_leave(&probe);
  EXPECT_FALSE(leaked);
}

static void exception_finally_runs_on_success(void) {
  int counter = 0;
  try {
    counter = 1;
  }
  finally {
    counter += 41;
  }
  EXPECT_INT_EQ(counter, 42);
}

static void exception_normal_exit_preserves_collected_errors(void) {
  Error.initialize();
  Error.policy_set(<old-error>, <collect>);
  int mark = Error.mark(), cleanup = 0;
  try {
    Error.raise(<old-error>, %((where "normal try")));
  }
  finally {
    cleanup++;
  }
  EXPECT_INT_EQ(cleanup, 1);
  EXPECT_INT_EQ(Error.count(), mark + 1);
}

static void exception_finally_runs_on_exception(void) {
  Error.initialize();
  int cleanup = 0, handled = 0;
  try {
    try {
      raise %(invariant);
    }
    finally {
      cleanup = 1;
    }
  }
  catch %(invariant): handled = 1;
  EXPECT_TRUE(handled);
  EXPECT_INT_EQ(cleanup, 1);
}

static void exception_finally_with_catch(void) {
  Error.initialize();
  int cleanup = 0, payload_seen = 0;
  try {
    raise %(invariant (value 7));
  }
  catch %(invariant (value ?value)): {
    payload_seen = value;
  }
  finally {
    cleanup = 1;
  }
  EXPECT_INT_EQ(payload_seen, 7);
  EXPECT_INT_EQ(cleanup, 1);
}

static void exception_nested_finally_runs_once(void) {
  int inner = 0;
  int outer = 0;
  int result = _exception_nested_finally_helper(&inner, &outer);
  EXPECT_INT_EQ(result, 7);
  EXPECT_INT_EQ(inner, 1);
  EXPECT_INT_EQ(outer, 1);
}

static void exception_bubbles_across_frames(void) {
  Error.initialize();
  volatile int final_hits = 0;
  int payload_seen = 0;
  try {
    _exception_bubble_callee(&final_hits);
  }
  catch %(invariant (value ?value)): {
    payload_seen = value;
  }
  EXPECT_INT_EQ(final_hits, 1);
  EXPECT_INT_EQ(payload_seen, 99);
}


static void error_unwind_selects_target_and_bindings(void) {
  Error.initialize();
  ExceptionFrame frame;
  List pattern = %(invariant (bytes ?count));
  ErrorHandler handler = x2c_error_catch_push(&frame, 1, pattern.var());
  x2c_exception_push(&frame);
  if (!sigsetjmp(frame.env, 0)) {
    Error.raise(<invariant>, %((bytes 42)));
    EXPECT_TRUE(0);
  }
  else {
    x2c_exception_landed(&frame);
    EXPECT_TRUE(x2c_exception_is_error_target(&frame));
    EXPECT_INT_EQ(x2c_error_catch_selected(handler), 0);
    EXPECT_INT_EQ(x2c_error_catch_capture(handler, 0).integer(), 42);
    x2c_error_catch_detach(handler);
    x2c_error_catch_close(handler);
    x2c_exception_mark_handled(&frame);
  }
  x2c_exception_leave(&frame);
}

static void error_unwind_retains_positional_and_legacy_order(void) {
  Error.initialize();
  ExceptionFrame frame;
  List pattern = %(
    !or
    (invariant (left ?first ?shared))
    (invariant (right ?later ?shared))
  );
  ErrorHandler handler = x2c_error_catch_push(&frame, 1, pattern.var());
  x2c_exception_push(&frame);
  if (!sigsetjmp(frame.env, 0)) {
    Error.raise(<invariant>, %((right 41 42)));
    EXPECT_TRUE(0);
  }
  else {
    x2c_exception_landed(&frame);
    EXPECT_INT_EQ(x2c_error_catch_selected(handler), 0);
    EXPECT_TRUE(x2c_error_catch_capture(handler, 0) is void);
    EXPECT_INT_EQ(x2c_error_catch_capture(handler, 2).integer(), 41);
    EXPECT_INT_EQ(x2c_error_catch_capture(handler, 1).integer(), 42);
    x2c_error_catch_detach(handler);
    x2c_error_catch_close(handler);
    x2c_exception_mark_handled(&frame);
  }
  x2c_exception_leave(&frame);
}


static void error_unwind_crosses_each_exception_frame(void) {
  Error.initialize();
  volatile int cleanup = 0;
  ExceptionFrame outer;
  ErrorHandler handler = x2c_error_catch_push(&outer, 1, %(invariant *).var());
  x2c_exception_push(&outer);
  if (!sigsetjmp(outer.env, 0)) {
    ExceptionFrame inner;
    x2c_exception_push(&inner);
    if (!sigsetjmp(inner.env, 0)) {
      Error.raise(<invariant>, %((where "inner")));
      EXPECT_TRUE(0);
    }
    else {
      x2c_exception_landed(&inner);
      EXPECT_TRUE(inner.state == <err-unwind>);
      EXPECT_FALSE(x2c_exception_is_error_target(&inner));
      cleanup++;
      x2c_exception_leave(&inner);
    }
    EXPECT_TRUE(0);
  }
  else {
    x2c_exception_landed(&outer);
    EXPECT_TRUE(x2c_exception_is_error_target(&outer));
    EXPECT_INT_EQ(cleanup, 1);
    x2c_error_catch_detach(handler);
    x2c_error_catch_close(handler);
    x2c_exception_mark_handled(&outer);
  }
  x2c_exception_leave(&outer);
}


static void _cleanup_record_digit(void *data) {
  int *order = data;
  *order = *order * 10 + 1;
}


static void cleanup_chain_leaves_in_lifo_order(void) {
  int order = 0;
  X2CCleanup outer = {
    .fn = _cleanup_record_digit,
    .env = &order
  };
  X2CCleanup inner = {
    .fn = _cleanup_record_digit,
    .env = &order
  };
  x2c_cleanup_push(&outer);
  x2c_cleanup_push(&inner);
  x2c_cleanup_leave(&inner);
  order *= 10;
  x2c_cleanup_leave(&outer);
  EXPECT_INT_EQ(order, 101);
}


static int cleanup_raise_hits;

static void _cleanup_raise(void *data) {
  (void) data;
  cleanup_raise_hits++;
  raise %(invariant);
}


static void cleanup_chain_unlinks_before_callback(void) {
  Error.initialize();
  cleanup_raise_hits = 0;
  int caught = 0;
  try {
    X2CCleanup cleanup = {
      .fn = _cleanup_raise,
      .env = NULL
    };
    x2c_cleanup_push(&cleanup);
    x2c_cleanup_leave(&cleanup);
  }
  catch %(invariant): caught = 1;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(cleanup_raise_hits, 1);
}


static void _cleanup_chain_deep(int *order) {
  defer *order = *order * 10 + 3;
  raise %(invariant);
}


static void _cleanup_chain_middle(int *order) {
  defer *order = *order * 10 + 2;
  _cleanup_chain_deep(order);
}


static void _cleanup_chain_outer(int *order) {
  defer *order = *order * 10 + 1;
  _cleanup_chain_middle(order);
}


static void cleanup_chain_crosses_three_callers(void) {
  Error.initialize();
  int order = 0;
  try {
    _cleanup_chain_outer(&order);
  }
  catch %(invariant): order = order * 10 + 4;
  EXPECT_INT_EQ(order, 3214);
}


static int cleanup_latest_value;

static void _cleanup_chain_latest_value(void) {
  int value = 7;
  defer cleanup_latest_value = value;
  value = 42;
  raise %(invariant);
}


static void cleanup_chain_reads_latest_value_before_jump(void) {
  Error.initialize();
  cleanup_latest_value = 0;
  try {
    _cleanup_chain_latest_value();
  }
  catch %(invariant): {}
  EXPECT_INT_EQ(cleanup_latest_value, 42);
}


static void _cleanup_chain_mixed_frames(int *order) {
  defer *order = *order * 10 + 3;
  try {
    defer *order = *order * 10 + 1;
    raise %(invariant);
  }
  finally {
    *order = *order * 10 + 2;
  }
}


static void cleanup_chain_preserves_intervening_finally(void) {
  Error.initialize();
  int order = 0;
  try {
    _cleanup_chain_mixed_frames(&order);
  }
  catch %(invariant): order = order * 10 + 4;
  EXPECT_INT_EQ(order, 1234);
}


static void _cleanup_chain_contains_handled_try(int *order) {
  defer *order = *order * 10 + 3;
  try {
    raise %(invariant);
  }
  catch %(invariant): *order = *order * 10 + 1;
  *order = *order * 10 + 2;
}


static void cleanup_chain_surrounds_handled_try(void) {
  Error.initialize();
  int order = 0;
  _cleanup_chain_contains_handled_try(&order);
  EXPECT_INT_EQ(order, 123);
}


static void filtered_catch_selects_exact_and_later_arms(void) {
  Error.initialize();
  int selected = 0, count = 0;
  try {
    raise %(alloc-fail (bytes 42) (owner "fixture"));
  }
  catch %(invariant): selected = 1;
  catch %(alloc-fail * (bytes ?bytes) *): {
    selected = 2;
    count = bytes;
  }
  catch: selected = 3;
  EXPECT_INT_EQ(selected, 2);
  EXPECT_INT_EQ(count, 42);
}


static void filtered_catch_selects_default_arm(void) {
  Error.initialize();
  int selected = 0;
  try {
    raise %(invariant);
  }
  catch %(alloc-fail): selected = 1;
  catch: selected = 2;
  EXPECT_INT_EQ(selected, 2);
}


static void filtered_catch_continues_to_outer_registration(void) {
  Error.initialize();
  int inner = 0, outer = 0;
  try {
    try {
      raise %(invariant);
    }
    catch %(alloc-fail): inner = 1;
  }
  catch %(invariant): outer = 1;
  EXPECT_INT_EQ(inner, 0);
  EXPECT_INT_EQ(outer, 1);
}


static void nonreturning_filtered_catch_does_not_resume(void) {
  Error.initialize();
  int caught = 0, resumed = 0;
  try {
    raise %(no-member (tag probe) (member missing));
    resumed = 1;
  }
  catch %(no-member *): caught = 1;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(resumed, 0);
}


static void _filtered_raise_callee(int *order) {
  defer *order = *order * 10 + 1;
  raise %(alloc-fail);
}


static void filtered_catch_runs_callee_cleanup_before_arm(void) {
  Error.initialize();
  int order = 0;
  try {
    _filtered_raise_callee(&order);
  }
  catch %(alloc-fail): order = order * 10 + 2;
  EXPECT_INT_EQ(order, 12);
}


static int relabel_old_seen;
static int relabel_new_seen;

static Symbol _observe_relabel(List errors, Var data) {
  (void) data;
  Symbol code = errors.last().list().assoc(<code>);
  if (code == <old-error>) relabel_old_seen++;
  if (code == <new-error>) relabel_new_seen++;
  return <declined>;
}


static void filtered_catch_relabels_privately(void) {
  Error.initialize();
  relabel_old_seen = 0;
  relabel_new_seen = 0;
  int caught = 0;
  try {
    ErrorHandler observer = Error.push(_observe_relabel, void);
    defer Error.pop(observer);
    try {
      raise %(old-error);
    }
    catch %(old-error): raise %(new-error);
  }
  catch %(new-error): caught = 1;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(relabel_old_seen, 0);
  EXPECT_INT_EQ(relabel_new_seen, 1);
}


static void _raise_scoped_wide_value(void) {
  Scope.retain();
  defer Scope.release();
  long value = 0x123456789L;
  raise %(invariant (value $value));
}


static void filtered_catch_binder_survives_callee_scope(void) {
  Error.initialize();
  long caught = 0;
  try {
    _raise_scoped_wide_value();
  }
  catch %(invariant (value ?value)): caught = value.long_value();
  EXPECT_INT_EQ(caught, 0x123456789L);
}

static void _raise_from_transient_pools(void) {
  String.pool_retain_named("catch-binding-values");
  defer String.pool_release();
  String text = String.new("transient catch binding");
  raise %(invariant (value $text));
}

static void filtered_catch_binder_survives_transient_pools(void) {
  Error.initialize();
  String caught = NULL;
  try {
    _raise_from_transient_pools();
  }
  catch %(invariant (value ?value)): {
    Var snapshot = Error.snapshot(value);
    caught = snapshot;
  }
  EXPECT_STR_EQ(caught, "transient catch binding");
}


static void error_snapshot_survives_catch_and_caller_owners(void) {
  Error.initialize();
  List escaped = NULL;
  Scope.retain();
  String.pool_retain_named("snapshot-source-values");
  String text = String.new("snapshot survives");
  Atom atom = Atom.intern(String.new("long snapshot atom survives"));
  long number = 0x123456789L;
  List payload = %($text $number $atom);
  try {
    raise %(invariant (value $payload));
  }
  catch %(invariant (value ?value)): {
    Var snapshot = Error.snapshot(value);
    escaped = snapshot;
  }
  String.pool_release();
  Scope.release();
  (String escaped_text, long escaped_number, Atom escaped_atom) = escaped;
  EXPECT_STR_EQ(escaped_text, "snapshot survives");
  EXPECT_INT_EQ(escaped_number, 0x123456789L);
  EXPECT_STR_EQ(escaped_atom.str(), "long snapshot atom survives");
}


static void error_regions_do_not_capture_application_pools(void) {
  Error.initialize();
  Pool strings = String.pool_retain_named("application-error-source");
  Pool lists = strings;
  String text = String.new("application owned");
  List value = %($text 42);
  EXPECT_TRUE(Pool.owns(strings, text));
  EXPECT_TRUE(Pool.owns(lists, value));
  try {
    raise %(invariant (value $value));
  }
  catch %(invariant *): (void) 0;
  EXPECT_TRUE(Pool.owns(strings, text));
  EXPECT_TRUE(Pool.owns(lists, value));
  EXPECT_STR_EQ(text, "application owned");
  EXPECT_INT_EQ(value.cadr().integer(), 42);
  String.pool_release();
}


static void filtered_catch_preserves_older_errors(void) {
  Error.initialize();
  Error.policy_set(<old-error>, <collect>);
  int mark = Error.mark();
  Error.raise(<old-error>, %((where "older")));
  int before = Error.count();
  try {
    raise %(invariant);
  }
  catch %(invariant): {}
  EXPECT_INT_EQ(before, mark + 1);
  EXPECT_INT_EQ(Error.count(), before);
}


static void _filtered_catch_once(void) {
  try {
    raise %(invariant);
  }
  catch %(invariant): {}
}


static void filtered_catch_repeated_success_does_not_leak(void) {
  Error.initialize();
  _filtered_catch_once();
  ScopeStats before = Scope.stats();
  for (int i = 0; i < 100; i++) _filtered_catch_once();
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}


$(import "test-macros.xmacro")

void exception_suite(void) {
  $test.run(exception_try_cleanup_on_return);
  $test.run(exception_try_cleanup_on_loop_control);
  $test.run(exception_finally_runs_on_success);
  $test.run(exception_normal_exit_preserves_collected_errors);
  $test.run(exception_finally_runs_on_exception);
  $test.run(exception_finally_with_catch);
  $test.run(exception_nested_finally_runs_once);
  $test.run(exception_bubbles_across_frames);
  $test.run(error_unwind_selects_target_and_bindings);
  $test.run(error_unwind_retains_positional_and_legacy_order);
  $test.run(error_unwind_crosses_each_exception_frame);
  $test.run(cleanup_chain_leaves_in_lifo_order);
  $test.run(cleanup_chain_unlinks_before_callback);
  $test.run(cleanup_chain_crosses_three_callers);
  $test.run(cleanup_chain_reads_latest_value_before_jump);
  $test.run(cleanup_chain_preserves_intervening_finally);
  $test.run(cleanup_chain_surrounds_handled_try);
  $test.run(filtered_catch_selects_exact_and_later_arms);
  $test.run(filtered_catch_selects_default_arm);
  $test.run(filtered_catch_continues_to_outer_registration);
  $test.run(nonreturning_filtered_catch_does_not_resume);
  $test.run(filtered_catch_runs_callee_cleanup_before_arm);
  $test.run(filtered_catch_relabels_privately);
  $test.run(filtered_catch_binder_survives_callee_scope);
  $test.run(filtered_catch_binder_survives_transient_pools);
  $test.run(error_snapshot_survives_catch_and_caller_owners);
  $test.run(error_regions_do_not_capture_application_pools);
  $test.run(filtered_catch_preserves_older_errors);
  $test.run(filtered_catch_repeated_success_does_not_leak);
}
