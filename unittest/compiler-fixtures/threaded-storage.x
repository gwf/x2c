#include "x2c.x"
#include <pthread.h>

/* `threaded` is x2c's spelling of C's thread-local storage class. The two C
   spellings mean the same thing and are accepted so that C using either
   passes through unchanged. It pairs with `static` or `extern` in either
   order, which is the only pairing C allows. */

threaded int visible;
static threaded int hidden;
threaded static int reordered;
static _Thread_local int legacy;
static thread_local int c23;

static void *worker(void *unused) {
  (void) unused;
  hidden = 7;
  reordered = 8;
  legacy = 9;
  c23 = 10;
  visible = hidden + reordered + legacy + c23;
  printf("worker %d\n", visible);
  return NULL;
}

int main(void) {
  hidden = 1;
  reordered = 1;
  legacy = 1;
  c23 = 1;
  visible = 4;
  pthread_t thread;
  if (pthread_create(&thread, NULL, worker, NULL)) return 1;
  if (pthread_join(thread, NULL)) return 1;
  // Each thread owns its own copy, so the worker's writes are invisible here.
  printf("main %d %d %d %d %d\n", visible, hidden, reordered, legacy, c23);
  return 0;
}
