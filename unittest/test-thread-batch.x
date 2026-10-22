/*  test-thread-batch.x -- synchronous callable batch contracts */

#include "test-support.x"
#include "test-macros.x"
#include <sched.h>
#include <stdatomic.h>
#include <pthread.h>

static atomic_int batch_ready, batch_finished, batch_cleanup_barrier;
static pthread_cond_t batch_condition =
  (pthread_cond_t) PTHREAD_COND_INITIALIZER;

static void _batch_reset(void) {
  atomic_store(&batch_ready, 0);
  atomic_store(&batch_finished, 0);
  atomic_store(&batch_cleanup_barrier, 0);
}

static void _batch_wait_ready(int count) {
  while (atomic_load(&batch_ready) < count) sched_yield();
}

static Var _batch_wait_for_stop(void) {
  defer atomic_fetch_add(&batch_finished, 1);
  x2c_thread_wait_lock();
  atomic_fetch_add(&batch_ready, 1);
  while (!x2c_thread_stopping()) x2c_thread_wait(&batch_condition);
  x2c_thread_wait_unlock();
  x2c_thread_cancel();
  return void;
}

static void batch_empty_and_void_results(void) {
  $test.scoped();
  int calls = 0, voids = 0;
  Thread.run([]);
  Thread.run([(Func) (%!(void) => { })]);
  Thread.run([(Func) (%!(void) => { }), (Func) (%!(void) => 17)],
    %!(Var result) using &calls, &voids => {
      calls++;
      if (result is void) voids++;
    });
  EXPECT_INT_EQ(calls, 2);
  EXPECT_INT_EQ(voids, 1);
}

static void batch_results_outlive_joined_handles(void) {
  $test.scoped();
  Map saved = NULL;
  Scope output = Scope.child();
  Thread.run([(Func) (%!(void) => {
    Map result = {};
    result[String.printf("batch-result-%d", 31)] = 31;
    Scope owner = output;
    result.move_to(&owner);
    return result;
  })], %!(Var result) using &saved => saved = result);
  EXPECT_INT_EQ(saved["batch-result-31"].integer(), 31);
  EXPECT_PTR_EQ(Scope.owner(saved), output);
  saved["later"] = 32;
  EXPECT_INT_EQ(saved["later"].integer(), 32);
}

static void batch_jobs_use_process_pool(void) {
  $test.scoped();
  String borrowed = NULL;
  Pool private = Pool.open_named("batch caller private");
  defer Pool.close();
  Thread.run([%!(void) using &borrowed => {
    borrowed = String.printf("batch-process-pool-%d", 8765);
    return Pool.is_permanent(borrowed);
  }], %!(Var result) => { EXPECT_TRUE(result.integer()); });
  EXPECT_TRUE(Pool.is_permanent(borrowed));
  EXPECT_STR_EQ(borrowed, "batch-process-pool-8765");
}

static void batch_partial_startup_stops_started_jobs(void) {
  $test.scoped();
  _batch_reset();
  int caught = 0;
  Array jobs = [(Func) _batch_wait_for_stop, 42];
  try Thread.run(jobs);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(atomic_load(&batch_finished), 1);
}

static Var _batch_wait_with_cleanup_barrier(void) {
  defer {
    atomic_fetch_add(&batch_cleanup_barrier, 1);
    while (atomic_load(&batch_cleanup_barrier) < 2) sched_yield();
  }
  return _batch_wait_for_stop();
}

static void batch_worker_failure_stops_all_peers(void) {
  $test.scoped();
  _batch_reset();
  int caught = 0, completions = 0;
  Array jobs = [
    (Func) _batch_wait_with_cleanup_barrier,
    (Func) _batch_wait_with_cleanup_barrier,
    (Func) (%!(void) => {
      _batch_wait_ready(2);
      raise %(batch-fail (detail "original worker failure"));
    })
  ];
  try Thread.run(jobs,
    %!(Var result) using &completions => ++completions);
  catch %(join-fail (errors ?errors)): {
    List first = errors.list().car();
    caught = first.assoc(<code>) == <batch-fail>;
  }
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(atomic_load(&batch_finished), 2);
  EXPECT_INT_EQ(completions, 0);
}

