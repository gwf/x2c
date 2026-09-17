/*  test-system-macros.x -- the shipped system macro set */

#include "x2c.x"
#include "test-support.x"
#include <time.h>
$(import "test-macros.xmacro")
$(import "system-macros.xmacro")

static String _classify(int code) {
  String reached = "none";
  $switch(code)
  {
    case 1:
    case 2:
      String shared = "low";
      reached = shared;
    case 3:
      String shared = "three";
      reached = shared;
    default:
      reached = "other";
  }
  return reached;
}

static int _returns_early(int code) {
  $switch(code)
  {
    case 1:
      return 10;
    default:
      return -1;
  }
}

static void system_macro_switch_scopes_and_breaks_each_run(void) {
  EXPECT_TRUE(_classify(1) == "low");
  EXPECT_TRUE(_classify(2) == "low");
  EXPECT_TRUE(_classify(3) == "three");
  EXPECT_TRUE(_classify(9) == "other");
  EXPECT_INT_EQ(_returns_early(1), 10);
  EXPECT_INT_EQ(_returns_early(2), -1);
}

static void system_macro_dedent_folds_and_defers(void) {
  EXPECT_TRUE($dedent(%"
    alpha
      beta
    gamma
  ") == "alpha\n  beta\ngamma\n");
  String who = "world";
  EXPECT_TRUE($dedent(%"
    hello $who
      indented
  ") == "hello world\n  indented\n");
}

static void system_macro_assert_reports_the_written_check(void) {
  int limit = 50;
  String check = NULL, site = NULL;
  try $assert(limit > 0 && limit < 10);
  catch %(invariant (check ?written) (at ?where)): {
    check = written;
    site = where;
  }
  EXPECT_TRUE(check == "limit > 0 && limit < 10");
  EXPECT_TRUE(site.contains("test-system-macros.x:"));
}

static void system_macro_assert_passes_a_true_check(void) {
  int limit = 5;
  $assert(limit > 0 && limit < 10);
  EXPECT_INT_EQ(limit, 5);
}

static void system_macro_todo_and_unreachable_carry_a_note(void) {
  String note = NULL, dead = NULL;
  try $todo("column alignment");
  catch %(invariant (note ?text) (at ?where)): note = text;
  EXPECT_TRUE(note == "column alignment");
  try $unreachable();
  catch %(invariant (note ?text) (at ?where)): dead = text;
  EXPECT_TRUE(dead == "unreachable");
}

static void system_macro_time_runs_its_target(void) {
  long total = 0;
  $time("unit")
  {
    for (int i = 0; i < 1000; i++) total += i;
  }
  EXPECT_TRUE(total == 499500);
}

void system_macros_suite(void) {
  $test.run(system_macro_switch_scopes_and_breaks_each_run);
  $test.run(system_macro_dedent_folds_and_defers);
  $test.run(system_macro_assert_reports_the_written_check);
  $test.run(system_macro_assert_passes_a_true_check);
  $test.run(system_macro_todo_and_unreachable_carry_a_note);
  $test.run(system_macro_time_runs_its_target);
}
