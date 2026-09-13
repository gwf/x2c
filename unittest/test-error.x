/*  test-error.x -- unit tests for the error handler and accumulation stacks */

$(import "../lib/error-macros.xmacro")
#include "test-support.x"
#include <string.h>

static const SymbolSet nonreturning_error_causes =
  $error.nonreturning.causes();

static void error_initialize_is_idempotent(void) {
  Error.initialize();
  EXPECT_TRUE(Error.ready());
  Error.initialize();
  EXPECT_TRUE(Error.ready());
}

static void error_depth_starts_at_zero(void) {
  Error.initialize();
  EXPECT_INT_EQ(Error.depth(), 0);
}

static void error_stack_accumulates_and_slices(void) {
  Error.initialize();
  Symbol collect = <collect>, code = <error-prob>;
  Error.policy_set(code, collect);
  int mark = Error.mark();
  List detail = %((where "task-3"));
  Error.raise(code, detail);
  EXPECT_INT_EQ(Error.count(), mark + 1);
  List slice = Error.since(mark);
  EXPECT_INT_EQ(slice.len(), 1);
  EXPECT_TRUE(Error.count() > 0);
}

static int seen_count;

static Symbol _absorb(List errors, Var data) {
  (void) data;
  seen_count = errors.len();
  return <handled>;
}

static Symbol _decline_all(List errors, Var data) {
  (void) errors;
  (void) data;
  return <declined>;
}


static Symbol _raise_from_handler(List errors, Var data) {
  (void) errors;
  (void) data;
  raise %(handler-pr (where "handler"));
  return <declined>;
}

static Symbol _handle_nested_only(List errors, Var data) {
  (void) data;
  if (!errors) return <declined>;
  List newest = errors.last();
  return newest.assoc(<code>) == <handler-pr> ? <handled> : <declined>;
}

static void error_handler_sees_its_own_slice(void) {
  Error.initialize();
  Symbol collect = <collect>, code = <error-prob>;
  Error.policy_set(code, collect);
  seen_count = -1;
  ErrorHandler h = Error.push(_absorb, void);
  List detail = %((where "task-4"));
  Error.raise(code, detail);
  Error.pop(h);
  EXPECT_INT_EQ(seen_count, 1);
}


static void error_handler_registration_is_reclaimed(void) {
  Error.initialize();
  ScopeStats before = Scope.stats();
  for (int i = 0; i < 100; i++) {
    ErrorHandler h = Error.push(_decline_all, void);
    Error.pop(h);
  }
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}


static void error_transferring_registration_is_reclaimed(void) {
  Error.initialize();
  List pattern = %(invariant *);
  ScopeStats before = Scope.stats();
  for (int i = 0; i < 100; i++) {
    int target = 0;
    ErrorHandler h = x2c_error_catch_push(&target, 1, pattern.var());
    x2c_error_catch_detach(h);
    x2c_error_catch_close(h);
  }
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}

static void error_decline_walks_outward(void) {
  Error.initialize();
  Symbol collect = <collect>, code = <error-prob>;
  Error.policy_set(code, collect);
  seen_count = -1;
  ErrorHandler outer = Error.push(_absorb, void);
  ErrorHandler inner = Error.push(_decline_all, void);
  List detail = %((where "task-4-decline"));
  Error.raise(code, detail);
  Error.pop(inner);
  Error.pop(outer);
  EXPECT_INT_EQ(seen_count, 1);
}

static void error_pop_truncates_declined_slice(void) {
  Error.initialize();
  Symbol collect = <collect>, code = <error-prob>;
  Error.policy_set(code, collect);
  int mark = Error.mark();
  ErrorHandler h = Error.push(_decline_all, void);
  List detail = %((where "task-4-residue"));
  Error.raise(code, detail);
  Error.pop(h);
  EXPECT_INT_EQ(Error.count(), mark);
}

