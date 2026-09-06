#include "x2c.x"

static void raise_io(void) {
  raise %(io-fail (operation read));
}

// Leaving a try must leave its exception frame before running a defer that
// was registered outside it. Running the outer defer first drops the frame's
// cleanup watermark below its own entries and aborts the process.
static int return_from_catch(void) {
  defer printf("catch-outer\n");
  try { raise_io(); }
  catch %(io-fail *): {
    printf("caught\n");
    return 2;
  }
  return 0;
}

static int return_from_body(void) {
  defer printf("body-outer\n");
  try {
    printf("body\n");
    return 3;
  }
  catch %(io-fail *): return 4;
  return 0;
}

static int return_with_finally(void) {
  defer printf("finally-outer\n");
  try { raise_io(); }
  catch %(io-fail *): return 5;
  finally { printf("finally\n"); }
  return 0;
}

int main(void) {
  int from_catch = return_from_catch();
  int from_body = return_from_body();
  int with_finally = return_with_finally();
  printf("%d %d %d\n", from_catch, from_body, with_finally);
  return from_catch == 2 && from_body == 3 && with_finally == 5 ? 0 : 1;
}
