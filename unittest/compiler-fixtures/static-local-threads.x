#include "x2c.x"
#include <pthread.h>

static int calls;
static int initial(void) { return __atomic_add_fetch(&calls, 1, __ATOMIC_SEQ_CST); }
static int value(void) { static const int result = initial(); return result; }
static void *worker(void *unused) {
  (void)unused;
  return (void *)(long)value();
}
static int recurse(void) { static int result = recurse(); return result; }
static int local(void) {
  static threaded int result = initial();
  return result;
}
static void *thread_local_value(void *unused) {
  (void)unused;
  int first = local(), second = local();
  return (void *)(long)(first == second);
}
int main(void) {
  pthread_t threads[8];
  for (int i = 0; i < 8; i++) pthread_create(&threads[i], NULL, worker, NULL);
  int total = 0;
  for (int i = 0; i < 8; i++) {
    void *result;
    pthread_join(threads[i], &result);
    total += (int)(long)result;
  }
  int once = calls, caught = 0;
  try { recurse(); }
  catch %(bad-state *): { caught = 1; }
  for (int i = 0; i < 8; i++)
    pthread_create(&threads[i], NULL, thread_local_value, NULL);
  int independent = 0;
  for (int i = 0; i < 8; i++) {
    void *result;
    pthread_join(threads[i], &result);
    independent += (int)(long)result;
  }
  printf("%d %d %d %d %d\n", once, total, caught, independent, calls);
  return 0;
}