static void error_bridge_records_like_raise(void) {
  Error.initialize();
  Symbol collect = <collect>, code = <error-prob>;
  Error.policy_set(code, collect);
  int mark = Error.mark();
  List detail = %((bytes 64));
  x2c_error_raise(code, detail);
  EXPECT_INT_EQ(Error.count(), mark + 1);
}


static void error_counted_bridge_records_site_and_pairs(void) {
  Error.initialize();
  Symbol code = <error-prob>;
  Error.policy_set(code, <collect>);
  int mark = Error.mark();
  X2CErrorSite site = {
    .file = "counted-probe.x",
    .function = "probe_function",
    .line = 17
  };
  int bytes = 64;
  x2c_error_raise_n(
    &site, code, 2,
    <bytes>.var(), bytes.var(),
    <owner>.var(), %"probe".var()
  );
  List entry = Error.since(mark).car();
  List detail = entry.assoc(<detail>);
  List location = entry.assoc(<location>);
  EXPECT_INT_EQ(detail.len(), 2);
  EXPECT_INT_EQ(detail[0].list().cadr().integer(), 64);
  EXPECT_STR_EQ(detail[1].list().cadr().string(), "probe");
  EXPECT_STR_EQ(location.assoc(<file>).string(), "counted-probe.x");
  EXPECT_INT_EQ(location.assoc(<line>).integer(), 17);
  EXPECT_STR_EQ(location.assoc(<function>).string(), "probe_function");
}

static void _raise_collected_from_transient_pools(void) {
  String.pool_retain_named("error-record-values");
  String text = String.malloc(27);
  strcpy(text, "transient collected detail");
  X2CErrorSite site = {
    .file = "transient-record.x",
    .function = "transient_record_probe",
    .line = 29
  };
  x2c_error_raise_n(&site, <error-prob>, 1, <text>.var(), text.var());
  String.pool_release();
}

static void error_collected_record_survives_transient_pools(void) {
  Error.initialize();
  Error.policy_set(<error-prob>, <collect>);
  int mark = Error.mark();
  _raise_collected_from_transient_pools();
  List entry = Error.since(mark).car();
  List detail = entry.assoc(<detail>);
  List location = entry.assoc(<location>);
  EXPECT_STR_EQ(detail.assoc(<text>).string(), "transient collected detail");
  EXPECT_STR_EQ(location.assoc(<file>).string(), "transient-record.x");
  EXPECT_STR_EQ(location.assoc(<function>).string(), "transient_record_probe");
  EXPECT_INT_EQ(location.assoc(<line>).integer(), 29);
}

static void error_stack_bound_is_configurable(void) {
  Error.initialize();
  EXPECT_INT_EQ(Error.bound(), ERROR_DEFAULT_BOUND);
  Error.bound_set(4);
  EXPECT_INT_EQ(Error.bound(), 4);
  Error.bound_set(ERROR_DEFAULT_BOUND);
}


static void error_default_policies_match_contract(void) {
  Error.initialize();
  EXPECT_INT_EQ(nonreturning_error_causes.len(), 28);
  foreach(Symbol code, nonreturning_error_causes)
    EXPECT_TRUE(Error.policy_get(code) == <abort>);
  EXPECT_TRUE(Error.policy_get(<join-fail>) == <abort>);
  EXPECT_TRUE(Error.policy_get(<unknown-co>) == <abort>);
}

