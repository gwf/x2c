#include "x2c.x"

static int steps = 0;

/* A finalizer that raises reaches the enclosing frame instead of re-entering
   its own landing and running the finalizer again. */
static void raises_from_finally(void) {
  try {
    steps = steps * 10 + 1;
  }
  finally {
    steps = steps * 10 + 2;
    raise %(from-fin);
  }
}

/* A finalizer that raises while already carrying an Error replaces it. */
static void replaces_pending_error(void) {
  try {
    raise %(pending);
  }
  finally {
    steps = steps * 10 + 3;
    raise %(from-fin);
  }
}

/* A nested try inside a finalizer handles its own Error, and the transfer
   the finalizer was running for continues outward. */
static void nested_try_in_finally(void) {
  try {
    raise %(pending);
  }
  finally {
    try {
      raise %(nested);
    }
    catch %(nested): {
      steps = steps * 10 + 4;
    }
    steps = steps * 10 + 5;
  }
}

int main(void) {
  try {
    raises_from_finally();
  }
  catch %(from-fin): {
    printf("caught from-fin\n");
  }
  try {
    replaces_pending_error();
  }
  catch %(from-fin): {
    printf("replaced pending\n");
  }
  catch %(pending): {
    printf("pending survived\n");
  }
  try {
    nested_try_in_finally();
  }
  catch %(pending): {
    printf("pending reached outer\n");
  }
  printf("steps %d\n", steps);
  return 0;
}
