/*  test-defer.x -- unit tests for defer statement semantics */

#include "test-support.x"

#include <string.h>

static int defer_log[8];
static int defer_index;

static void defer_reset(void) {
  memset(defer_log, 0, sizeof(defer_log));
  defer_index = 0;
}

static void defer_record(int value) {
  if (defer_index < (int)(sizeof(defer_log) / sizeof(defer_log[0])))
    defer_log[defer_index++] = value;
}

static int defer_return_helper(void) {
  {
    defer defer_record(2);
    defer_record(1);
  }
  return 0;
}

static int defer_return_value;

static void defer_clear_return_value(void) {
  defer_return_value = 0;
}

static int defer_return_expression_helper(void) {
  defer defer_clear_return_value();
  defer_return_value = 42;
  return defer_return_value;
}

static void defer_runs_on_scope_exit(void) {
  defer_reset();
  {
    defer defer_record(2);
    defer_record(1);
  }
  EXPECT_INT_EQ(defer_index, 2);
  EXPECT_INT_EQ(defer_log[0], 1);
  EXPECT_INT_EQ(defer_log[1], 2);
}

static void defer_runs_on_return(void) {
  defer_reset();
  defer_return_helper();
  EXPECT_INT_EQ(defer_index, 2);
  EXPECT_INT_EQ(defer_log[0], 1);
  EXPECT_INT_EQ(defer_log[1], 2);
}

static void defer_evaluates_return_before_cleanup(void) {
  defer_return_value = 0;
  int result = defer_return_expression_helper();
  EXPECT_INT_EQ(result, 42);
  EXPECT_INT_EQ(defer_return_value, 0);
}

static void _defer_collect_helper(int *cleanup) {
  defer (*cleanup)++;
  Error.raise(<old-error>, %((where "defer return")));
}

static void defer_preserves_collected_errors(void) {
  Error.initialize();
  Error.policy_set(<old-error>, <collect>);
  int mark = Error.mark(), cleanup = 0;
  _defer_collect_helper(&cleanup);
  EXPECT_INT_EQ(cleanup, 1);
  EXPECT_INT_EQ(Error.count(), mark + 1);
}

static void defer_uses_lifo_order(void) {
  defer_reset();
  {
    defer defer_record(3);
    {
      defer defer_record(2);
      defer_record(1);
    }
  }
  EXPECT_INT_EQ(defer_index, 3);
  EXPECT_INT_EQ(defer_log[0], 1);
  EXPECT_INT_EQ(defer_log[1], 2);
  EXPECT_INT_EQ(defer_log[2], 3);
}

static void defer_runs_with_break(void) {
  defer_reset();
  for (int i = 0; i < 1; i++) {
    defer defer_record(2);
    defer_record(1);
    break;
  }
  EXPECT_INT_EQ(defer_index, 2);
  EXPECT_INT_EQ(defer_log[0], 1);
  EXPECT_INT_EQ(defer_log[1], 2);
}

static int cleanup_catch_survived = 0;

static void _defer_loop_body(void) {
  try {
    for (int i = 0; i < 3; i++) {
      if (i == 0) continue;
      if (i == 1) raise %(invariant);
    }
  }
  catch %(invariant): {
    cleanup_catch_survived = 1;
  }
}

static void defer_continue_preserves_enclosing_catch(void) {
  Scope.retain();
  cleanup_catch_survived = 0;
  _defer_loop_body();
  EXPECT_INT_EQ(cleanup_catch_survived, 1);
  Scope.release();
}

static int cleanup_switch_order = 0;

static void _defer_switch_body(void) {
  defer cleanup_switch_order = cleanup_switch_order * 10 + 2;
  int x = 1;
  switch (x) {
    case 1: cleanup_switch_order = 1; break;
    default: break;
  }
  cleanup_switch_order = cleanup_switch_order * 10 + 3;
}

static void defer_switch_break_defers_to_function_exit(void) {
  Scope.retain();
  cleanup_switch_order = 0;
  _defer_switch_body();
  EXPECT_INT_EQ(cleanup_switch_order, 132);
  Scope.release();
}

// break and continue need separate cleanup barriers. A continue inside a
// switch targets the enclosing loop, so it must still run a defer registered
// in the loop body; a break in the same loop targets the switch, so it must
// not. A single shared barrier gets exactly one of these two wrong.
static int cleanup_loop_switch_order = 0;

static void _defer_loop_switch_body(void) {
  for (int i = 0; i < 3; i++) {
    defer cleanup_loop_switch_order = cleanup_loop_switch_order * 10 + 9;
    switch (i) {
      case 0: continue;
      default: break;
    }
    cleanup_loop_switch_order = cleanup_loop_switch_order * 10 + i;
  }
}

static void defer_continue_in_switch_targets_enclosing_loop(void) {
  Scope.retain();
  cleanup_loop_switch_order = 0;
  _defer_loop_switch_body();
  EXPECT_INT_EQ(cleanup_loop_switch_order, 91929);
  Scope.release();
}

// The converse nesting: a break inside a loop nested in a switch targets that
// loop, so a defer registered in the case block runs when the case block
// exits, not at the inner break.
static int cleanup_switch_loop_order = 0;

static void _defer_switch_loop_body(void) {
  int selector = 1;
  switch (selector) {
    case 1: {
      defer cleanup_switch_loop_order = cleanup_switch_loop_order * 10 + 4;
      while (1) {
        break;
      }
      cleanup_switch_loop_order = cleanup_switch_loop_order * 10 + 5;
      break;
    }
    default: break;
  }
  cleanup_switch_loop_order = cleanup_switch_loop_order * 10 + 6;
}

static void defer_break_in_nested_loop_targets_that_loop(void) {
  Scope.retain();
  cleanup_switch_loop_order = 0;
  _defer_switch_loop_body();
  EXPECT_INT_EQ(cleanup_switch_loop_order, 546);
  Scope.release();
}

$(import "test-macros.xmacro")

void defer_suite(void) {
  $test.run(defer_runs_on_scope_exit);
  $test.run(defer_runs_on_return);
  $test.run(defer_evaluates_return_before_cleanup);
  $test.run(defer_preserves_collected_errors);
  $test.run(defer_uses_lifo_order);
  $test.run(defer_runs_with_break);
  $test.run(defer_continue_preserves_enclosing_catch);
  $test.run(defer_switch_break_defers_to_function_exit);
  $test.run(defer_continue_in_switch_targets_enclosing_loop);
  $test.run(defer_break_in_nested_loop_targets_that_loop);
}
