#include "x2c.x"

static int calls;

int try(int n) { calls++; return n + 1; }
int catch(int n) { calls++; return n + 1; }
int finally(int n) { calls++; return n + 1; }
int raise(int n) { calls++; return n + 1; }
int import(int n) { calls++; return n + 1; }
int protocol(int n) { calls++; return n + 1; }
int delegate(int n) { calls++; return n + 1; }
int associated(int n) { calls++; return n + 1; }
int threaded(int n) { calls++; return n + 1; }
int with(int n) { calls++; return n + 1; }

int main(void) {
  int total = 0;
  total += try(1);
  try(2);
  total += catch(1);
  catch(2);
  total += finally(1);
  finally(2);
  total += raise(1);
  raise(2);
  total += import(1);
  import(2);
  total += protocol(1);
  protocol(2);
  total += delegate(1);
  delegate(2);
  total += associated(1);
  associated(2);
  total += threaded(1);
  threaded(2);
  total += with(1);
  with(2);
  if (total != 20 || calls != 20) return 1;
  {
    int macro_calls = 0;
    macro Stmt try() { macro_calls++; }
    try();
    if (macro_calls != 1) return 8;
  }
  int value = 0;
  with (value = 7) {
    if (value != 7) return 2;
  }
  if (value != 0) return 3;
  try {
    raise %(ctx-test);
  }
  catch %(ctx-test): { value = 1; catch(3); }
  finally { value += 2; finally(4); }
  if (value != 3 || calls != 22) return 4;
  try value++;
  finally { value++; }
  try { value++; }
  catch: { return 5; }
  if (value != 6) return 6;
  int ordinary = 19;
  total = (raise)(ordinary) % (7);
  if (total != 6) return 7;
  printf("names %d calls %d value %d\n", 20, calls, value);
  return 0;
}
