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

static int _locked_return(Mutex mutex) {
  $lock(mutex) { return 9; }
}

static void mutex_system_lock_evaluation_and_transfer(void) {
  Mutex mutex = $auto(Mutex.new());
  int evaluations = 0, caught = 0;
  try {
    $lock((evaluations++, mutex)) {
      EXPECT_FALSE(mutex.try_lock());
      raise %(invariant);
    }
  }
  catch %(invariant): { caught = 1; }
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(evaluations, 1);
  EXPECT_TRUE(mutex.try_lock());
  mutex.unlock();
  EXPECT_INT_EQ(_locked_return(mutex), 9);
  EXPECT_TRUE(mutex.try_lock());
  mutex.unlock();
}

static void mutex_system_lock_failed_acquisition(void) {
  int caught = 0;
  try {
    $lock((Mutex) NULL) { TEST_FAIL("failed lock entered body"); }
  }
  catch %(bad-state (owner ?owner)): {
    EXPECT_STR_EQ(owner.str(), "Mutex.lock");
    caught = 1;
  }
  EXPECT_INT_EQ(caught, 1);
}

$(import "test-macros.xmacro")

void mutex_suite(void) {
  $test.run(mutex_system_lock_evaluation_and_transfer);
  $test.run(mutex_system_lock_failed_acquisition);
  $test.run(mutex_lock_try_unlock);
}
