/*  test-static-init.x -- dynamic local static storage and publication */

#include "test-support.x"
#include "static-init.x"
#include <sched.h>
#include <stdint.h>
#include <unistd.h>
$(import "test-macros.xmacro")

static X2CStatic aligned_guard, retry_guard, recursive_guard;
static X2CStatic concurrent_guard, cycle_guards[2];
static int concurrent_calls, cycle_arrived;
static int *failed_address;

static void static_storage_outlives_context(void) {
  Context context = Context.open_isolated_named("static storage");
  int acquired = x2c_static_acquire(&aligned_guard, sizeof(int), 1024, 0);
  EXPECT_TRUE(acquired);
  {
    defer x2c_static_abort(&aligned_guard);
    int *value = aligned_guard.payload;
    EXPECT_INT_EQ((uintptr_t) value % 1024, 0);
    EXPECT_INT_EQ(*value, 0);
    *value = 73;
    x2c_static_commit(&aligned_guard);
  }
  context.close();
  EXPECT_FALSE(x2c_static_acquire(&aligned_guard, sizeof(int), 1024, 0));
  EXPECT_INT_EQ(*(int *) aligned_guard.payload, 73);
}

static void _failed_initializer(void) {
  if (x2c_static_acquire(
    &retry_guard, sizeof(int), _Alignof(max_align_t), 0)) {
    defer x2c_static_abort(&retry_guard);
    failed_address = retry_guard.payload;
    *(int *) retry_guard.payload = 19;
    raise %(init-test);
  }
}

static void static_error_preserves_address_and_retries(void) {
  int caught = 0;
  try _failed_initializer();
  catch %(init-test): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_PTR_EQ(retry_guard.payload, failed_address);
  EXPECT_INT_EQ(retry_guard.ready, 0);
  int *intervening = malloc(sizeof(int));
  defer free(intervening);
  EXPECT_TRUE(intervening != failed_address);
  EXPECT_TRUE(x2c_static_acquire(
    &retry_guard, sizeof(int), _Alignof(max_align_t), 0));
  {
    defer x2c_static_abort(&retry_guard);
    EXPECT_PTR_EQ(retry_guard.payload, failed_address);
    EXPECT_INT_EQ(*(int *) retry_guard.payload, 0);
    *(int *) retry_guard.payload = 41;
    x2c_static_commit(&retry_guard);
  }
  EXPECT_INT_EQ(*(int *) retry_guard.payload, 41);
}

static void _recursive_initializer(void) {
  if (x2c_static_acquire(
    &recursive_guard, sizeof(int), _Alignof(max_align_t), 0)) {
    defer x2c_static_abort(&recursive_guard);
    x2c_static_acquire(
      &recursive_guard, sizeof(int), _Alignof(max_align_t), 0);
  }
}

