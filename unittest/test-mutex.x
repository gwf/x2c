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
  Mutex mutex = auto Mutex.new();
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
  String raised = NULL;
  try {
    $lock((Mutex) NULL) { TEST_FAIL("failed lock entered body"); }
  }
  catch %(?code (operation ?op) *): raised = %"$code $op";
  EXPECT_STR_EQ(raised, "bad-arg Mutex.lock");
}

/* Operations on a null Mutex raise; free and cleanup do nothing. */
static void mutex_null_handle_contract(void) {
  Mutex mutex = NULL;
  String raised = NULL;
  try mutex.lock();
  catch %(?code (operation ?op) *): raised = %"$raised$code $op; ";
  try mutex.try_lock();
  catch %(?code (operation ?op) *): raised = %"$raised$code $op; ";
  try mutex.unlock();
  catch %(?code (operation ?op) *): raised = %"$raised$code $op; ";
  try mutex.free();
  catch %(?code (operation ?op) *): raised = %"$raised$code $op; ";
  try mutex.cleanup();
  catch %(?code (operation ?op) *): raised = %"$raised$code $op; ";
  EXPECT_STR_EQ(raised,
    "bad-arg Mutex.lock; bad-arg Mutex.try_lock; bad-arg Mutex.unlock; ");
}

#include "test-macros.x"

void mutex_suite(void) {
  $test.run(mutex_system_lock_evaluation_and_transfer);
  $test.run(mutex_system_lock_failed_acquisition);
  $test.run(mutex_lock_try_unlock);
  $test.run(mutex_null_handle_contract);
}
