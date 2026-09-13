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

static void system_scope_loop_lifetimes(void) {
  ScopeStats before = Scope.stats();
  $scope() for (int i = 0; i < 3; i++) {
    Scope.malloc(1);
    if (i == 1) continue;
  }
  ScopeStats whole = Scope.stats();
  EXPECT_INT_EQ(whole.scope_creations, before.scope_creations + 1);
  EXPECT_INT_EQ(whole.live_allocations, before.live_allocations);
  for (int i = 0; i < 3; i++) $scope() {
    Scope.malloc(1);
    if (i == 1) continue;
  }
  ScopeStats each = Scope.stats();
  EXPECT_INT_EQ(each.scope_creations, whole.scope_creations + 3);
  EXPECT_INT_EQ(each.live_allocations, before.live_allocations);
}

static int _scope_return(void) {
  $scope() { Scope.malloc(1); return 9; }
}

static int _scope_transfer_round(void) {
  int caught = 0;
  try {
    $scope() { Scope.malloc(1); raise %(invariant); }
  }
  catch %(invariant): { caught = 1; }
  return caught;
}

static void system_scope_restores_destination_and_transfer(void) {
  Scope destination = Scope.new(), *previous = Scope.top();
  int evaluations = 0, caught = 0;
  $scope((evaluations++, &destination)) {
    EXPECT_TRUE(Scope.top() == &destination);
    Scope.malloc(3);
  }
  EXPECT_INT_EQ(evaluations, 1);
  EXPECT_TRUE(Scope.top() == previous);
  try { $scope(&destination) { raise %(invariant); } }
  catch %(invariant): { caught = 1; }
  EXPECT_INT_EQ(caught, 1);
  EXPECT_TRUE(Scope.top() == previous);
  EXPECT_INT_EQ(_scope_return(), 9);
  // the first round publishes this catch site's process-lifetime plans
  caught = _scope_transfer_round();
  ScopeStats retained = Scope.stats();
  caught = _scope_transfer_round();
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(after.live_allocations, retained.live_allocations);
  EXPECT_INT_EQ(after.live_scopes, retained.live_scopes);
  Scope.destroy(destination);
}

static void system_let_captures_storage_once(void) {
  int values[2] = { 1, 2 }, index = 0, evaluations = 0, caught = 0;
  try {
    $let(values[index++], (evaluations++, 7)) {
      EXPECT_INT_EQ(values[0], 7);
      EXPECT_INT_EQ(index, 1);
      index = 1;
      raise %(invariant);
    }
  }
  catch %(invariant): { caught = 1; }
  EXPECT_INT_EQ(values[0], 1);
  EXPECT_INT_EQ(values[1], 2);
  EXPECT_INT_EQ(evaluations, 1);
  EXPECT_INT_EQ(caught, 1);
}

typedef int ManagedResource;
typedef ManagedResource ManagedChild;
protocol Cleanup(ManagedResource);

void ManagedResource.cleanup(ManagedResource resource) {
  defer_record(resource);
}

static int managed_acquisitions;

static ManagedResource _managed_acquire(int value) {
  managed_acquisitions++;
  if (value < 0) raise %(invariant);
  return value;
}

static void managed_local_preserves_binding_and_order(void) {
  defer_reset();
  managed_acquisitions = 0;
  {
    ManagedResource before = 0, first = $auto(_managed_acquire(1)),
      between = 8, second = ($auto(_managed_acquire(2))), after = 9;
    ManagedChild third = $auto(_managed_acquire(3));
    first = 4;
    EXPECT_INT_EQ(before, 0);
    EXPECT_INT_EQ(between, 8);
    EXPECT_INT_EQ(after, 9);
    EXPECT_INT_EQ(second, 2);
    EXPECT_INT_EQ(third, 3);
    EXPECT_INT_EQ(defer_index, 0);
  }
  EXPECT_INT_EQ(managed_acquisitions, 3);
  EXPECT_INT_EQ(defer_index, 3);
  EXPECT_INT_EQ(defer_log[0], 3);
  EXPECT_INT_EQ(defer_log[1], 2);
  EXPECT_INT_EQ(defer_log[2], 4);
}

static void managed_local_cleans_before_failed_later_acquisition(void) {
  defer_reset();
  managed_acquisitions = 0;
  int caught = 0;
  try {
    ManagedResource first = $auto(_managed_acquire(1)),
      second = $auto(_managed_acquire(-2));
    (void) first, (void) second;
    TEST_FAIL("raising initializer returned");
  }
  catch %(invariant): { caught = 1; }
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(managed_acquisitions, 2);
  EXPECT_INT_EQ(defer_index, 1);
  EXPECT_INT_EQ(defer_log[0], 1);
}

macro Expression $managed_nested(Expr $value) => ($auto($value))

macro Statement $managed_declaration(Name $name, Expr $value) => {
  ManagedResource $name = $auto($value);
}

int ManagedResource.value(ManagedResource value) { return value; }

static void managed_local_keeps_constructed_binding(void) {
  defer_reset();
  {
    $managed_declaration(resource, 7);
    EXPECT_INT_EQ(resource.value(), 7);
  }
  EXPECT_INT_EQ(defer_index, 1);
  EXPECT_INT_EQ(defer_log[0], 7);
}

static ManagedResource _managed_return(void) {
  ManagedResource resource = $managed_nested(_managed_acquire(5));
  return resource;
}

static void managed_local_allows_constructed_syntax(void) {
  defer_reset();
  managed_acquisitions = 0;
  {
    ManagedResource resource = $(list 'managed-init
      (list 'expr (list 'int) (list 'literal (list 'int) "6")));
    EXPECT_INT_EQ(resource, 6);
  }
  EXPECT_INT_EQ(_managed_return(), 5);
  EXPECT_INT_EQ(managed_acquisitions, 1);
  EXPECT_INT_EQ(defer_index, 2);
  EXPECT_INT_EQ(defer_log[0], 6);
  EXPECT_INT_EQ(defer_log[1], 5);
}

$(import "test-macros.xmacro")

void defer_suite(void) {
  $test.run(system_scope_loop_lifetimes);
  $test.run(system_scope_restores_destination_and_transfer);
  $test.run(system_let_captures_storage_once);
  $test.run(managed_local_preserves_binding_and_order);
  $test.run(managed_local_cleans_before_failed_later_acquisition);
  $test.run(managed_local_allows_constructed_syntax);
  $test.run(managed_local_keeps_constructed_binding);
  $test.run(defer_runs_on_scope_exit);
  $test.run(defer_runs_on_return);
  $test.run(defer_evaluates_return_before_cleanup);
  $test.run(defer_uses_lifo_order);
  $test.run(defer_runs_with_break);
  $test.run(defer_continue_preserves_enclosing_catch);
  $test.run(defer_switch_break_defers_to_function_exit);
  $test.run(defer_continue_in_switch_targets_enclosing_loop);
  $test.run(defer_break_in_nested_loop_targets_that_loop);
}