static void static_recursive_initialization_transfers(void) {
  int caught = 0;
  try _recursive_initializer();
  catch %(bad-state *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(recursive_guard.payload != NULL);
  EXPECT_TRUE(x2c_static_acquire(
    &recursive_guard, sizeof(int), _Alignof(max_align_t), 0));
  x2c_static_commit(&recursive_guard);
}

static Var _concurrent_initializer(const void *input, size_t size) {
  (void) input;
  (void) size;
  if (x2c_static_acquire(
    &concurrent_guard, sizeof(int), _Alignof(max_align_t), 0)) {
    defer x2c_static_abort(&concurrent_guard);
    __atomic_add_fetch(&concurrent_calls, 1, __ATOMIC_RELAXED);
    usleep(20000);
    *(int *) concurrent_guard.payload = 97;
    x2c_static_commit(&concurrent_guard);
  }
  return *(int *) concurrent_guard.payload;
}

static void static_concurrent_initialization_publishes_once(void) {
  Thread workers[8];
  for (int i = 0; i < 8; i++)
    workers[i] = Thread.start(_concurrent_initializer, NULL, 0);
  for (int i = 0; i < 8; i++) {
    EXPECT_INT_EQ(workers[i].join().int(), 97);
    workers[i].free();
  }
  EXPECT_INT_EQ(concurrent_calls, 1);
}

static Var _cyclic_initializer(const void *input, size_t size) {
  (void) size;
  int index = *(const int *) input;
  X2CStatic *own = &cycle_guards[index], *other = &cycle_guards[1 - index];
  if (!x2c_static_acquire(own, sizeof(int), _Alignof(max_align_t), 0))
    return -1;
  defer x2c_static_abort(own);
  __atomic_add_fetch(&cycle_arrived, 1, __ATOMIC_RELEASE);
  while (__atomic_load_n(&cycle_arrived, __ATOMIC_ACQUIRE) != 2)
    sched_yield();
  try {
    if (x2c_static_acquire(other, sizeof(int), _Alignof(max_align_t), 0)) {
      defer x2c_static_abort(other);
      *(int *) other.payload = 31;
      x2c_static_commit(other);
    }
    *(int *) own.payload = 31;
    x2c_static_commit(own);
  }
  catch %(bad-state *): return 0;
  return 1;
}

static void static_cross_thread_cycle_transfers_and_wakes_waiter(void) {
  int first = 0, second = 1;
  Thread a = Thread.start(_cyclic_initializer, &first, sizeof(first));
  Thread b = Thread.start(_cyclic_initializer, &second, sizeof(second));
  int successes = a.join().int() + b.join().int();
  a.free();
  b.free();
  EXPECT_INT_EQ(successes, 1);
  EXPECT_INT_EQ(*(int *) cycle_guards[0].payload, 31);
  EXPECT_INT_EQ(*(int *) cycle_guards[1].payload, 31);
}

static Var _thread_local_initializer(const void *input, size_t size) {
  (void) size;
  static threaded X2CStatic guard;
  if (!x2c_static_acquire(&guard, sizeof(int), _Alignof(max_align_t), 1))
    return 0;
  {
    defer x2c_static_abort(&guard);
    *(int *) guard.payload = *(const int *) input;
    x2c_static_commit(&guard);
  }
  int value = *(int *) guard.payload;
  x2c_static_thread_release();
  if (guard.payload || guard.ready) return 0;
  if (!x2c_static_acquire(&guard, sizeof(int), _Alignof(max_align_t), 1))
    return 0;
  x2c_static_abort(&guard);
  x2c_static_thread_release();
  if (guard.payload || guard.ready) return 0;
  return value;
}

static void static_threaded_storage_releases_with_thread(void) {
  int first = 17, second = 29;
  Thread a = Thread.start(_thread_local_initializer, &first, sizeof(first));
  Thread b = Thread.start(_thread_local_initializer, &second, sizeof(second));
  EXPECT_INT_EQ(a.join().int(), first);
  EXPECT_INT_EQ(b.join().int(), second);
  a.free();
  b.free();
}

static void static_uncommitted_process_storage_releases(void) {
  static X2CStatic guard;
  EXPECT_TRUE(x2c_static_acquire(
    &guard, sizeof(int), _Alignof(max_align_t), 0));
  x2c_static_abort(&guard);
  EXPECT_TRUE(guard.payload != NULL);
  x2c_static_shutdown();
  EXPECT_NULL(guard.payload);
  EXPECT_INT_EQ(guard.ready, 0);
}

void static_init_suite(void) {
  $test.run(static_storage_outlives_context);
  $test.run(static_error_preserves_address_and_retries);
  $test.run(static_recursive_initialization_transfers);
  $test.run(static_concurrent_initialization_publishes_once);
  $test.run(static_cross_thread_cycle_transfers_and_wakes_waiter);
  $test.run(static_threaded_storage_releases_with_thread);
  $test.run(static_uncommitted_process_storage_releases);
}