static void error_policy_rejects_unknown_disposition(void) {
  Error.initialize();
  Error.policy_set(<old-error>, <collect>);
  int caught = 0;
  try {
    Error.policy_set(<old-error>, <typo>);
  }
  catch %(bad-arg *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(Error.policy_get(<old-error>) == <collect>);
}

static void error_policy_locks_nonreturning_causes(void) {
  Error.initialize();
  int caught = 0;
  Symbol dispositions[] = { <collect>, <log>, <ignore> };
  foreach(Symbol code, nonreturning_error_causes) {
    size_t count = sizeof dispositions / sizeof dispositions[0];
    for (size_t i = 0; i < count; i++) {
      try Error.policy_set(code, dispositions[i]);
      catch %(bad-arg *): caught++;
      EXPECT_TRUE(Error.policy_get(code) == <abort>);
    }
  }
  EXPECT_INT_EQ(caught, 84);
}


static void error_nested_pop_truncates_exact_watermark(void) {
  Error.initialize();
  Error.policy_set(<old-error>, <collect>);
  int mark = Error.mark();
  ErrorHandler outer = Error.push(_decline_all, void);
  Error.raise(<old-error>, %((sequence 1)));
  EXPECT_INT_EQ(Error.count(), mark + 1);
  ErrorHandler inner = Error.push(_decline_all, void);
  Error.raise(<old-error>, %((sequence 2)));
  EXPECT_INT_EQ(Error.count(), mark + 2);
  Error.pop(inner);
  EXPECT_INT_EQ(Error.count(), mark + 1);
  Error.pop(outer);
  EXPECT_INT_EQ(Error.count(), mark);
}


static void _raise_unique_errors(Symbol code, int count) {
  String.pool_retain_named("error-unique-source-values");
  for (int i = 0; i < count; i++) {
    char raw[32];
    snprintf(raw, sizeof raw, "unique-error-%d", i);
    String text = String.new(raw);
    x2c_error_raise_n(NULL, code, 1, <value>.var(), text.var());
  }
  String.pool_release();
}


static void error_record_regions_reclaim_at_owner_boundary(void) {
  Error.initialize();
  Error.policy_set(<ignored-er>, <ignore>);
  Error.policy_set(<logged-err>, <log>);
  Error.policy_set(<old-error>, <collect>);
  ErrorHandler warm_renderer = Error.push(_render_current, void);
  _raise_unique_errors(<logged-err>, 1);
  Error.pop(warm_renderer);
  int mark = Error.mark();
  ScopeStats before = Scope.stats();

  ErrorHandler handled = Error.push(_absorb, void);
  _raise_unique_errors(<handled-er>, 1000);
  Error.pop(handled);
  ScopeStats after_handled = Scope.stats();
  EXPECT_INT_EQ(after_handled.live_allocations, before.live_allocations);

  _raise_unique_errors(<ignored-er>, 1000);
  ScopeStats after_ignored = Scope.stats();
  EXPECT_INT_EQ(after_ignored.live_allocations, before.live_allocations);

  ErrorHandler rendered = Error.push(_render_current, void);
  _raise_unique_errors(<logged-err>, 1000);
  Error.pop(rendered);
  ScopeStats after_logged = Scope.stats();
  EXPECT_INT_EQ(after_logged.live_allocations, before.live_allocations);

  ErrorHandler collected = Error.push(_decline_all, void);
  _raise_unique_errors(<old-error>, 1000);
  EXPECT_INT_EQ(Error.count(), mark + 1000);
  EXPECT_TRUE(Scope.stats().live_allocations > before.live_allocations);
  Error.pop(collected);
  ScopeStats after_collected = Scope.stats();
  EXPECT_INT_EQ(Error.count(), mark);
  EXPECT_INT_EQ(after_collected.live_allocations, before.live_allocations);
}


static Symbol _render_current(List errors, Var data) {
  (void) errors;
  (void) data;
  Error.note_rendered();
  return <declined>;
}


static void error_policy_actions_affect_only_newest(void) {
  Error.initialize();
  int mark = Error.mark();
  Error.policy_set(<error-prob>, <collect>);
  Error.raise(<error-prob>, %((where "collect")));
  EXPECT_INT_EQ(Error.count(), mark + 1);

  Error.policy_set(<ignored-er>, <ignore>);
  Error.raise(<ignored-er>, %((where "ignore")));
  EXPECT_INT_EQ(Error.count(), mark + 1);

  Error.policy_set(<logged-err>, <log>);
  ErrorHandler renderer = Error.push(_render_current, void);
  Error.raise(<logged-err>, %((where "log")));
  Error.pop(renderer);
  EXPECT_INT_EQ(Error.count(), mark + 1);
}


static void error_handler_head_survives_transfer(void) {
  Error.initialize();
  Symbol ignore = <ignore>, code = <handler-pr>;
  Error.policy_set(code, ignore);
  seen_count = -1;
  ErrorHandler h = Error.push(_absorb, void);
  int depth_before = Error.handler_depth();
  try {
    raise %(bad-state (where "past registration"));
  }
  catch %(bad-state *): {}
  EXPECT_INT_EQ(Error.handler_depth(), depth_before);
  List detail = %((where "task-6"));
  Error.raise(code, detail);
  Error.pop(h);
  EXPECT_INT_EQ(seen_count, 1);
}


static void error_dispatch_firewall_skips_active_handler(void) {
  Error.initialize();
  Error.policy_set(<firewall-p>, <ignore>);
  Error.policy_set(<handler-pr>, <ignore>);
  int baseline = Error.handler_depth();
  ErrorHandler h = Error.push(_raise_from_handler, void);
  Error.raise(<firewall-p>, %((where "firewall")));
  Error.pop(h);
  EXPECT_INT_EQ(Error.handler_depth(), baseline);
  EXPECT_INT_EQ(Error.depth(), 0);
}

static void filtered_catch_ignores_consumed_records(void) {
  Error.initialize();
  Error.policy_set(<old-error>, <collect>);
  Error.policy_set(<error-prob>, <collect>);
  Error.policy_set(<handler-pr>, <collect>);
  int mark = Error.mark(), caught = 0;
  ErrorHandler cleanup = Error.push(_decline_all, void);
  Error.raise(<old-error>, %((sequence 1)));
  ErrorHandler outer = Error.push(_handle_nested_only, void);
  Error.raise(<error-prob>, %((sequence 2)));
  try {
    ErrorHandler inner = Error.push(_raise_from_handler, void);
    defer Error.pop(inner);
    Error.raise(<old-error>, %((sequence 3)));
  }
  catch %(old-error *): caught = 1;
  Error.pop(outer);
  Error.pop(cleanup);
  EXPECT_FALSE(caught);
  EXPECT_INT_EQ(Error.count(), mark);
}

static void error_logger_handler_is_registered(void) {
  Logger.initialize();
  Error.initialize();
  EXPECT_TRUE(Error.handler_depth() >= 1);
}

$(import "test-macros.xmacro")

void error_suite(void) {
  $test.run(error_initialize_is_idempotent);
  $test.run(error_depth_starts_at_zero);
  $test.run(error_default_policies_match_contract);
  $test.run(error_policy_rejects_unknown_disposition);
  $test.run(error_policy_locks_nonreturning_causes);
  $test.run(error_stack_accumulates_and_slices);
  $test.run(error_handler_sees_its_own_slice);
  $test.run(error_handler_registration_is_reclaimed);
  $test.run(error_transferring_registration_is_reclaimed);
  $test.run(error_decline_walks_outward);
  $test.run(error_pop_truncates_declined_slice);
  $test.run(error_nested_pop_truncates_exact_watermark);
  $test.run(error_record_regions_reclaim_at_owner_boundary);
  $test.run(error_bridge_records_like_raise);
  $test.run(error_counted_bridge_records_site_and_pairs);
  $test.run(error_collected_record_survives_transient_pools);
  $test.run(error_stack_bound_is_configurable);
  $test.run(error_policy_actions_affect_only_newest);
  $test.run(error_handler_head_survives_transfer);
  $test.run(error_dispatch_firewall_skips_active_handler);
  $test.run(filtered_catch_ignores_consumed_records);
  $test.run(error_logger_handler_is_registered);
}