static void batch_callback_failure_stops_all_peers(void) {
  $test.scoped();
  _batch_reset();
  int caught = 0;
  Array jobs = [
    (Func) _batch_wait_for_stop,
    (Func) (%!(void) => { _batch_wait_ready(1); return 19; })
  ];
  try Thread.run(jobs, %!(Var result) => {
    raise %(cb-fail (detail "original callback failure"));
  });
  catch %(cb-fail *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(atomic_load(&batch_finished), 1);
}

static void batch_does_not_invoke_result_exporter(void) {
  $test.scoped();
  Scope output = Scope.child();
  int completed = 0;
  Thread.run([%!(void) => {
    Scope owner = output;
    ContextProbe probe = Scope.malloc_in(&owner, sizeof(struct ContextProbe));
    probe.value = 23;
    probe.exports = 0;
    probe.fail_at = 1;
    return Var.new(<ctxprobe>, probe);
  }], %!(Var value) using &completed => {
    ContextProbe probe = value;
    EXPECT_INT_EQ(probe.exports, 0);
    EXPECT_INT_EQ(probe.value.int(), 23);
    completed++;
  });
  EXPECT_INT_EQ(completed, 1);
}

static Var _batch_nested_worker(const void *bytes, size_t size) {
  (void) bytes;
  (void) size;
  Thread.run([(Func) _batch_wait_for_stop]);
  return void;
}

static void batch_nested_coordinator_stop_cleans_children(void) {
  $test.scoped();
  _batch_reset();
  Thread coordinator = Thread.start_raw(_batch_nested_worker, NULL, 0);
  _batch_wait_ready(1);
  coordinator.stop();
  int caught = 0;
  try coordinator.join();
  catch %(join-fail *): caught = 1;
  coordinator.free();
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(atomic_load(&batch_finished), 1);
}

static Var _batch_stopped_before_launch(const void *bytes, size_t size) {
  (void) bytes;
  (void) size;
  x2c_thread_wait_lock();
  Thread self = x2c_thread_wait_owner();
  x2c_thread_wait_unlock();
  self.stop();
  int started = 0, caught = 0;
  try Thread.run([%!(void) using &started => ++started]);
  catch %(bad-state (operation "Thread.stop") (cancelled 1)): caught = 1;
  return caught && !started;
}

static void batch_pending_stop_prevents_startup(void) {
  Thread coordinator = Thread.start_raw(_batch_stopped_before_launch, NULL, 0);
  EXPECT_TRUE(coordinator.join().integer());
  coordinator.free();
}

static void batch_explicit_private_pool_result_exports(void) {
  $test.scoped();
  String result = NULL;
  Thread.run([(Func) (%!(void) => {
    Context private = Context.open_isolated_named("explicit batch private");
    String value = String.printf("explicit-batch-private-%d", 9301);
    Var exported = private.export(value);
    private.close();
    return exported;
  })], %!(Var value) using &result => result = value);
  EXPECT_STR_EQ(result, "explicit-batch-private-9301");
  EXPECT_TRUE(Pool.is_permanent(result));
}

static atomic_int batch_temporary_drops, batch_owned_drops;

static void _batch_drop_temporary(void *value) {
  (void) value;
  atomic_fetch_add(&batch_temporary_drops, 1);
}

static void _batch_drop_owned(void *value) {
  (void) value;
  atomic_fetch_add(&batch_owned_drops, 1);
}

static void batch_failure_preserves_explicit_owner(void) {
  $test.scoped();
  Scope output = Scope.child();
  atomic_store(&batch_temporary_drops, 0);
  atomic_store(&batch_owned_drops, 0);
  int caught = 0;
  try Thread.run([%!(void) => {
    Scope owner = output;
    Scope.malloc_finalized(8, _batch_drop_temporary);
    Scope.malloc_finalized_in(&owner, 8, _batch_drop_owned);
    raise %(batch-fail (detail "after explicit allocation"));
  }]);
  catch %(join-fail *): caught = 1;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(atomic_load(&batch_temporary_drops), 1);
  EXPECT_INT_EQ(atomic_load(&batch_owned_drops), 0);
  output.destroy();
  EXPECT_INT_EQ(atomic_load(&batch_owned_drops), 1);
}

void thread_batch_suite(void) {
  $test.run(batch_failure_preserves_explicit_owner);
  $test.run(batch_pending_stop_prevents_startup);
  $test.run(batch_explicit_private_pool_result_exports);
  $test.run(batch_empty_and_void_results);
  $test.run(batch_results_outlive_joined_handles);
  $test.run(batch_jobs_use_process_pool);
  $test.run(batch_partial_startup_stops_started_jobs);
  $test.run(batch_worker_failure_stops_all_peers);
  $test.run(batch_callback_failure_stops_all_peers);
  $test.run(batch_does_not_invoke_result_exporter);
  $test.run(batch_nested_coordinator_stop_cleans_children);
}
