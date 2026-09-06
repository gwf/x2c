/*  test-mutex.x -- native Mutex tests */

#include "test-support.x"

static void mutex_lock_try_unlock(void) {
  Mutex mutex = Mutex.new();
  EXPECT_TRUE(mutex.try_lock());
  EXPECT_FALSE(mutex.try_lock());
  mutex.unlock();
  mutex.lock();
  mutex.unlock();
  mutex.free();
}

$(import "test-macros.xmacro")

void mutex_suite(void) {
  $test.run(mutex_lock_try_unlock);
}
