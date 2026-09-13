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
  Symbol code = <error-prob>;
  Error.policy_set(code, <ignore>);
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
  Symbol code = <error-prob>;
  Error.policy_set(code, <ignore>);
  seen_count = -1;
  ErrorHandler outer = Error.push(_absorb, void);
  ErrorHandler inner = Error.push(_decline_all, void);
  List detail = %((where "task-4-decline"));
  Error.raise(code, detail);
  Error.pop(inner);
  Error.pop(outer);
  EXPECT_INT_EQ(seen_count, 1);
}




static List observed_entry;

static Symbol _observe_newest(List errors, Var data) {
  (void) data;
  observed_entry = Error.snapshot(errors.last());
  return <handled>;
}

static void error_counted_bridge_records_site_and_pairs(void) {
  Error.initialize();
  Symbol code = <error-prob>;
  Error.policy_set(code, <ignore>);
  ErrorHandler observer = Error.push(_observe_newest, void);
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
  Error.pop(observer);
  List entry = observed_entry;
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
  Error.policy_set(<error-prob>, <ignore>);
  ErrorHandler observer = Error.push(_observe_newest, void);
  _raise_collected_from_transient_pools();
  Error.pop(observer);
  List entry = observed_entry;
  List detail = entry.assoc(<detail>);
  List location = entry.assoc(<location>);
  EXPECT_STR_EQ(detail.assoc(<text>).string(), "transient collected detail");
  EXPECT_STR_EQ(location.assoc(<file>).string(), "transient-record.x");
  EXPECT_STR_EQ(location.assoc(<function>).string(), "transient_record_probe");
  EXPECT_INT_EQ(location.assoc(<line>).integer(), 29);
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
  Error.policy_set(<old-error>, <ignore>);
  int caught = 0;
  try {
    Error.policy_set(<old-error>, <typo>);
  }
  catch %(bad-arg *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(Error.policy_get(<old-error>) == <ignore>);
}

static void error_policy_locks_nonreturning_causes(void) {
  Error.initialize();
  int caught = 0;
  Symbol dispositions[] = { <log>, <ignore> };
  foreach(Symbol code, nonreturning_error_causes) {
    size_t count = sizeof dispositions / sizeof dispositions[0];
    for (size_t i = 0; i < count; i++) {
      try Error.policy_set(code, dispositions[i]);
      catch %(bad-arg *): caught++;
      EXPECT_TRUE(Error.policy_get(code) == <abort>);
    }
  }
  EXPECT_INT_EQ(caught, 56);
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
  ErrorHandler warm_renderer = Error.push(_render_current, void);
  _raise_unique_errors(<logged-err>, 1);
  Error.pop(warm_renderer);
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

  ErrorHandler declined = Error.push(_decline_all, void);
  _raise_unique_errors(<ignored-er>, 1000);
  Error.pop(declined);
  ScopeStats after_declined = Scope.stats();
  EXPECT_INT_EQ(Error.count(), 0);
  EXPECT_INT_EQ(after_declined.live_allocations, before.live_allocations);
}


static Symbol _render_current(List errors, Var data) {
  (void) errors;
  (void) data;
  Error.note_rendered();
  return <declined>;
}


static void error_policy_actions_consume_the_newest_record(void) {
  Error.initialize();
  Error.policy_set(<ignored-er>, <ignore>);
  Error.raise(<ignored-er>, %((where "ignore")));
  EXPECT_INT_EQ(Error.count(), 0);

  Error.policy_set(<logged-err>, <log>);
  ErrorHandler renderer = Error.push(_render_current, void);
  Error.raise(<logged-err>, %((where "log")));
  Error.pop(renderer);
  EXPECT_INT_EQ(Error.count(), 0);
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
  $test.run(error_handler_sees_its_own_slice);
  $test.run(error_handler_registration_is_reclaimed);
  $test.run(error_transferring_registration_is_reclaimed);
  $test.run(error_decline_walks_outward);
  $test.run(error_record_regions_reclaim_at_owner_boundary);
  $test.run(error_counted_bridge_records_site_and_pairs);
  $test.run(error_collected_record_survives_transient_pools);
  $test.run(error_policy_actions_consume_the_newest_record);
  $test.run(error_handler_head_survives_transfer);
  $test.run(error_dispatch_firewall_skips_active_handler);
  $test.run(error_logger_handler_is_registered);
}
