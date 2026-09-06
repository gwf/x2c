#include "x2c.x"

static void raise_io(void) {
  raise %(io-fail (operation read));
}

// A defer registered inside a try must not borrow the try's run-once guard.
// Sharing it let the defer's cleanup set the guard to -1 first, so the
// finally body and the frame's x2c_exception_leave were both skipped on
// every structured exit out of the try.
static int return_from_body(void) {
  try {
    defer printf("return-defer\n");
    printf("return-body\n");
    return 2;
  }
  finally { printf("return-finally\n"); }
  return 0;
}

static int return_from_catch(void) {
  try { raise_io(); }
  catch %(io-fail *): {
    defer printf("catch-defer\n");
    return 3;
  }
  finally { printf("catch-finally\n"); }
  return 0;
}

static int break_from_body(void) {
  int rounds = 0;
  for (int i = 0; i < 3; i++) {
    try {
      defer printf("break-defer\n");
      rounds++;
      if (i == 1) break;
    }
    finally { printf("break-finally\n"); }
  }
  return rounds;
}

static int goto_from_body(void) {
  try {
    defer printf("goto-defer\n");
    goto done;
  }
  finally { printf("goto-finally\n"); }
done:
  return 5;
}

// The guard belongs to one try, so nesting still leaves the inner frame
// before the outer defer runs.
static int nested_return(void) {
  try {
    defer printf("outer-defer\n");
    try {
      defer printf("inner-defer\n");
      return 8;
    }
    finally { printf("inner-finally\n"); }
  }
  finally { printf("outer-finally\n"); }
  return 0;
}

int main(void) {
  int body = return_from_body();
  int caught = return_from_catch();
  int broken = break_from_body();
  int jumped = goto_from_body();
  int nested = nested_return();
  printf("%d %d %d %d %d\n", body, caught, broken, jumped, nested);
  return body == 2 && caught == 3 && broken == 2 && jumped == 5 &&
         nested == 8 ? 0 : 1;
}
